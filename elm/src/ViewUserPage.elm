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

port trustChanged : () -> Cmd msg

type AuthState = LoggedIn Pb.AuthToken SmallInvitationWidget.Model | LoggedOut
type alias Model =
  { userId : Pb.UserId
  , userView : Pb.UserUserView
  , authState : AuthState
  , predictionsWidget : Maybe ViewPredictionsWidget.Model
  , working : Bool
  , setTrustedError : Maybe String
  }

type Msg
  = SetTrusted Bool
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)
  | InvitationMsg SmallInvitationWidget.Msg
  | PredictionsMsg ViewPredictionsWidget.Msg

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    linkToAuthority = Utils.mustDecodeFromFlags JD.string "linkToAuthority" flags
    auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    (predsWidget, predsCmd) = case auth of
      Just auth_ -> case Utils.decodePbFromFlags Pb.predictionsByIdDecoder "predictionsPbB64" flags of
        Just preds ->
          ViewPredictionsWidget.init
            { auth=auth_
            , linkToAuthority=linkToAuthority
            , predictions=preds.predictions |> Utils.mustMapValues
            }
          |> Tuple.mapFirst (ViewPredictionsWidget.noFilterByOwner >> Just)
        Nothing -> ( Nothing, Cmd.none )
      Nothing -> ( Nothing, Cmd.none )
  in
  ( { userId = Utils.mustDecodePbFromFlags Pb.userIdDecoder "userIdPbB64" flags
    , userView = Utils.mustDecodePbFromFlags Pb.userUserViewDecoder "userViewPbB64" flags
    , authState = case auth of
        Just auth_ -> LoggedIn auth_ (SmallInvitationWidget.init {auth=auth_, linkToAuthority=linkToAuthority})
        Nothing -> LoggedOut
    , predictionsWidget = predsWidget
    , working = False
    , setTrustedError = Nothing
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
    InvitationMsg widgetMsg ->
      case model.authState of
        LoggedIn auth widget ->
          let (newWidget, widgetCmd) = SmallInvitationWidget.update widgetMsg widget in
          ( { model | authState = LoggedIn auth newWidget }
          , Cmd.map InvitationMsg widgetCmd
          )
        LoggedOut -> Debug.todo "bad state"
    PredictionsMsg widgetMsg ->
      case model.predictionsWidget of
        Just widget ->
          let (newWidget, widgetCmd) = ViewPredictionsWidget.update widgetMsg widget in
          ( { model | predictionsWidget = Just newWidget }
          , Cmd.map PredictionsMsg widgetCmd
          )
        Nothing -> Debug.todo "bad state"


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
      else case model.authState of
        LoggedOut ->
          H.text "Log in to see your relationship with this user."
        LoggedIn _ invitationWidget ->
          H.div []
            [ if model.userView.trustsYou then
                H.text "This user trusts you! :)"
              else
                H.div []
                  [ H.text "This user hasn't marked you as trusted! If you think that, in real life, they "
                  , H.i [] [H.text "do"]
                  , H.text " trust you, send them an invitation: "
                  , SmallInvitationWidget.view invitationWidget |> H.map InvitationMsg
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
