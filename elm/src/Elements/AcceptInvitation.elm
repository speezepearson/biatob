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
import Globals
import API
import Widgets.Navbar as Navbar
import Utils exposing (InvitationNonce, Username)

port navigate : Maybe String -> Cmd msg
port authWidgetExternallyChanged : (AuthWidget.DomModification -> msg) -> Sub msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , inviter : Username
  , recipient : Username
  , nonce : InvitationNonce
  , requestStatus : RequestStatus
  }
type RequestStatus = AwaitingResponse | Succeeded | Failed String

type Msg
  = SetAuthWidget AuthWidget.State
  | AcceptInvitation
  | AcceptInvitationFinished Pb.AcceptInvitationRequest (Result Http.Error Pb.AcceptInvitationResponse)
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | AuthWidgetExternallyModified AuthWidget.DomModification
  | Ignore

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
    inviter = Utils.mustDecodeFromFlags JD.string "inviter" flags
    recipient = Utils.mustDecodeFromFlags JD.string "recipient" flags
    nonce = Utils.mustDecodeFromFlags JD.string "nonce" flags
  in
  ( { globals = globals
    , inviter = inviter
    , recipient = recipient
    , nonce = nonce
    , navbarAuth = AuthWidget.init
    , requestStatus = AwaitingResponse
    }
  , let req = {nonce = nonce} in
    API.postAcceptInvitation (AcceptInvitationFinished req) req
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetAuthWidget widgetState ->
      ( { model | navbarAuth = widgetState } , Cmd.none )
    AcceptInvitation ->
      ( { model | requestStatus = AwaitingResponse }
      , let req = {nonce = model.nonce} in
        API.postAcceptInvitation (AcceptInvitationFinished req) req
      )
    AcceptInvitationFinished req res ->
      ( case API.simplifyAcceptInvitationResponse res of
          Ok _ -> { model | requestStatus = Succeeded }
          Err e -> { model | requestStatus = Failed e }
      , Cmd.none
      )
    LogInUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postLogInUsername (LogInUsernameFinished req) req
      )
    LogInUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleLogInUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleLogInUsernameResponse res
        }
      , case API.simplifyLogInUsernameResponse res of
          Ok _ -> navigate Nothing
          Err _ -> Cmd.none
      )
    RegisterUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postRegisterUsername (RegisterUsernameFinished req) req
      )
    RegisterUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleRegisterUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleRegisterUsernameResponse res
        }
      , case API.simplifyRegisterUsernameResponse res of
          Ok _ -> navigate Nothing
          Err _ -> Cmd.none
      )
    SignOut widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postSignOut (SignOutFinished req) req
      )
    SignOutFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSignOutResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleSignOutResponse res
        }
      , case API.simplifySignOutResponse res of
          Ok _ -> navigate <| Just "/"
          Err _ -> Cmd.none
      )
    AuthWidgetExternallyModified mod ->
      ( { model | navbarAuth = model.navbarAuth |> AuthWidget.handleDomModification mod }
      , Cmd.none
      )
    Ignore ->
      ( model , Cmd.none )

view : Model -> Browser.Document Msg
view model =
  { title = case model.requestStatus of
      AwaitingResponse -> "Accepting invitation"
      Succeeded -> "Invitation accepted"
      Failed _ -> "[try again?] Accept invitation"
  , body =
    [ Navbar.view
        { setState = SetAuthWidget
        , logInUsername = LogInUsername
        , register = RegisterUsername
        , signOut = SignOut
        , ignore = Ignore
        , auth = Globals.getAuth model.globals
        , id = "navbar-auth"
        }
        model.navbarAuth
    , H.main_ [HA.class "container", HA.style "text-align" "justify"]
      [ case model.requestStatus of
          AwaitingResponse ->
            H.text "Working..."
          Failed e ->
            H.div []
            [ H.text "Oof, sorry, I'm having trouble accepting "
            , Utils.renderUser model.inviter
            , H.text "'s invitation:"
            , H.div [HA.style "margin" "1em"] [Utils.redText e]
            , H.text "Would you like to "
            , H.button [HE.onClick AcceptInvitation] [H.text "try again?"]
            ]
          Succeeded ->
            H.div []
            [ H.text "Thanks! I now know that you and "
            , Utils.renderUser model.inviter
            , H.text " trust each other, and I'll let you bet on each other's predictions!"
            , case Globals.getAuth model.globals |> Maybe.map .owner of
                Nothing -> H.text ""
                Just currentUser ->
                  if currentUser == model.recipient then
                    H.text ""
                  else
                    H.div []
                    [ H.strong [] [Utils.redText "Strangely,"]
                    , H.text " this invitation was destined for user "
                    , Utils.renderUser model.recipient
                    , H.text ", but you're logged in as "
                    , Utils.renderUser currentUser
                    , H.text ". I... I guess you just have two different accounts?"
                    , H.br [] []
                    , H.text "I recorded that "
                    , Utils.renderUser model.inviter
                    , H.text " and "
                    , Utils.renderUser model.recipient
                    , H.text " trust each other, as "
                    , Utils.renderUser model.inviter
                    , H.text " intended, not "
                    , Utils.renderUser model.inviter
                    , H.text " and your current account."
                    ]
            ]
      ]
    ]
  }
  --   if (model.globals.authToken |> Maybe.map .owner) == Just model.inviter then
  --     [H.text "This is your own invitation!"]
  --   else if not model.invitationIsOpen then
  --     [H.text "This invitation has been used up already!"]
  --   else
  --     [ H.h2 [] [H.text "Invitation from ", Utils.renderUser model.inviter]
  --     , H.p []
  --       [ H.text <| "The person who sent you this link is interested in betting against you regarding real-world events,"
  --         ++ " with real money, upheld by the honor system!"
  --         ++ " They trust you to behave honorably and pay your debts, and hope that you trust them back."
  --       ]
  --     , H.p [] <|
  --       if Globals.isLoggedIn model.globals then
  --         [ H.text "If you trust them back, click "
  --         , H.button [HE.onClick AcceptInvitation, HA.disabled model.working] [H.text "I trust the person who sent me this link"]
  --         , model.acceptNotification
  --         , H.text "; otherwise, just close this tab."
  --         ]
  --       else
  --         [ H.text "If you trust them back, and you're interested in betting against them:"
  --         , H.ul []
  --           [ H.li []
  --             [ H.text "Authenticate yourself: "
  --             , AuthWidget.view
  --                 { setState = SetAuthWidget
  --                 , logInUsername = LogInUsername
  --                 , register = RegisterUsername
  --                 , signOut = SignOut
  --                 , ignore = Ignore
  --                 , auth = Globals.getAuth model.globals
  --                 , id = "inline-auth"
  --                 }
  --                 model.authWidget
  --             ]
  --           , H.li []
  --             [ H.text "...then click "
  --             , H.button
  --               [ HE.onClick AcceptInvitation
  --               , HA.disabled True -- login will trigger reload, and then we'll take the other case branch
  --               ] [H.text "I trust the person who sent me this link"]
  --             , model.acceptNotification
  --             , H.text "."
  --             ]
  --           ]
  --         ]
  --     , H.hr [] []
  --     , H.h3 [] [H.text "Huh? What? What is this?"]
  --     , H.p [] [H.text "This site is a tool that helps people make concrete predictions and bet on them, thereby clarifying their beliefs and making the world a better, saner place."]
  --     , H.p [] [H.text <| "Users can make predictions and say how confident they are;"
  --         ++ " then other people can bet real money against them. "
  --         , Utils.b "Everything is purely honor-system,"
  --         , H.text <| " so you don't have to provide a credit card or anything, but you ", Utils.i  "do"
  --         , H.text <| " have to tell the site who you trust, so that it knows who's allowed to bet against you."
  --         ++ " (Honor systems only work where there is honor.)"]
  --     , H.p [] [Utils.renderUser model.inviter, H.text <|
  --         " thinks you might be interested in gambling against them, and trusts you to pay any debts you incur when you lose;"
  --         ++ " if you feel likewise, accept their invitation!"]
  --     ]
  -- ]}

subscriptions : Model -> Sub Msg
subscriptions _ = authWidgetExternallyChanged AuthWidgetExternallyModified

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
