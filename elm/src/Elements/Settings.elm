module Elements.Settings exposing (main)

import Browser
import Html as H
import Http

import Widgets.ChangePasswordWidget as ChangePasswordWidget
import Widgets.EmailSettingsWidget as EmailSettingsWidget
import Widgets.TrustedUsersWidget as TrustedUsersWidget
import Page
import Page.Program
import API
import Biatob.Proto.Mvp as Pb

type alias Model =
  { emailSettingsWidget : EmailSettingsWidget.State
  , trustedUsersWidget : TrustedUsersWidget.Model
  , changePasswordWidget : ChangePasswordWidget.State
  }

type Msg
  = SetEmailWidget EmailSettingsWidget.State
  | UpdateSettings EmailSettingsWidget.State Pb.UpdateSettingsRequest
  | UpdateSettingsFinished (Result Http.Error Pb.UpdateSettingsResponse)
  | SetEmail EmailSettingsWidget.State Pb.SetEmailRequest
  | SetEmailFinished (Result Http.Error Pb.SetEmailResponse)
  | VerifyEmail EmailSettingsWidget.State Pb.VerifyEmailRequest
  | VerifyEmailFinished (Result Http.Error Pb.VerifyEmailResponse)
  | TrustedUsersMsg TrustedUsersWidget.Msg
  | SetChangePasswordWidget ChangePasswordWidget.State
  | ChangePassword ChangePasswordWidget.State Pb.ChangePasswordRequest
  | ChangePasswordFinished (Result Http.Error Pb.ChangePasswordResponse)
  | Ignore

init : Model
init =
  { emailSettingsWidget = EmailSettingsWidget.init
  , trustedUsersWidget = TrustedUsersWidget.init
  , changePasswordWidget = ChangePasswordWidget.init
  }

update : Msg -> Model -> (Model, Page.Command Msg)
update msg model =
  case msg of
    SetChangePasswordWidget widgetState ->
      ( { model | changePasswordWidget = widgetState } , Page.NoCmd )
    ChangePassword widgetState req ->
      ( { model | changePasswordWidget = widgetState }
      , Page.RequestCmd <| Page.ChangePasswordRequest ChangePasswordFinished req
      )
    ChangePasswordFinished res ->
      ( { model | changePasswordWidget = model.changePasswordWidget |> ChangePasswordWidget.handleChangePasswordResponse res }
      , Page.NoCmd
      )
    TrustedUsersMsg widgetMsg ->
      let (newWidget, innerCmd) = TrustedUsersWidget.update widgetMsg model.trustedUsersWidget in
      ( { model | trustedUsersWidget = newWidget } , Page.mapCmd TrustedUsersMsg innerCmd )

    SetEmailWidget widgetState ->
      ( { model | emailSettingsWidget = widgetState } , Page.NoCmd )
    UpdateSettings widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , Page.RequestCmd <| Page.UpdateSettingsRequest UpdateSettingsFinished req
      )
    UpdateSettingsFinished res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleUpdateSettingsResponse res }
      , Page.NoCmd
      )
    SetEmail widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , Page.RequestCmd <| Page.SetEmailRequest SetEmailFinished req
      )
    SetEmailFinished res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleSetEmailResponse res }
      , Page.NoCmd
      )
    VerifyEmail widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , Page.RequestCmd <| Page.VerifyEmailRequest VerifyEmailFinished req
      )
    VerifyEmailFinished res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleVerifyEmailResponse res }
      , Page.NoCmd
      )
    Ignore ->
      ( model , Page.NoCmd )


view : Page.Globals -> Model -> Browser.Document Msg
view globals model =
  { title = "Settings"
  , body = [
    H.main_ [] <| List.singleton <| case globals.serverState.settings of
      Nothing -> H.text "You have to log in to view your settings!"
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
          , TrustedUsersWidget.view globals model.trustedUsersWidget |> H.map TrustedUsersMsg
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
  ]
  }

subscriptions : Model -> Sub Msg
subscriptions model =
  TrustedUsersWidget.subscriptions model.trustedUsersWidget |> Sub.map TrustedUsersMsg

pagedef : Page.Element Model Msg
pagedef = {init=\_ -> (init, Page.NoCmd), view=view, update=update, subscriptions=subscriptions}

main = Page.Program.page pagedef
