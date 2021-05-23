port module Elements.Settings exposing (main)

import Browser
import Html as H
import Http
import Json.Decode as JD

import Widgets.ChangePasswordWidget as ChangePasswordWidget
import Widgets.EmailSettingsWidget as EmailSettingsWidget
import Widgets.TrustedUsersWidget as TrustedUsersWidget
import Globals
import API
import Utils
import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Biatob.Proto.Mvp as Pb

port copy : String -> Cmd msg
port navigate : Maybe String -> Cmd msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , emailSettingsWidget : EmailSettingsWidget.State
  , trustedUsersWidget : TrustedUsersWidget.State
  , changePasswordWidget : ChangePasswordWidget.State
  }

type Msg
  = SetEmailWidget EmailSettingsWidget.State
  | UpdateSettings EmailSettingsWidget.State Pb.UpdateSettingsRequest
  | UpdateSettingsFinished Pb.UpdateSettingsRequest (Result Http.Error Pb.UpdateSettingsResponse)
  | SetEmail EmailSettingsWidget.State Pb.SetEmailRequest
  | SetEmailFinished Pb.SetEmailRequest (Result Http.Error Pb.SetEmailResponse)
  | VerifyEmail EmailSettingsWidget.State Pb.VerifyEmailRequest
  | VerifyEmailFinished Pb.VerifyEmailRequest (Result Http.Error Pb.VerifyEmailResponse)
  | SetTrustedUsersWidget TrustedUsersWidget.State
  | CreateInvitation TrustedUsersWidget.State Pb.CreateInvitationRequest
  | CreateInvitationFinished Pb.CreateInvitationRequest (Result Http.Error Pb.CreateInvitationResponse)
  | SetTrusted TrustedUsersWidget.State Pb.SetTrustedRequest
  | SetTrustedFinished Pb.SetTrustedRequest (Result Http.Error Pb.SetTrustedResponse)
  | SetChangePasswordWidget ChangePasswordWidget.State
  | ChangePassword ChangePasswordWidget.State Pb.ChangePasswordRequest
  | ChangePasswordFinished Pb.ChangePasswordRequest (Result Http.Error Pb.ChangePasswordResponse)
  | SetAuthWidget AuthWidget.State
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | Copy String
  | Ignore

init : JD.Value -> ( Model , Cmd Msg )
init flags =
  ( { globals = JD.decodeValue Globals.globalsDecoder flags |> Result.toMaybe |> Utils.must "flags"
    , navbarAuth = AuthWidget.init
    , emailSettingsWidget = EmailSettingsWidget.init
    , trustedUsersWidget = TrustedUsersWidget.init
    , changePasswordWidget = ChangePasswordWidget.init
    }
  , Cmd.none
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetChangePasswordWidget widgetState ->
      ( { model | changePasswordWidget = widgetState } , Cmd.none )
    ChangePassword widgetState req ->
      ( { model | changePasswordWidget = widgetState }
      , API.postChangePassword (ChangePasswordFinished req) req
      )
    ChangePasswordFinished req res ->
      ( { model | changePasswordWidget = model.changePasswordWidget |> ChangePasswordWidget.handleChangePasswordResponse res
                , globals = model.globals |> Globals.handleChangePasswordResponse req res
        }
      , Cmd.none
      )
    SetTrustedUsersWidget widgetState ->
      ( { model | trustedUsersWidget = widgetState } , Cmd.none )
    CreateInvitation widgetState req ->
      ( { model | trustedUsersWidget = widgetState }
      , API.postCreateInvitation (CreateInvitationFinished req) req
      )
    CreateInvitationFinished req res ->
      ( { model | trustedUsersWidget = model.trustedUsersWidget |> TrustedUsersWidget.handleCreateInvitationResponse res
                , globals = model.globals |> Globals.handleCreateInvitationResponse req res
        }
      , Cmd.none
      )
    SetTrusted widgetState req ->
      ( { model | trustedUsersWidget = widgetState }
      , API.postSetTrusted (SetTrustedFinished req) req
      )
    SetTrustedFinished req res ->
      ( { model | trustedUsersWidget = model.trustedUsersWidget |> TrustedUsersWidget.handleSetTrustedResponse res
                , globals = model.globals |> Globals.handleSetTrustedResponse req res
        }
      , Cmd.none
      )


    SetEmailWidget widgetState ->
      ( { model | emailSettingsWidget = widgetState } , Cmd.none )
    UpdateSettings widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , API.postUpdateSettings (UpdateSettingsFinished req) req
      )
    UpdateSettingsFinished req res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleUpdateSettingsResponse res
                , globals = model.globals |> Globals.handleUpdateSettingsResponse req res
        }
      , Cmd.none
      )
    SetEmail widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , API.postSetEmail (SetEmailFinished req) req
      )
    SetEmailFinished req res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleSetEmailResponse res
                , globals = model.globals |> Globals.handleSetEmailResponse req res
        }
      , Cmd.none
      )
    VerifyEmail widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , API.postVerifyEmail (VerifyEmailFinished req) req
      )
    VerifyEmailFinished req res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleVerifyEmailResponse res
                , globals = model.globals |> Globals.handleVerifyEmailResponse req res
        }
      , Cmd.none
      )
    SetAuthWidget widgetState ->
      ( { model | navbarAuth = widgetState } , Cmd.none )
    LogInUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postLogInUsername (LogInUsernameFinished req) req
      )
    LogInUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleLogInUsernameResponse req res , navbarAuth = model.navbarAuth |> AuthWidget.handleLogInUsernameResponse res }
      , navigate Nothing
      )
    RegisterUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postRegisterUsername (RegisterUsernameFinished req) req
      )
    RegisterUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleRegisterUsernameResponse req res , navbarAuth = model.navbarAuth |> AuthWidget.handleRegisterUsernameResponse res }
      , navigate Nothing
      )
    SignOut widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postSignOut (SignOutFinished req) req
      )
    SignOutFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSignOutResponse req res , navbarAuth = model.navbarAuth |> AuthWidget.handleSignOutResponse res }
      , navigate (Just "/")
      )
    Copy s ->
      ( model
      , copy s
      )
    Ignore ->
      ( model , Cmd.none )


view : Model -> Browser.Document Msg
view model =
  { title = "Settings"
  , body = [
    Navbar.view
        { setState = SetAuthWidget
        , logInUsername = LogInUsername
        , register = RegisterUsername
        , signOut = SignOut
        , ignore = Ignore
        , auth = Globals.getAuth model.globals
        }
        model.navbarAuth
    ,
    H.main_ []
    [ case model.globals.serverState.settings of
        Nothing -> H.text "You need to log in to view your settings!"
        Just userInfo ->
          H.div []
          [ H.h2 [] [H.text "Settings"]
          , H.hr [] []
          , H.h3 [] [H.text "Email"]
          , EmailSettingsWidget.view
              { setState = SetEmailWidget
              , ignore = Ignore
              , setEmail = SetEmail
              , verifyEmail = VerifyEmail
              , updateSettings = UpdateSettings
              , userInfo = userInfo
              }
              model.emailSettingsWidget
          , H.hr [] []
          , H.h3 [] [H.text "Trust"]
          , TrustedUsersWidget.view
              { setState = SetTrustedUsersWidget
              , createInvitation = CreateInvitation
              , setTrusted = SetTrusted
              , copy = Copy
              , auth = model.globals.authToken |> Utils.must "should condense Globals.auth and .serverState.settings into a single type, since they Nothing together"
              , userInfo = userInfo
              , timeZone = model.globals.timeZone
              , httpOrigin = model.globals.httpOrigin
              }
              model.trustedUsersWidget
          , H.hr [] []
          , H.div []
              [ H.h3 [] [H.text "Change password"]
              , ChangePasswordWidget.view
                  { setState = SetChangePasswordWidget
                  , changePassword = ChangePassword
                  }
                  model.changePasswordWidget
              ]
          ]
  ]]
  }

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
