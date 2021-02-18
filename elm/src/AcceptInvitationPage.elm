port module AcceptInvitationPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import API
import AuthWidget

port accepted : {dest : String} -> Cmd msg

type AuthState = LoggedIn Pb.AuthToken | LoggedOut AuthWidget.Model
type alias Model =
  { authState : AuthState
  , invitationId : Pb.InvitationId
  , working : Bool
  , acceptNotification : Html Msg
  }

type Msg
  = AcceptInvitation
  | AcceptInvitationFinished (Result Http.Error Pb.AcceptInvitationResponse)
  | AuthWidgetMsg AuthWidget.Msg

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags in
  ( { authState = case auth of
        Just auth_ -> LoggedIn auth_
        Nothing -> LoggedOut AuthWidget.initNoToken
    , invitationId = Utils.mustDecodePbFromFlags Pb.invitationIdDecoder "invitationIdPbB64" flags
    , working = False
    , acceptNotification = H.text ""
    }
  , Cmd.none
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    AcceptInvitation ->
      ( { model | working = True , acceptNotification = H.text "" }
      , API.postAcceptInvitation AcceptInvitationFinished {invitationId=Just model.invitationId}
      )
    AcceptInvitationFinished (Err e) ->
      ( { model | working = False , acceptNotification = Utils.redText (Debug.toString e) }
      , Cmd.none
      )
    AcceptInvitationFinished (Ok resp) ->
      case resp.acceptInvitationResult of
        Just (Pb.AcceptInvitationResultOk _) ->
          ( model
          , accepted {dest = Utils.pathToUserPage <| Utils.mustInviter model.invitationId }
          )
        Just (Pb.AcceptInvitationResultError e) ->
          ( { model | working = False , acceptNotification = Utils.redText (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , acceptNotification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )
    AuthWidgetMsg widgetMsg ->
      case model.authState of
        LoggedOut widget ->
          let (newWidget, widgetCmd) = AuthWidget.update widgetMsg widget in
          ( { model | authState = LoggedOut newWidget }
          , Cmd.map AuthWidgetMsg widgetCmd
          )
        _ -> Debug.todo "wrong state"

isOwnInvitation : AuthState -> Pb.InvitationId -> Bool
isOwnInvitation authState invitationId =
  case authState of
    LoggedIn auth -> auth.owner == invitationId.inviter
    LoggedOut _ -> False

view : Model -> Html Msg
view model =
  if isOwnInvitation model.authState model.invitationId then H.text "This is your own invitation!" else
  H.div []
    [ H.h2 [] [H.text "Invitation from ", Utils.renderUser <| Utils.mustInviter model.invitationId]
    , H.p []
      [ H.text <| "The person who sent you this link is interested in betting against you regarding real-world events,"
        ++ " with real money, upheld by the honor system!"
        ++ " They trust you to behave honorably and pay your debts, and hope that you trust them back."
      ]
    , H.p [] <|
      case model.authState of
        LoggedIn _ ->
          [ H.text "If you trust them back, click "
          , H.button [HE.onClick AcceptInvitation, HA.disabled model.working] [H.text "I trust the person who sent me this link"]
          , model.acceptNotification
          , H.text "; otherwise, just close this tab."
          ]
        LoggedOut authWidget ->
          [ H.text "If you trust them back, and you're interested in betting against them:"
          , H.ul []
            [ H.li [] [H.text "Authenticate yourself: ", AuthWidget.view authWidget |> H.map AuthWidgetMsg]
            , H.li []
              [ H.text "...then click "
              , H.button
                [ HE.onClick AcceptInvitation
                , HA.disabled True -- login will trigger reload, and then we'll take the other case branch
                ] [H.text "I trust the person who sent me this link"]
              , model.acceptNotification
              , H.text "."
              ]
            ]
          ]
    , H.hr [] []
    , H.h3 [] [H.text "Huh? What? What is this?"]
    , H.p [] [H.text "This site is a tool that helps people make concrete predictions and bet on them, thereby clarifying their beliefs and making the world a better, saner place."]
    , H.p [] [H.text <| "Users can make predictions and say how confident they are;"
        ++ " then other people can bet real money against them. "
        , H.strong [] [H.text "Everything is purely honor-system,"]
        , H.text <| " so you don't have to provide a credit card or anything, but you ", H.i [] [H.text "do"]
        , H.text <| " have to tell the site who you trust, so that it knows who's allowed to bet against you."
        ++ " (Honor systems only work where there is honor.)"]
    , H.p [] [Utils.renderUser <| Utils.mustInviter model.invitationId, H.text <|
        " thinks you might be interested in gambling against them, and trusts you to pay any debts you incur when you lose;"
        ++ " if you feel likewise, accept their invitation!"]
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
