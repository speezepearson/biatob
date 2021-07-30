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
    proofOfEmail = Utils.mustDecodePbFromFlags Pb.proofOfEmailDecoder "proofOfEmailPbB64" flags
    model =
      { globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
      , navbarAuth = AuthWidget.init
      , usernameField = emailToSuggestedUsername (Utils.mustProofOfEmailPayload proofOfEmail).emailAddress
      , passwordField = ""
      , confirmPasswordField = ""
      , proofOfEmail = proofOfEmail
      , registerStatus = Unstarted
      }
  in
    ( model
    , Cmd.none
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
          Ok _ -> navigate <| Nothing
          Err _ -> Cmd.none
      )
    RegisterUsername ->
      ( { model | registerStatus = AwaitingResponse }
      , let req = {username=model.usernameField, password=model.passwordField, proofOfEmail=Just model.proofOfEmail} in API.postRegisterUsername (RegisterUsernameFinished req) req
      )
    RegisterUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleRegisterUsernameResponse req res }
      , case API.simplifyRegisterUsernameResponse res of
          Ok _ -> navigate <| Just "/new"
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


emailToSuggestedUsername : String -> String
emailToSuggestedUsername email =
  let
    emailUsername =
      email
      |> String.split "@"
      |> List.head
      |> Utils.must "String.split with nonempty delimiter is always nonempty"
    camelcase words =
      words
      |> List.map (\w -> String.toUpper (String.left 1 w) ++ String.dropLeft 1 w)
      |> String.concat
  in
    if String.contains "." emailUsername then
      camelcase (String.split "." emailUsername)
    else
      emailUsername

view : Model -> Browser.Document Msg
view model =
  { title = "Register new user"
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
    let
      username = Utils.parseUsername model.usernameField
      password =
        if String.length model.passwordField > 5 then
          Ok model.passwordField
        else
          Err "Must be at least 6 characters."
      canSubmit = Utils.isOk username && Utils.isOk password && model.confirmPasswordField == model.passwordField
    in
    H.main_ [HA.class "container"] <|
    [ H.h2 [HA.class "text-center"] [H.text "Register new user"]
    , H.div [HA.style "max-width" "50em", HA.class "mx-auto"] <|
      case Globals.getOwnUsername model.globals of
        Just self ->
          [ H.text "You're already registered, as "
          , Utils.renderUser self
          , H.text "! You might want to "
          , H.a [HA.href "/"] [H.text "visit the Home page"]
          , H.text "?"
          ]
        Nothing ->
          [ H.div [HA.class "mb-4"]
            [ H.label [HA.class "form-label"] [H.text "Your email address:"]
            , H.input
              [ HA.readonly True
              , HA.value (Utils.mustProofOfEmailPayload model.proofOfEmail).emailAddress
              , HA.class "form-control"
              ] []
            , H.div [HA.class "form-text"] [H.text "I'll send you notifications at this address when something needs your attention."]
            ]
          , H.div [HA.class "mb-4"]
            [ H.label [HA.for "register-username-field", HA.class "form-label"] [H.text "Username:"]
            , H.input
              [ HE.onInput SetUsernameField
              , HA.value model.usernameField
              , HA.id "register-username-field"
              , HA.class "form-control"
              , HA.class <| if model.usernameField == "" || Utils.isOk username then "" else "is-invalid"
              ] []
            , H.div [HA.class "form-text"] [H.text "How I'll identify you to other users."]
            , H.div [HA.class "invalid-feedback"]
              [ case username of
                  Ok _ -> H.text ""
                  Err e -> H.text e
              ]
            ]
          , H.div [HA.class "row mb-4"]
            [ H.div [HA.class "col-6"]
              [ H.label [HA.for "register-password-field", HA.class "form-label"] [H.text "Password:"]
              , H.input
                [ HE.onInput SetPasswordField
                , HA.type_ "password"
                , HA.value model.passwordField
                , HA.id "register-password-field"
                , HA.class "form-control"
                , HA.class <| if model.passwordField == "" || Utils.isOk password then "" else "is-invalid"
                ] []
              , H.div [HA.class "invalid-feedback"]
                [ case password of
                    Ok _ -> H.text ""
                    Err e -> H.text e
                ]
              ]
            , H.div [HA.class "col-6"]
              [ H.label [HA.for "register-confirm-password-field", HA.class "form-label"] [H.text "Confirm password:"]
              , H.input
                [ HE.onInput SetConfirmPasswordField
                , Utils.onEnter (if canSubmit then RegisterUsername else Ignore) Ignore
                , HA.type_ "password"
                , HA.value model.confirmPasswordField
                , HA.id "register-confirm-password-field"
                , HA.class "form-control"
                , HA.class <| if model.confirmPasswordField == "" && model.passwordField == "" then "" else if model.confirmPasswordField == model.passwordField then "is-valid" else "is-invalid"
                ] []
              ]
            ]
          , H.div [HA.class "text-center"]
            [ H.button
              [ HE.onClick RegisterUsername
              , HA.class "btn btn-primary"
              , HA.disabled <| not canSubmit
              ] [H.text "Finish signup"]
            , case model.registerStatus of
                Unstarted -> H.text ""
                AwaitingResponse -> H.text ""
                Succeeded -> Utils.greenText "Success!"
                Failed e -> H.div [HA.style "color" "red"] [H.text e]
            ]
          ]
    ]
  ]}

subscriptions : Model -> Sub Msg
subscriptions _ = authWidgetExternallyChanged AuthWidgetExternallyModified

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
