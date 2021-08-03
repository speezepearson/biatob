port module Elements.Signup exposing (..)

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
  , emailField : String
  , sendVerificationEmailStatus : RequestStatus
  }
type Msg
  = SetAuthWidget AuthWidget.State
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | SendVerificationEmail
  | SendVerificationEmailFinished Pb.SendVerificationEmailRequest (Result Http.Error Pb.SendVerificationEmailResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | SetEmailField String
  | Tick Time.Posix
  | AuthWidgetExternallyModified AuthWidget.DomModification
  | Ignore

init : JD.Value -> ( Model , Cmd Msg )
init flags =
  let
    model =
      { globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
      , navbarAuth = AuthWidget.init
      , emailField = ""
      , sendVerificationEmailStatus = Unstarted
      }
  in
    ( model
    , if Globals.isLoggedIn model.globals then
        navigate <| Just "/"
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
    SetEmailField value -> ( { model | emailField = value } , Cmd.none )
    SendVerificationEmail ->
      let req = {emailAddress=model.emailField} in ( { model | sendVerificationEmailStatus = AwaitingResponse } , API.postSendVerificationEmail (SendVerificationEmailFinished req) req )
    SendVerificationEmailFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSendVerificationEmailResponse req res
                , sendVerificationEmailStatus = case API.simplifySendVerificationEmailResponse res of
                    Ok _ -> Succeeded
                    Err e -> Failed e
        }
      , Cmd.none
      )
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
    let
      email = Utils.parseEmailAddress model.emailField
      isError = (model.sendVerificationEmailStatus == AwaitingResponse) || Utils.isErr email
    in
    H.main_ [HA.class "container"]
    [ H.h2 [HA.class "text-center"] [H.text "Sign up"]
    , H.div [HA.style "max-width" "50em", HA.class "mx-auto"] <|
      case model.sendVerificationEmailStatus of
        Succeeded ->
          [ H.text "I've sent a verification email to "
          , H.text model.emailField
          , H.text "! Click the link it contains to finish registering."
          ]
        _ ->
          [ H.div [HA.class "mb-3"]
            [ H.label [HA.for "sign-up-email-field", HA.class "form-label"] [H.text "Email address:"]
            , H.input
              [ HE.onInput SetEmailField
              , Utils.onEnter (if isError then Ignore else SendVerificationEmail) Ignore
              , HA.value model.emailField
              , HA.id "sign-up-email-field"
              , HA.class "form-control"
              , HA.class <| if model.emailField == "" || Utils.isOk email then "" else "is-invalid"
              ] []
            , H.div [HA.class "form-text"] [H.text "I'll never ever intentionally share this with anybody unless you ask me to. I just need it so I can notify you when e.g. you owe somebody money."]
            ]
          , H.div [HA.class "text-center mt-4"]
            [ H.button
              [ HA.class "btn btn-primary"
              , HE.onClick SendVerificationEmail
              , HA.disabled <| isError
              ]
              [H.text "Send verification email"]
            ]
          ]
    ]
  ]}

subscriptions : Model -> Sub Msg
subscriptions _ = authWidgetExternallyChanged AuthWidgetExternallyModified

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
