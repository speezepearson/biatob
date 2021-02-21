port module ViewUserPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import API
import SmallInvitationWidget
import ViewPredictionsWidget
import CopyWidget

port trustChanged : () -> Cmd msg

type alias Model =
  { userId : Pb.UserId
  , userView : Pb.UserUserView
  , auth : Maybe Pb.AuthToken
  , predictionsWidget : Maybe ViewPredictionsWidget.Model
  , working : Bool
  , setTrustedError : Maybe String
  , httpOrigin : String
  , invitationWidget : SmallInvitationWidget.State
  }

type Msg
  = SetTrusted Bool
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)
  | PredictionsMsg ViewPredictionsWidget.Msg
  | InvitationEvent SmallInvitationWidget.Event SmallInvitationWidget.State
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)

invitationWidgetCtx : Model -> SmallInvitationWidget.Context Msg
invitationWidgetCtx model =
  { destination = Nothing
  , httpOrigin = model.httpOrigin
  , handle = InvitationEvent
  }

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    httpOrigin = Utils.mustDecodeFromFlags JD.string "httpOrigin" flags
    auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    (predsWidget, predsCmd) = case auth of
      Just _ -> case Utils.decodePbFromFlags Pb.predictionsByIdDecoder "predictionsPbB64" flags of
        Just preds ->
          ViewPredictionsWidget.init
            { auth=auth
            , httpOrigin=httpOrigin
            , predictions=preds.predictions |> Utils.mustMapValues
            }
          |> Tuple.mapFirst (ViewPredictionsWidget.noFilterByOwner >> Just)
        Nothing -> ( Nothing, Cmd.none )
      Nothing -> ( Nothing, Cmd.none )
  in
  ( { userId = Utils.mustDecodePbFromFlags Pb.userIdDecoder "userIdPbB64" flags
    , userView = Utils.mustDecodePbFromFlags Pb.userUserViewDecoder "userViewPbB64" flags
    , auth = auth
    , predictionsWidget = predsWidget
    , working = False
    , setTrustedError = Nothing
    , httpOrigin = httpOrigin
    , invitationWidget = SmallInvitationWidget.init
    }
  , Cmd.map PredictionsMsg predsCmd
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetTrusted trusted ->
      ( { model | working = True , setTrustedError = Nothing }
      , API.postSetTrusted SetTrustedFinished {who=Just model.userId, trusted=trusted}
      )
    SetTrustedFinished (Err e) ->
      ( { model | working = False , setTrustedError = Just (Debug.toString e) }
      , Cmd.none
      )
    SetTrustedFinished (Ok resp) ->
      case resp.setTrustedResult of
        Just (Pb.SetTrustedResultOk _) ->
          ( model
          , trustChanged ()
          )
        Just (Pb.SetTrustedResultError e) ->
          ( { model | working = False , setTrustedError = Just (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , setTrustedError = Just "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )
    PredictionsMsg widgetMsg ->
      case model.predictionsWidget of
        Just widget ->
          let (newWidget, widgetCmd) = ViewPredictionsWidget.update widgetMsg widget in
          ( { model | predictionsWidget = Just newWidget }
          , Cmd.map PredictionsMsg widgetCmd
          )
        Nothing -> Debug.todo "bad state"

    InvitationEvent event newWidget ->
      (case event of
        SmallInvitationWidget.CreateInvitation ->
          (model, API.postCreateInvitation CreateInvitationFinished {notes = ""})  -- TODO(P3): add notes field
        SmallInvitationWidget.Copy s ->
          (model, CopyWidget.copy s)
        SmallInvitationWidget.Nevermind ->
          (model, Cmd.none)
      ) |> Tuple.mapFirst (\m -> { m | invitationWidget = newWidget })
    CreateInvitationFinished res ->
      ( { model | invitationWidget = model.invitationWidget |> SmallInvitationWidget.handleCreateInvitationResponse (model.auth |> Utils.must "should only be able to send CreateInvitationRequests when logged in") res }
      , Cmd.none
      )

view : Model -> Html Msg
view model =
  H.div []
    [ H.h2 [] [H.text model.userView.displayName]
    , H.br [] []
    , if model.userView.isSelf then
        H.div []
          [ H.text "This is you! You might have meant to visit "
          , H.a [HA.href "/settings"] [H.text "your settings"]
          , H.text "?"
          ]
      else case model.auth of
        Nothing ->
          H.text "Log in to see your relationship with this user."
        Just _ ->
          H.div []
            [ if model.userView.trustsYou then
                H.text "This user trusts you! :)"
              else
                H.div []
                  [ H.text "This user hasn't marked you as trusted! If you think that, in real life, they "
                  , H.i [] [H.text "do"]
                  , H.text " trust you, send them an invitation: "
                  , SmallInvitationWidget.view (invitationWidgetCtx model) model.invitationWidget
                  ]
            , H.br [] []
            , if model.userView.isTrusted then
                H.div []
                  [ H.text "You trust this user. "
                  , H.button [HA.disabled model.working, HE.onClick (SetTrusted False)] [H.text "Mark untrusted"]
                  ]
              else
                H.div []
                  [ H.text "You don't trust this user. "
                  , H.button [HA.disabled model.working, HE.onClick (SetTrusted True)] [H.text "Mark trusted"]
                  ]
            , case model.setTrustedError of
                Just e -> H.div [HA.style "color" "red"] [H.text e]
                Nothing -> H.text ""
            , H.br [] []
            , H.h3 [] [H.text "Predictions"]
            , case model.predictionsWidget of
                Nothing -> H.text "No predictions to show."
                Just widget -> ViewPredictionsWidget.view widget |> H.map PredictionsMsg
            ]
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
