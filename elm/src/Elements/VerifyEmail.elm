port module Elements.VerifyEmail exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import API
import Utils exposing (Username)

import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Globals
import Dict exposing (Dict)
import Biatob.Proto.Mvp exposing (Relationship)

port navigate : Maybe String -> Cmd msg
port authWidgetExternallyChanged : (AuthWidget.DomModification -> msg) -> Sub msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , code : String
  , requestStatus : RequestStatus
  }
type RequestStatus = AwaitingResponse | Succeeded | Failed String

type Msg
  = SetAuthWidget AuthWidget.State
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | AuthWidgetExternallyModified AuthWidget.DomModification
  | VerifyEmail
  | VerifyEmailFinished Pb.VerifyEmailRequest (Result Http.Error Pb.VerifyEmailResponse)
  | Ignore

init : JD.Value -> ( Model, Cmd Msg )
init flags =
  let
    code = Utils.mustDecodeFromFlags JD.string "code" flags
  in
  ( { globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
    , navbarAuth = AuthWidget.init
    , code = code
    , requestStatus = AwaitingResponse
    }
  , let req = { code = code } in API.postVerifyEmail (VerifyEmailFinished req) req
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
    RegisterUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postRegisterUsername (RegisterUsernameFinished req) req
      )
    RegisterUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleRegisterUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleRegisterUsernameResponse res
        }
      , case API.simplifyRegisterUsernameResponse res of
          Ok _ -> navigate <| Nothing
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
          Ok _ -> navigate <| Nothing
          Err _ -> Cmd.none
      )
    VerifyEmail ->
      ( { model | requestStatus = AwaitingResponse }
      , let req = { code = model.code } in API.postVerifyEmail (VerifyEmailFinished req) req
      )
    VerifyEmailFinished req res ->
      ( { model | globals = model.globals |> Globals.handleVerifyEmailResponse req res
                , requestStatus = case API.simplifyVerifyEmailResponse res of
                    Ok _ -> Succeeded
                    Err e -> Failed e
        }
      , Cmd.none
      )
    AuthWidgetExternallyModified mod ->
      ( { model | navbarAuth = model.navbarAuth |> AuthWidget.handleDomModification mod }
      , Cmd.none
      )
    Ignore ->
      ( model , Cmd.none )

type Relationship
  = LoggedOut
  | Self
  | NoRelation
  | Related Pb.Relationship
getRelationship : Username -> Globals.Globals -> Relationship
getRelationship who globals =
  case Globals.getUserInfo globals of
    Nothing -> LoggedOut
    Just {relationships} ->
      if Globals.getOwnUsername globals == Just who then Self else
      case Dict.get who relationships |> Maybe.andThen identity of
        Nothing -> NoRelation
        Just rel -> Related rel

view : Model -> Browser.Document Msg
view model =
  { title="Verify email"
  , body=
    [ Navbar.view
        { setState = SetAuthWidget
        , logInUsername = LogInUsername
        , register = RegisterUsername
        , signOut = SignOut
        , ignore = Ignore
        , username = Globals.getOwnUsername model.globals
        , id = "navbar-auth"
        }
        model.navbarAuth
    , H.main_ [HA.class "container"]
      [ H.h2 [HA.class "my-3 text-center"] [H.text "Verify email"]
      , case model.requestStatus of
          AwaitingResponse -> H.text "Working..."
          Succeeded -> H.text "Email verified! You can close this tab and go back to what you were doing before. (You might need to refresh any open pages if you want them to notice the change.)"
          Failed e ->
            H.span []
            [ Utils.redText <| "Email verification failed: " ++ e
            , H.text " "
            , H.button
              [ HE.onClick VerifyEmail
              , HA.class "btn btn-sm py-0 btn-primary"
              ] [H.text "Try again?"]
            ]
      ]
    ]
  }

subscriptions : Model -> Sub Msg
subscriptions _ = authWidgetExternallyChanged AuthWidgetExternallyModified

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
