module Elements.Settings exposing (main)

import Browser
import Html as H exposing (Html)
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

type UserTypeSpecificSettings
  = UsernameSettings ChangePasswordWidget.Model

type alias Model =
  { auth : Pb.AuthToken
  , userInfo : Pb.GenericUserInfo
  , emailSettingsWidget : EmailSettingsWidget.State
  , trustedUsersWidget : TrustedUsersWidget.State
  , userTypeSettings : UserTypeSpecificSettings
  , httpOrigin : String
  }

trustedUsersCtx : Model -> TrustedUsersWidget.Context Msg
trustedUsersCtx model =
  { auth = model.auth
  , httpOrigin = model.httpOrigin
  , invitations = model.userInfo.invitations |> Utils.mustMapValues
  , trustedUsers = model.userInfo.trustedUsers
  , handle = TrustedUsersEvent
  }

emailSettingsCtx : Model -> EmailSettingsWidget.Context Msg
emailSettingsCtx model =
  { emailFlowState = model.userInfo |> Utils.mustUserInfoEmail
  , emailRemindersToResolve = model.userInfo.emailRemindersToResolve
  , emailResolutionNotifications = model.userInfo.emailResolutionNotifications
  , handle = EmailSettingsEvent
  }

emailSettingsHandler : EmailSettingsWidget.Handler Model
emailSettingsHandler =
  { updateWidget = \f m -> { m | emailSettingsWidget = m.emailSettingsWidget |> f }
  , setEmailFlowState = \e m -> { m | userInfo = m.userInfo |> \u -> { u | email = Just e } }
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

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    auth = Utils.mustDecodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    httpOrigin = Utils.mustDecodeFromFlags JD.string "httpOrigin" flags
    pbResp = Utils.mustDecodePbFromFlags Pb.getSettingsResponseDecoder "settingsRespPbB64" flags
    genericInfo = case Utils.mustGetSettingsResult pbResp of
      Pb.GetSettingsResultError e -> Debug.todo (Debug.toString e)
      Pb.GetSettingsResultOkUsername usernameInfo -> Utils.mustUsernameGenericInfo usernameInfo
  in
  case Utils.mustGetSettingsResult pbResp of
    Pb.GetSettingsResultError e -> Debug.todo (Debug.toString e)
    Pb.GetSettingsResultOkUsername _ ->
      let
        (changePasswordWidget, changePasswordCmd) = ChangePasswordWidget.init ()
      in
      ( { auth = auth
        , userInfo = genericInfo
        , emailSettingsWidget = EmailSettingsWidget.init
        , trustedUsersWidget = TrustedUsersWidget.init
        , userTypeSettings = UsernameSettings changePasswordWidget
        , httpOrigin = httpOrigin
        }
      , Cmd.map ChangePasswordMsg changePasswordCmd
      )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    ChangePasswordMsg widgetMsg ->
      case model.userTypeSettings of
        UsernameSettings widget ->
          let (newWidget, cmd) = ChangePasswordWidget.update widgetMsg widget in
          ( { model | userTypeSettings = UsernameSettings newWidget }
          , Cmd.map ChangePasswordMsg cmd
          )

    TrustedUsersEvent event newWidget ->
      (case event of
        Just (TrustedUsersWidget.Copy s) -> ( model , CopyWidget.copy s )
        Just (TrustedUsersWidget.InvitationEvent (SmallInvitationWidget.Copy s)) -> ( model , CopyWidget.copy s )
        Just (TrustedUsersWidget.InvitationEvent SmallInvitationWidget.CreateInvitation) -> ( model , API.postCreateInvitation CreateInvitationFinished {notes=""} )
        Just (TrustedUsersWidget.RemoveTrust who) -> ( model , API.postSetTrusted SetTrustedFinished {who=Just who, trusted=False} )
        Nothing -> ( model , Cmd.none )
      ) |> Tuple.mapFirst (\m -> { m | trustedUsersWidget = newWidget })

    EmailSettingsEvent event newWidget ->
      (case event of
        Just (EmailSettingsWidget.SetEmail req) -> (model, API.postSetEmail SetEmailFinished req)
        Just (EmailSettingsWidget.VerifyEmail req) -> (model, API.postVerifyEmail VerifyEmailFinished req)
        Just (EmailSettingsWidget.UpdateSettings req) -> (model, API.postUpdateSettings UpdateSettingsFinished req)
        Just EmailSettingsWidget.Ignore -> (model, Cmd.none)
        Nothing -> (model, Cmd.none)
      ) |> Tuple.mapFirst (\m -> { m | emailSettingsWidget = newWidget })

    CreateInvitationFinished res ->
      ( { model | trustedUsersWidget = model.trustedUsersWidget |> TrustedUsersWidget.handleCreateInvitationResponse res
                , userInfo = case res |> Result.toMaybe |> Maybe.andThen .createInvitationResult of
                    Just (Pb.CreateInvitationResultOk result) -> model.userInfo |> (\u -> { u | invitations = u.invitations |> Dict.insert (result.id |> Utils.must "" |> .nonce) result.invitation })
                    _ -> model.userInfo
        }
      , Cmd.none
      )

    SetTrustedFinished res ->
      ( { model | trustedUsersWidget = model.trustedUsersWidget |> TrustedUsersWidget.handleSetTrustedResponse res
                , userInfo = case res |> Result.toMaybe |> Maybe.andThen .setTrustedResult of
                    Just (Pb.SetTrustedResultOk {values}) -> model.userInfo |> (\u -> { u | trustedUsers = values })
                    _ -> model.userInfo
        }
      , Cmd.none
      )

    SetEmailFinished res ->
      ( EmailSettingsWidget.handleSetEmailResponse emailSettingsHandler res model
      , Cmd.none
      )

    VerifyEmailFinished res ->
      ( EmailSettingsWidget.handleVerifyEmailResponse emailSettingsHandler res model
      , Cmd.none
      )

    UpdateSettingsFinished res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleUpdateSettingsResponse res
                , userInfo = case res |> Result.toMaybe |> Maybe.andThen .updateSettingsResult of
                    Just (Pb.UpdateSettingsResultOk userInfo) -> userInfo
                    _ -> model.userInfo
        }
      , Cmd.none
      )


view : Model -> Html Msg
view model =
  H.div []
    [ H.h2 [] [H.text "Settings"]
    , H.hr [] []
    , H.h3 [] [H.text "Email"]
    , EmailSettingsWidget.view (emailSettingsCtx model) model.emailSettingsWidget
    , H.hr [] []
    , H.h3 [] [H.text "Trust"]
    , TrustedUsersWidget.view (trustedUsersCtx model) model.trustedUsersWidget
    , H.hr [] []
    , viewUserTypeSettings model.userTypeSettings
    ]

viewUserTypeSettings : UserTypeSpecificSettings -> Html Msg
viewUserTypeSettings settings =
  case settings of
    UsernameSettings changePasswordWidget ->
      H.div []
        [ H.h3 [] [H.text "Change password"]
        , H.map ChangePasswordMsg <| ChangePasswordWidget.view changePasswordWidget
        ]

subscriptions : Model -> Sub Msg
subscriptions model =
  case model.userTypeSettings of
    UsernameSettings changePasswordWidget ->
      ChangePasswordWidget.subscriptions changePasswordWidget |> Sub.map ChangePasswordMsg

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
