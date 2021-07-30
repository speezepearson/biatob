port module Elements.InitUser exposing (..)

import Browser
import Html as H
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD
import Time

import Globals
import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Biatob.Proto.Mvp as Pb
import API
import Utils
import Utils exposing (RequestStatus(..))

port copy : String -> Cmd msg
port navigate : Maybe String -> Cmd msg
port authWidgetExternallyChanged : (AuthWidget.DomModification -> msg) -> Sub msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , usernameField : String
  , passwordField : String
  , confirmPasswordField : String
  , destination : String
  , proofOfEmail : Pb.ProofOfEmail
  , registerStatus : RequestStatus
  }
type Msg
  = SetAuthWidget AuthWidget.State
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | SetUsernameField String
  | SetPasswordField String
  | SetConfirmPasswordField String
  | Tick Time.Posix
  | AuthWidgetExternallyModified AuthWidget.DomModification
  | Ignore

init : JD.Value -> ( Model , Cmd Msg )
init flags =
  let
    model =
      { globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
      , navbarAuth = AuthWidget.init
      , destination = Utils.mustDecodeFromFlags JD.string "destination" flags
      , usernameField = ""
      , passwordField = ""
      , confirmPasswordField = ""
      , proofOfEmail = Utils.mustDecodePbFromFlags Pb.proofOfEmailDecoder "proofOfEmail" flags
      , registerStatus = Unstarted
      }
  in
    ( model
    , if Globals.isLoggedIn model.globals then
        navigate <| Just model.destination
      else
        Cmd.none
    )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetAuthWidget widgetState ->
      ( { model | navbarAuth = widgetState } , Cmd.none )
    LogInUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postLogInUsername (LogInUsernameFinished req) req
      )
    LogInUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleLogInUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleLogInUsernameResponse res
        }
      , case API.simplifyLogInUsernameResponse res of
          Ok _ -> navigate <| Just model.destination
          Err _ -> Cmd.none
      )
    RegisterUsername ->
      ( { model | registerStatus = AwaitingResponse }
      , let req = {username=model.usernameField, password=model.passwordField, proofOfEmail=Just model.proofOfEmail} in API.postRegisterUsername (RegisterUsernameFinished req) req
      )
    RegisterUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleRegisterUsernameResponse req res }
      , case API.simplifyRegisterUsernameResponse res of
          Ok _ -> navigate <| Just model.destination
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
    SetUsernameField value -> ( { model | usernameField = value } , Cmd.none )
    SetPasswordField value -> ( { model | passwordField = value } , Cmd.none )
    SetConfirmPasswordField value -> ( { model | confirmPasswordField = value } , Cmd.none )
    Tick now ->
      ( { model | globals = model.globals |> Globals.tick now }
      , Cmd.none
      )
    AuthWidgetExternallyModified mod ->
      ( { model | navbarAuth = model.navbarAuth |> AuthWidget.handleDomModification mod }
      , Cmd.none
      )
    Ignore ->
      ( model , Cmd.none )


view : Model -> Browser.Document Msg
view model =
  { title = "Sign up"
  , body = [
    Navbar.view
        { setState = SetAuthWidget
        , logInUsername = LogInUsername
        , signOut = SignOut
        , ignore = Ignore
        , username = Globals.getOwnUsername model.globals
        , id = "navbar-auth"
        }
        model.navbarAuth
    ,
    H.main_ [HA.class "container"]
    [ H.h2 [] [H.text "Sign up"]
    , H.div [HA.class "mb-3"]
      [ H.label [HA.for "register-username-field", HA.class "form-label"] [H.text "Username:"]
      , H.input [HE.onInput SetUsernameField, HA.value model.usernameField, HA.id "register-username-field"] []
      , H.div [HA.class "form-text"] [H.text "How I'll identify you to other users."]
      ]
    , H.div [HA.class "mb-3"]
      [ H.label [HA.for "register-password-field", HA.class "form-label"] [H.text "Password:"]
      , H.input [HE.onInput SetUsernameField, HA.value model.usernameField, HA.id "register-password-field"] []
      , H.div [HA.class "form-text"] [H.text "How I'll identify you to other users."]
      ]
    , H.div [HA.class "mb-3"]
      [ H.label [HA.for "register-confirm-password-field", HA.class "form-label"] [H.text "Confirm password:"]
      , H.input [HE.onInput SetUsernameField, HA.value model.usernameField, HA.id "register-confirm-password-field"] []
      , H.div [HA.class "form-text"] [H.text "How I'll identify you to other users."]
      ]
    , H.button [HE.onClick RegisterUsername, HA.class "btn btn-primary"] [H.text "Submit"]
    ]
  ]}

subscriptions : Model -> Sub Msg
subscriptions _ = authWidgetExternallyChanged AuthWidgetExternallyModified

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
