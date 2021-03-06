module Elements.ViewUser exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD
import Dict

import Biatob.Proto.Mvp as Pb
import Utils

import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Widgets.ViewPredictionsWidget as ViewPredictionsWidget
import Widgets.CopyWidget as CopyWidget
import Page
import Page exposing (getUserInfo)
import Page exposing (getUserInfo)
import Page.Program

type alias Model =
  { userId : Pb.UserId
  , userView : Pb.UserUserView
  , predictionsWidget : ViewPredictionsWidget.Model
  , working : Bool
  , notification : Html Never
  , invitationWidget : SmallInvitationWidget.Model
  }

type Msg
  = SetTrusted Bool
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)
  | PredictionsMsg ViewPredictionsWidget.Msg
  | InvitationMsg SmallInvitationWidget.Msg

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
  ( { userId = Utils.mustDecodePbFromFlags Pb.userIdDecoder "userIdPbB64" flags
    , userView = Utils.mustDecodePbFromFlags Pb.userUserViewDecoder "userViewPbB64" flags
    , predictionsWidget = predsWidget
    , working = False
    , notification = H.text ""
    , invitationWidget = SmallInvitationWidget.init Nothing
    }
  , Page.NoCmd
  )

update : Msg -> Model -> (Model, Page.Command Msg)
update msg model =
  case msg of
    SetTrusted trusted ->
      ( { model | working = True , notification = H.text "" }
      , Page.RequestCmd <| Page.SetTrustedRequest SetTrustedFinished {who="", whoDepr=Just model.userId, trusted=trusted}
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
    InvitationMsg widgetMsg ->
      let (newWidget, innerCmd) = SmallInvitationWidget.update widgetMsg model.invitationWidget in
      ( { model | invitationWidget = newWidget } , Page.mapCmd InvitationMsg innerCmd )


view : Page.Globals -> Model -> Browser.Document Msg
view globals model =
  {title=Utils.renderUserPlain model.userId, body=[H.main_ []
    [ H.h2 [] [H.text model.userView.displayName]
    , H.br [] []
    , if model.userView.isSelf then
        H.div []
          [ H.text "This is you! You might have meant to visit "
          , H.a [HA.href "/settings"] [H.text "your settings"]
          , H.text "?"
          ]
      else case globals.authState of
        Nothing -> H.text "Log in to see your relationship with this user."
        Just auth -> let userInfo = Utils.mustAuthSuccessUserInfo auth in
          H.div []
            [ if model.userView.trustsYou then
                H.text "This user trusts you! :)"
              else
                H.div []
                  [ H.text "This user hasn't marked you as trusted! If you think that, in real life, they "
                  , H.i [] [H.text "do"]
                  , H.text " trust you, send them an invitation: "
                  , SmallInvitationWidget.view globals model.invitationWidget |> H.map InvitationMsg
                  ]
            , H.br [] []
            , if Dict.get (Utils.mustUsername model.userId) (Utils.mustMapValues userInfo.relationships) |> Maybe.map .trusted |> Maybe.withDefault False then
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
            , if model.userView.trustsYou then
                H.div []
                  [ H.h3 [] [H.text "Predictions"]
                  , ViewPredictionsWidget.view globals model.predictionsWidget |> H.map PredictionsMsg
                  ]
              else
                H.text ""
            ]
  ]]}

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

pagedef : Page.Element Model Msg
pagedef = {init=init, view=view, update=update, subscriptions=subscriptions}

main = Page.Program.page pagedef
