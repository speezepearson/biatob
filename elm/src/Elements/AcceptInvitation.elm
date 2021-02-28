port module Elements.AcceptInvitation exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import API
import Widgets.AuthWidget as AuthWidget
import Time
import Task
import Utils
import Page
import Widgets.Navbar as Navbar

port accepted : {dest : String} -> Cmd msg

type alias Model =
  { invitationId : Pb.InvitationId
  , invitationIsOpen : Bool
  , destination : Maybe String
  , authWidget : AuthWidget.State
  , navbar : Navbar.Model
  , working : Bool
  , acceptNotification : Html Msg
  }

type Msg
  = NavbarMsg Navbar.Msg
  | AcceptInvitation
  | AcceptInvitationFinished (Result Http.Error Pb.AcceptInvitationResponse)
  | AuthWidgetEvent (Maybe AuthWidget.Event) AuthWidget.State
  | LogInUsernameFinished (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsernameFinished (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOutFinished (Result Http.Error Pb.SignOutResponse)

init : JD.Value -> (Model, Page.Command Msg)
init flags =
  ( { invitationId = Utils.mustDecodePbFromFlags Pb.invitationIdDecoder "invitationIdPbB64" flags
    , destination = Utils.mustDecodeFromFlags (JD.nullable JD.string) "destination" flags
    , invitationIsOpen = Utils.mustDecodeFromFlags JD.bool "invitationIsOpen" flags
    , authWidget = AuthWidget.init
    , navbar = Navbar.init
    , working = False
    , acceptNotification = H.text ""
    }
  , Page.NoCmd
  )

authWidgetCtx : Page.Globals -> AuthWidget.Context Msg
authWidgetCtx globals =
  { auth = Page.getAuth globals
  , now = globals.now
  , handle = AuthWidgetEvent
  }

update : Msg -> Model -> (Model, Page.Command Msg)
update msg model =
  case msg of
    AcceptInvitation ->
      ( { model | working = True , acceptNotification = H.text "" }
      , Page.RequestCmd <| Page.AcceptInvitationRequest AcceptInvitationFinished {invitationId=Just model.invitationId}
      )
    AcceptInvitationFinished (Err e) ->
      ( { model | working = False , acceptNotification = Utils.redText (Debug.toString e) }
      , Page.NoCmd
      )
    AcceptInvitationFinished (Ok resp) ->
      case resp.acceptInvitationResult of
        Just (Pb.AcceptInvitationResultOk _) ->
          ( model
          , Page.MiscCmd <| accepted {dest = model.destination |> Maybe.withDefault (Utils.pathToUserPage <| Utils.mustInviter model.invitationId) }
          )
        Just (Pb.AcceptInvitationResultError e) ->
          ( { model | working = False , acceptNotification = Utils.redText (Debug.toString e) }
          , Page.NoCmd
          )
        Nothing ->
          ( { model | working = False , acceptNotification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
          , Page.NoCmd
          )
    AuthWidgetEvent event newState ->
      ( { model | authWidget = newState }
      , case event of
          Just (AuthWidget.LogInUsername req) -> Page.RequestCmd (Page.LogInUsernameRequest LogInUsernameFinished req)
          Just (AuthWidget.RegisterUsername req) -> Page.RequestCmd (Page.RegisterUsernameRequest RegisterUsernameFinished req)
          Just (AuthWidget.SignOut req) -> Page.RequestCmd (Page.SignOutRequest SignOutFinished req)
          Nothing -> Page.NoCmd
      )
    NavbarMsg innerMsg ->
      let (newNavbar, innerCmd) = Navbar.update innerMsg model.navbar in
      ( { model | navbar = newNavbar } , Page.mapCmd NavbarMsg innerCmd )
    LogInUsernameFinished res -> ( { model | authWidget = model.authWidget |> AuthWidget.handleLogInUsernameResponse {updateWidget=\f s -> f s, setAuth=always identity} res } , Page.NoCmd )
    RegisterUsernameFinished res -> ( { model | authWidget = model.authWidget |> AuthWidget.handleRegisterUsernameResponse {updateWidget=\f s -> f s, setAuth=always identity} res } , Page.NoCmd )
    SignOutFinished res -> ( { model | authWidget = model.authWidget |> AuthWidget.handleSignOutResponse {updateWidget=\f s -> f s, setAuth=always identity} res } , Page.NoCmd )

isOwnInvitation : Page.Globals -> Pb.InvitationId -> Bool
isOwnInvitation globals invitationId =
  Page.getAuth globals
  |> Maybe.map Utils.mustTokenOwner
  |> (==) invitationId.inviter

view : Page.Globals -> Model -> Browser.Document Msg
view globals model =
  { title = "Accept Invitation"
  , body = [Navbar.view globals model.navbar |> H.map NavbarMsg
   ,H.main_ [HA.id "main", HA.style "text-align" "justify"] <|
    if isOwnInvitation globals model.invitationId then
      [H.text "This is your own invitation!"]
    else if not model.invitationIsOpen then
      [H.text "This invitation has been used up already!"]
    else
      [ H.h2 [] [H.text "Invitation from ", Utils.renderUser <| Utils.mustInviter model.invitationId]
      , H.p []
        [ H.text <| "The person who sent you this link is interested in betting against you regarding real-world events,"
          ++ " with real money, upheld by the honor system!"
          ++ " They trust you to behave honorably and pay your debts, and hope that you trust them back."
        ]
      , H.p [] <|
        if Page.isLoggedIn globals then
          [ H.text "If you trust them back, click "
          , H.button [HE.onClick AcceptInvitation, HA.disabled model.working] [H.text "I trust the person who sent me this link"]
          , model.acceptNotification
          , H.text "; otherwise, just close this tab."
          ]
        else
          [ H.text "If you trust them back, and you're interested in betting against them:"
          , H.ul []
            [ H.li [] [H.text "Authenticate yourself: ", AuthWidget.view (authWidgetCtx globals) model.authWidget]
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
  ]}

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

pagedef : Page.Element Model Msg
pagedef = {init=init, view=view, update=update, subscriptions=\_ -> Sub.none}

main = Page.page pagedef
