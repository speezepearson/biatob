port module Elements.Settings exposing (main)

import Browser
import Html as H
import Html.Attributes as HA
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
import Time

port copy : String -> Cmd msg
port navigate : Maybe String -> Cmd msg
port authWidgetExternallyChanged : (AuthWidget.DomModification -> msg) -> Sub msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , emailSettingsWidget : EmailSettingsWidget.State
  , trustedUsersWidget : TrustedUsersWidget.State
  , changePasswordWidget : ChangePasswordWidget.State
  }

type Msg
  = SetAuthWidget AuthWidget.State
  | SetChangePasswordWidget ChangePasswordWidget.State
  | SetEmailWidget EmailSettingsWidget.State
  | SetTrustedUsersWidget TrustedUsersWidget.State
  | ChangePassword ChangePasswordWidget.State Pb.ChangePasswordRequest
  | ChangePasswordFinished Pb.ChangePasswordRequest (Result Http.Error Pb.ChangePasswordResponse)
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | SetEmail EmailSettingsWidget.State Pb.SetEmailRequest
  | SetEmailFinished Pb.SetEmailRequest (Result Http.Error Pb.SetEmailResponse)
  | SetTrusted TrustedUsersWidget.State Pb.SetTrustedRequest
  | SetTrustedFinished Pb.SetTrustedRequest (Result Http.Error Pb.SetTrustedResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | UpdateSettings EmailSettingsWidget.State Pb.UpdateSettingsRequest
  | UpdateSettingsFinished Pb.UpdateSettingsRequest (Result Http.Error Pb.UpdateSettingsResponse)
  | Copy String
  | Tick Time.Posix
  | AuthWidgetExternallyModified AuthWidget.DomModification
  | Ignore

init : JD.Value -> ( Model , Cmd Msg )
init flags =
  ( { globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
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
    SetAuthWidget widgetState ->
      ( { model | navbarAuth = widgetState } , Cmd.none )
    SetChangePasswordWidget widgetState ->
      ( { model | changePasswordWidget = widgetState } , Cmd.none )
    SetEmailWidget widgetState ->
      ( { model | emailSettingsWidget = widgetState } , Cmd.none )
    SetTrustedUsersWidget widgetState ->
      ( { model | trustedUsersWidget = widgetState } , Cmd.none )
    ChangePassword widgetState req ->
      ( { model | changePasswordWidget = widgetState }
      , API.postChangePassword (ChangePasswordFinished req) req
      )
    ChangePasswordFinished req res ->
      ( { model | globals = model.globals |> Globals.handleChangePasswordResponse req res
                , changePasswordWidget = model.changePasswordWidget |> ChangePasswordWidget.handleChangePasswordResponse res
        }
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
          Ok _ -> navigate <| Nothing
          Err _ -> Cmd.none
      )
    SetEmail widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , API.postSetEmail (SetEmailFinished req) req
      )
    SetEmailFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSetEmailResponse req res
                , emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleSetEmailResponse res
        }
      , Cmd.none
      )
    SetTrusted widgetState req ->
      ( { model | trustedUsersWidget = widgetState }
      , API.postSetTrusted (SetTrustedFinished req) req
      )
    SetTrustedFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSetTrustedResponse req res
                , trustedUsersWidget = model.trustedUsersWidget |> TrustedUsersWidget.handleSetTrustedResponse req.who res
        }
      , Cmd.none
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
    UpdateSettings widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , API.postUpdateSettings (UpdateSettingsFinished req) req
      )
    UpdateSettingsFinished req res ->
      ( { model | globals = model.globals |> Globals.handleUpdateSettingsResponse req res
                , emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleUpdateSettingsResponse res
        }
      , Cmd.none
      )
    Copy s ->
      ( model
      , copy s
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
  { title = "Settings"
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
    [ case model.globals.self of
        Nothing -> H.text "You need to log in to view your settings!"
        Just {username, settings} ->
          H.div []
          [ H.h2 [] [H.text "Settings"]
          , H.hr [] []
          , H.h3 [] [H.text "Email"]
          , EmailSettingsWidget.view
              { setState = SetEmailWidget
              , ignore = Ignore
              , setEmail = SetEmail
              , updateSettings = UpdateSettings
              , userInfo = settings
              , showAllEmailSettings = True
              }
              model.emailSettingsWidget
          , H.hr [] []
          , H.h3 [] [H.text "Trust"]
          , TrustedUsersWidget.view
              { setState = SetTrustedUsersWidget
              , setTrusted = SetTrusted
              , copy = Copy
              , userInfo = settings
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
                  , ignore = Ignore
                  }
                  model.changePasswordWidget
              ]
          ]
  ]]
  }

subscriptions : Model -> Sub Msg
subscriptions _ = authWidgetExternallyChanged AuthWidgetExternallyModified

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
