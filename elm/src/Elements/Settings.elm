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
import Widgets.Navbar as Navbar

type alias Model =
  { emailSettingsWidget : EmailSettingsWidget.State
  , trustedUsersWidget : TrustedUsersWidget.State
  , changePasswordWidget : ChangePasswordWidget.Model
  , navbar : Navbar.Model
  }

trustedUsersCtx : Pb.AuthToken -> Pb.GenericUserInfo -> String -> TrustedUsersWidget.Context Msg
trustedUsersCtx auth userInfo httpOrigin =
  { auth = auth
  , httpOrigin = httpOrigin
  , invitations = userInfo.invitations |> Utils.mustMapValues
  , trustedUsers = userInfo.trustedUsers
  , handle = TrustedUsersEvent
  }

emailSettingsCtx : Pb.GenericUserInfo -> EmailSettingsWidget.Context Msg
emailSettingsCtx userInfo =
  { emailFlowState = userInfo |> Utils.mustUserInfoEmail
  , emailRemindersToResolve = userInfo.emailRemindersToResolve
  , emailResolutionNotifications = userInfo.emailResolutionNotifications
  , handle = EmailSettingsEvent
  }

type Msg
  = EmailSettingsEvent (Maybe EmailSettingsWidget.Event) EmailSettingsWidget.State
  | TrustedUsersEvent (Maybe TrustedUsersWidget.Event) TrustedUsersWidget.State
  | ChangePasswordMsg ChangePasswordWidget.Msg
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)
  | SetEmailFinished (Result Http.Error Pb.SetEmailResponse)
  | VerifyEmailFinished (Result Http.Error Pb.VerifyEmailResponse)
  | UpdateSettingsFinished (Result Http.Error Pb.UpdateSettingsResponse)
  | NavbarMsg Navbar.Msg

init : JD.Value -> (Model, Page.Command Msg)
init flags =
  let
    (changePasswordWidget, changePasswordCmd) = ChangePasswordWidget.init ()
  in
  ( { emailSettingsWidget = EmailSettingsWidget.init
    , trustedUsersWidget = TrustedUsersWidget.init
    , changePasswordWidget = changePasswordWidget
    , navbar = Navbar.init
    }
  , Page.MiscCmd <| Cmd.map ChangePasswordMsg changePasswordCmd
  )

update : Msg -> Model -> (Model, Page.Command Msg)
update msg model =
  case msg of
    ChangePasswordMsg widgetMsg ->
      let (newWidget, cmd) = ChangePasswordWidget.update widgetMsg model.changePasswordWidget in
      ( { model | changePasswordWidget = newWidget }
      , Page.mapCmd ChangePasswordMsg (Page.MiscCmd cmd)
      )

    TrustedUsersEvent event newWidget ->
      ( { model | trustedUsersWidget = newWidget }
      , case event of
          Just (TrustedUsersWidget.Copy s) -> Page.CopyCmd s
          Just (TrustedUsersWidget.InvitationEvent (SmallInvitationWidget.Copy s)) -> Page.CopyCmd s
          Just (TrustedUsersWidget.InvitationEvent SmallInvitationWidget.CreateInvitation) -> Page.RequestCmd <| Page.CreateInvitationRequest CreateInvitationFinished {notes=""}
          Just (TrustedUsersWidget.RemoveTrust who) -> Page.RequestCmd <| Page.SetTrustedRequest SetTrustedFinished {who=Just who, trusted=False}
          Nothing -> Page.NoCmd
      )

    EmailSettingsEvent event newWidget ->
      ( { model | emailSettingsWidget = newWidget }
      , case event of
        Just (EmailSettingsWidget.SetEmail req) -> Page.RequestCmd <| Page.SetEmailRequest SetEmailFinished req
        Just (EmailSettingsWidget.VerifyEmail req) -> Page.RequestCmd <| Page.VerifyEmailRequest VerifyEmailFinished req
        Just (EmailSettingsWidget.UpdateSettings req) -> Page.RequestCmd <| Page.UpdateSettingsRequest UpdateSettingsFinished req
        Just EmailSettingsWidget.Ignore -> Page.NoCmd
        Nothing -> Page.NoCmd
      )

    CreateInvitationFinished res ->
      ( { model | trustedUsersWidget = model.trustedUsersWidget |> TrustedUsersWidget.handleCreateInvitationResponse res
        }
      , Page.NoCmd
      )

    SetTrustedFinished res ->
      ( { model | trustedUsersWidget = model.trustedUsersWidget |> TrustedUsersWidget.handleSetTrustedResponse res
        }
      , Page.NoCmd
      )

    SetEmailFinished res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleSetEmailResponse {updateWidget=\f s -> f s, setEmailFlowState=always identity} res }
      , Page.NoCmd
      )

    VerifyEmailFinished res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleVerifyEmailResponse {updateWidget=\f s -> f s, setEmailFlowState=always identity} res }
      , Page.NoCmd
      )

    UpdateSettingsFinished res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleUpdateSettingsResponse res }
      , Page.NoCmd
      )

    NavbarMsg innerMsg ->
      let (newNavbar, innerCmd) = Navbar.update innerMsg model.navbar in
      ( { model | navbar = newNavbar } , Page.mapCmd NavbarMsg innerCmd )



view : Page.Globals -> Model -> Browser.Document Msg
view globals model =
  { title = "Settings"
  , body = [
    Navbar.view globals model.navbar |> H.map NavbarMsg
   ,H.main_ [HA.id "main", HA.style "text-align" "justify"] <| List.singleton <| case globals.authState of
      Nothing -> H.text "You have to log in to view your settings!"
      Just auth ->
        let
          token = Utils.mustAuthSuccessToken auth
          userInfo = Utils.mustAuthSuccessUserInfo auth
        in
          H.div []
            [ H.h2 [] [H.text "Settings"]
            , H.hr [] []
            , H.h3 [] [H.text "Email"]
            , EmailSettingsWidget.view (emailSettingsCtx userInfo) model.emailSettingsWidget
            , H.hr [] []
            , H.h3 [] [H.text "Trust"]
            , TrustedUsersWidget.view (trustedUsersCtx token userInfo globals.httpOrigin) model.trustedUsersWidget
            , H.hr [] []
            , H.div []
                [ H.h3 [] [H.text "Change password"]
                , H.map ChangePasswordMsg <| ChangePasswordWidget.view model.changePasswordWidget
                ]
            ]
  ]
  }

pagedef : Page.Element Model Msg
pagedef = {init=init, view=view, update=update, subscriptions=\_ -> Sub.none}

main = Page.page pagedef
