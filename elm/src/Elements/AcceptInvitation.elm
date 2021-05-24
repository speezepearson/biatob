port module Elements.AcceptInvitation exposing (main)

import Browser
import Dict
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import Widgets.AuthWidget as AuthWidget
import Utils
import Globals
import API
import Widgets.Navbar as Navbar
import Time

port navigate : Maybe String -> Cmd msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , invitationId : Pb.InvitationId
  , invitationIsOpen : Bool
  , destination : Maybe String
  , authWidget : AuthWidget.State
  , working : Bool
  , acceptNotification : Html Msg
  }

type AuthWidgetLoc = Navbar | Inline
type Msg
  = SetAuthWidget AuthWidgetLoc AuthWidget.State
  | AcceptInvitation
  | AcceptInvitationFinished Pb.AcceptInvitationRequest (Result Http.Error Pb.AcceptInvitationResponse)
  | LogInUsername AuthWidgetLoc AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished AuthWidgetLoc Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidgetLoc AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished AuthWidgetLoc Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut AuthWidgetLoc AuthWidget.State Pb.SignOutRequest
  | SignOutFinished AuthWidgetLoc Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | Tick Time.Posix
  | Ignore

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
    invitationId = Utils.mustDecodePbFromFlags Pb.invitationIdDecoder "invitationIdPbB64" flags
    destination = Utils.mustDecodeFromFlags (JD.nullable JD.string) "destination" flags
  in
  ( { globals = globals
    , invitationId = invitationId
    , destination = destination
    , invitationIsOpen = Utils.mustDecodeFromFlags JD.bool "invitationIsOpen" flags
    , navbarAuth = AuthWidget.init
    , authWidget = AuthWidget.init
    , working = False
    , acceptNotification = H.text ""
    }
  , case globals.serverState.settings |> Maybe.map .relationships |> Maybe.andThen (Dict.get invitationId.inviter) |> Maybe.andThen identity of
      Just {trusted, trusting} ->
        if trusted && trusting then
          navigate destination
        else
          Cmd.none
      Nothing -> Cmd.none

  )

updateAuthWidget : AuthWidgetLoc -> (AuthWidget.State -> AuthWidget.State) -> Model -> Model
updateAuthWidget loc f model =
  case loc of
    Navbar -> { model | navbarAuth = model.navbarAuth |> f }
    Inline -> { model | authWidget = model.authWidget |> f }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetAuthWidget loc widgetState ->
      ( updateAuthWidget loc (always widgetState) model , Cmd.none )
    AcceptInvitation ->
      ( { model | working = True , acceptNotification = H.text "" }
      , API.postAcceptInvitation (AcceptInvitationFinished {invitationId=Just model.invitationId}) {invitationId=Just model.invitationId}
      )
    AcceptInvitationFinished req res ->
      ( { model | globals = model.globals |> Globals.handleAcceptInvitationResponse req res
                , working = False
                , acceptNotification = case API.simplifyAcceptInvitationResponse res of
                    Ok _ -> H.text ""
                    Err e -> Utils.redText e
        }
      , case API.simplifyAcceptInvitationResponse res of
          Ok _ -> navigate model.destination
          Err _ -> Cmd.none
      )
    LogInUsername loc widgetState req ->
      ( updateAuthWidget loc (always widgetState) model
      , API.postLogInUsername (LogInUsernameFinished loc req) req
      )
    LogInUsernameFinished loc req res ->
      ( updateAuthWidget loc (AuthWidget.handleLogInUsernameResponse res) { model | globals = model.globals |> Globals.handleLogInUsernameResponse req res }
      , navigate Nothing
      )
    RegisterUsername loc widgetState req ->
      ( updateAuthWidget loc (always widgetState) model
      , API.postRegisterUsername (RegisterUsernameFinished loc req) req
      )
    RegisterUsernameFinished loc req res ->
      ( updateAuthWidget loc (AuthWidget.handleRegisterUsernameResponse res) { model | globals = model.globals |> Globals.handleRegisterUsernameResponse req res }
      , navigate Nothing
      )
    SignOut loc widgetState req ->
      ( updateAuthWidget loc (always widgetState) model
      , API.postSignOut (SignOutFinished loc req) req
      )
    SignOutFinished loc req res ->
      ( updateAuthWidget loc (AuthWidget.handleSignOutResponse res) { model | globals = model.globals |> Globals.handleSignOutResponse req res }
      , navigate <| Just "/"
      )
    Tick now ->
      ( { model | globals = model.globals |> Globals.tick now }
      , Cmd.none
      )
    Ignore ->
      ( model , Cmd.none )

isOwnInvitation : Globals.Globals -> Pb.InvitationId -> Bool
isOwnInvitation globals invitationId =
  case Globals.getAuth globals of
    Nothing -> False
    Just token -> token.owner == invitationId.inviter

view : Model -> Browser.Document Msg
view model =
  { title = "Accept Invitation"
  , body = [
    Navbar.view
        { setState = SetAuthWidget Navbar
        , logInUsername = LogInUsername Navbar
        , register = RegisterUsername Navbar
        , signOut = SignOut Navbar
        , ignore = Ignore
        , auth = Globals.getAuth model.globals
        }
        model.navbarAuth
    ,
    H.main_ [HA.style "text-align" "justify"] <|
    if isOwnInvitation model.globals model.invitationId then
      [H.text "This is your own invitation!"]
    else if not model.invitationIsOpen then
      [H.text "This invitation has been used up already!"]
    else
      [ H.h2 [] [H.text "Invitation from ", Utils.renderUser model.invitationId.inviter]
      , H.p []
        [ H.text <| "The person who sent you this link is interested in betting against you regarding real-world events,"
          ++ " with real money, upheld by the honor system!"
          ++ " They trust you to behave honorably and pay your debts, and hope that you trust them back."
        ]
      , H.p [] <|
        if Globals.isLoggedIn model.globals then
          [ H.text "If you trust them back, click "
          , H.button [HE.onClick AcceptInvitation, HA.disabled model.working] [H.text "I trust the person who sent me this link"]
          , model.acceptNotification
          , H.text "; otherwise, just close this tab."
          ]
        else
          [ H.text "If you trust them back, and you're interested in betting against them:"
          , H.ul []
            [ H.li []
              [ H.text "Authenticate yourself: "
              , AuthWidget.view
                  { setState = SetAuthWidget Inline
                  , logInUsername = LogInUsername Inline
                  , register = RegisterUsername Inline
                  , signOut = SignOut Inline
                  , ignore = Ignore
                  , auth = Globals.getAuth model.globals
                  }
                  model.authWidget
              ]
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
          , Utils.b "Everything is purely honor-system,"
          , H.text <| " so you don't have to provide a credit card or anything, but you ", Utils.i  "do"
          , H.text <| " have to tell the site who you trust, so that it knows who's allowed to bet against you."
          ++ " (Honor systems only work where there is honor.)"]
      , H.p [] [Utils.renderUser model.invitationId.inviter, H.text <|
          " thinks you might be interested in gambling against them, and trusts you to pay any debts you incur when you lose;"
          ++ " if you feel likewise, accept their invitation!"]
      ]
  ]}

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
