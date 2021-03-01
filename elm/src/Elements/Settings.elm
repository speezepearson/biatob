module Elements.Settings exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Json.Decode as JD
import Http
import Dict exposing (Dict)

import Biatob.Proto.Mvp as Pb
import Utils

import Widgets.ChangePasswordWidget as ChangePasswordWidget
import Widgets.EmailSettingsWidget as EmailSettingsWidget
import Widgets.TrustedUsersWidget as TrustedUsersWidget
import Widgets.CopyWidget as CopyWidget
import API
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Page

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
    H.main_ [HA.id "main", HA.style "text-align" "justify"] <| List.singleton <| case globals.authState of
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

pagedef : Page.Element Model Msg
pagedef = {init=\_ -> (init, Page.NoCmd), view=view, update=update, subscriptions=\_ -> Sub.none}

main = Page.page pagedef
