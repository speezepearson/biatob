module Elements.ViewUser exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD
import Dict

import Biatob.Proto.Mvp as Pb
import Utils exposing (Username)

import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Widgets.ViewPredictionsWidget as ViewPredictionsWidget
import Page
import Page.Program
import Page exposing (Command(..))

type alias Model =
  { username : Username
  , predictionsWidget : ViewPredictionsWidget.Model
  , working : Bool
  , notification : Html Never
  , invitationWidget : SmallInvitationWidget.State
  }

type Msg
  = SetTrusted Bool
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)
  | PredictionsMsg ViewPredictionsWidget.Msg
  | SetInvitationWidget SmallInvitationWidget.State
  | CreateInvitation SmallInvitationWidget.State Pb.CreateInvitationRequest
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)
  | Copy String

init : JD.Value -> (Model, Page.Command Msg)
init flags =
  let
    predsWidget =
      case Utils.decodePbFromFlags Pb.predictionsByIdDecoder "predictionsPbB64" flags of
        Nothing -> ViewPredictionsWidget.init (Dict.empty)
        Just preds ->
          ViewPredictionsWidget.init (Utils.mustMapValues preds.predictions)
          |> ViewPredictionsWidget.noFilterByOwner
  in
  ( { username = Utils.mustDecodeFromFlags JD.string "who" flags
    , predictionsWidget = predsWidget
    , working = False
    , notification = H.text ""
    , invitationWidget = SmallInvitationWidget.init
    }
  , Page.NoCmd
  )

update : Msg -> Model -> (Model, Page.Command Msg)
update msg model =
  case msg of
    SetTrusted trusted ->
      ( { model | working = True , notification = H.text "" }
      , Page.RequestCmd <| Page.SetTrustedRequest SetTrustedFinished {who=model.username, whoDepr=Nothing, trusted=trusted}
      )
    SetTrustedFinished res ->
      ( case res of
          Err e ->
            { model | working = False , notification = Utils.redText (Debug.toString e) }
          Ok resp ->
            case resp.setTrustedResult of
              Just (Pb.SetTrustedResultOk _) ->
                { model | working = False, notification = H.text "" }
              Just (Pb.SetTrustedResultError e) ->
                { model | working = False , notification = Utils.redText (Debug.toString e) }
              Nothing ->
                { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
      , Page.NoCmd
      )
    PredictionsMsg widgetMsg ->
        let (newWidget, widgetCmd) = ViewPredictionsWidget.update widgetMsg model.predictionsWidget in
        ( { model | predictionsWidget = newWidget }
        , Page.mapCmd PredictionsMsg widgetCmd
        )
    SetInvitationWidget widgetState ->
      ( { model | invitationWidget = widgetState } , Page.NoCmd )
    CreateInvitation widgetState req ->
      ( { model | invitationWidget = widgetState }
      , Page.RequestCmd <| Page.CreateInvitationRequest CreateInvitationFinished req
      )
    CreateInvitationFinished res ->
      ( { model | invitationWidget = model.invitationWidget |> SmallInvitationWidget.handleCreateInvitationResponse res }
      , Page.NoCmd
      )
    Copy s ->
      ( model
      , Page.CopyCmd s
      )


view : Page.Globals -> Model -> Browser.Document Msg
view globals model =
  {title=model.username, body=[H.main_ []
    [ H.h2 [] [H.text model.username]
    , H.br [] []
    , if Page.isSelf globals model.username then
        H.div []
          [ H.text "This is you! You might have meant to visit "
          , H.a [HA.href "/settings"] [H.text "your settings"]
          , H.text "?"
          ]
      else case globals.serverState.settings of
        Nothing -> H.text "Log in to see your relationship with this user."
        Just _ ->
          H.div []
            [ if Page.getRelationship globals model.username |> Maybe.map .trusting |> Maybe.withDefault False then
                H.text "This user trusts you! :)"
              else
                H.div []
                  [ H.text "This user hasn't marked you as trusted! If you think that, in real life, they "
                  , Utils.i "do"
                  , H.text " trust you, send them an invitation: "
                  , SmallInvitationWidget.view
                      { setState = SetInvitationWidget
                      , createInvitation = CreateInvitation
                      , copy = Copy
                      , destination = Just <| "/username/" ++ model.username
                      , httpOrigin = globals.httpOrigin
                      }
                      model.invitationWidget
                  ]
            , H.br [] []
            , if Page.getRelationship globals model.username |> Maybe.map .trusted |> Maybe.withDefault False then
                H.div []
                  [ H.text "You trust this user. "
                  , H.button [HA.disabled model.working, HE.onClick (SetTrusted False)] [H.text "Mark untrusted"]
                  ]
              else
                H.div []
                  [ H.text "You don't trust this user. "
                  , H.button [HA.disabled model.working, HE.onClick (SetTrusted True)] [H.text "Mark trusted"]
                  ]
            , model.notification |> H.map never
            , H.br [] []
            , if Page.getRelationship globals model.username |> Maybe.map .trusting |> Maybe.withDefault False then
                H.div []
                  [ H.h3 [] [H.text "Predictions"]
                  , ViewPredictionsWidget.view globals model.predictionsWidget |> H.map PredictionsMsg
                  ]
              else
                H.text ""
            ]
  ]]}

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ ViewPredictionsWidget.subscriptions model.predictionsWidget |> Sub.map PredictionsMsg
    ]

pagedef : Page.Element Model Msg
pagedef = {init=init, view=view, update=update, subscriptions=subscriptions}

main = Page.Program.page pagedef
