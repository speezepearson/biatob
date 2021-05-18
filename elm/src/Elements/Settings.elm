module Elements.Settings exposing (main)

import Browser
import Html as H


import Widgets.ChangePasswordWidget as ChangePasswordWidget
import Widgets.EmailSettingsWidget as EmailSettingsWidget
import Widgets.TrustedUsersWidget as TrustedUsersWidget
import Page
import Page.Program

type alias Model =
  { emailSettingsWidget : EmailSettingsWidget.Model
  , trustedUsersWidget : TrustedUsersWidget.Model
  , changePasswordWidget : ChangePasswordWidget.Model
  }

type Msg
  = EmailSettingsMsg EmailSettingsWidget.Msg
  | TrustedUsersMsg TrustedUsersWidget.Msg
  | ChangePasswordMsg ChangePasswordWidget.Msg

init : Model
init =
  { emailSettingsWidget = EmailSettingsWidget.init
  , trustedUsersWidget = TrustedUsersWidget.init
  , changePasswordWidget = ChangePasswordWidget.init
  }

update : Msg -> Model -> (Model, Page.Command Msg)
update msg model =
  case msg of
    ChangePasswordMsg widgetMsg ->
      let (newWidget, innerCmd) = ChangePasswordWidget.update widgetMsg model.changePasswordWidget in
      ( { model | changePasswordWidget = newWidget } , Page.mapCmd ChangePasswordMsg innerCmd )
    TrustedUsersMsg widgetMsg ->
      let (newWidget, innerCmd) = TrustedUsersWidget.update widgetMsg model.trustedUsersWidget in
      ( { model | trustedUsersWidget = newWidget } , Page.mapCmd TrustedUsersMsg innerCmd )

    EmailSettingsMsg widgetMsg ->
      let (newWidget, innerCmd) = EmailSettingsWidget.update widgetMsg model.emailSettingsWidget in
      ( { model | emailSettingsWidget = newWidget } , Page.mapCmd EmailSettingsMsg innerCmd )


view : Page.Globals -> Model -> Browser.Document Msg
view globals model =
  { title = "Settings"
  , body = [
    H.main_ [] <| List.singleton <| case globals.authToken of
      Nothing -> H.text "You have to log in to view your settings!"
      Just _ ->
        H.div []
          [ H.h2 [] [H.text "Settings"]
          , H.hr [] []
          , H.h3 [] [H.text "Email"]
          , EmailSettingsWidget.view globals model.emailSettingsWidget |> H.map EmailSettingsMsg
          , H.hr [] []
          , H.h3 [] [H.text "Trust"]
          , TrustedUsersWidget.view globals model.trustedUsersWidget |> H.map TrustedUsersMsg
          , H.hr [] []
          , H.div []
              [ H.h3 [] [H.text "Change password"]
              , ChangePasswordWidget.view model.changePasswordWidget |> H.map ChangePasswordMsg
              ]
          ]
  ]
  }

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ EmailSettingsWidget.subscriptions model.emailSettingsWidget |> Sub.map EmailSettingsMsg
    , TrustedUsersWidget.subscriptions model.trustedUsersWidget |> Sub.map TrustedUsersMsg
    , ChangePasswordWidget.subscriptions model.changePasswordWidget |> Sub.map ChangePasswordMsg
    ]

pagedef : Page.Element Model Msg
pagedef = {init=\_ -> (init, Page.NoCmd), view=view, update=update, subscriptions=subscriptions}

main = Page.Program.page pagedef
