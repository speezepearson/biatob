module SettingsPage exposing (..)

import Browser
import Html as H exposing (Html)
import Json.Decode as JD
import Http
import Dict exposing (Dict)

import Biatob.Proto.Mvp as Pb
import Utils

import ChangePasswordWidget
import EmailSettingsWidget
import TrustedUsersWidget
import CopyWidget
import API

type UserTypeSpecificSettings
  = UsernameSettings ChangePasswordWidget.Model

type alias Model =
  { auth : Pb.AuthToken
  , trustedUsers : List Pb.UserId
  , invitations : Dict String Pb.Invitation
  , emailSettingsWidget : EmailSettingsWidget.Model
  , trustedUsersWidget : TrustedUsersWidget.State
  , userTypeSettings : UserTypeSpecificSettings
  , httpOrigin : String
  }

trustedUsersCtx : Model -> TrustedUsersWidget.Context Msg
trustedUsersCtx model =
  { auth = model.auth
  , httpOrigin = model.httpOrigin
  , invitations = model.invitations
  , trustedUsers = model.trustedUsers
  , handle = TrustedUsersEvent
  }

type Msg
  = EmailSettingsMsg EmailSettingsWidget.Msg
  | TrustedUsersEvent TrustedUsersWidget.Event TrustedUsersWidget.State
  | ChangePasswordMsg ChangePasswordWidget.Msg
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    auth = Utils.mustDecodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    httpOrigin = Utils.mustDecodeFromFlags JD.string "httpOrigin" flags
    pbResp = Utils.mustDecodePbFromFlags Pb.getSettingsResponseDecoder "settingsRespPbB64" flags
    genericInfo = case Utils.mustGetSettingsResult pbResp of
      Pb.GetSettingsResultError e -> Debug.todo (Debug.toString e)
      Pb.GetSettingsResultOkUsername usernameInfo -> Utils.mustUsernameGenericInfo usernameInfo
    (emailSettingsWidget, emailSettingsCmd) = EmailSettingsWidget.initFromUserInfo genericInfo
  in
  case Utils.mustGetSettingsResult pbResp of
    Pb.GetSettingsResultError e -> Debug.todo (Debug.toString e)
    Pb.GetSettingsResultOkUsername _ ->
      let
        (changePasswordWidget, changePasswordCmd) = ChangePasswordWidget.init ()
      in
      ( { auth = auth
        , trustedUsers = genericInfo.trustedUsers
        , invitations = genericInfo.invitations |> Utils.mustMapValues
        , emailSettingsWidget = emailSettingsWidget
        , trustedUsersWidget = TrustedUsersWidget.init
        , userTypeSettings = UsernameSettings changePasswordWidget
        , httpOrigin = httpOrigin
        }
      , Cmd.batch
          [ Cmd.map ChangePasswordMsg changePasswordCmd
          , Cmd.map EmailSettingsMsg emailSettingsCmd
          ]
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

    EmailSettingsMsg widgetMsg ->
      let (newWidget, cmd) = EmailSettingsWidget.update widgetMsg model.emailSettingsWidget in
      ( { model | emailSettingsWidget = newWidget }, Cmd.map EmailSettingsMsg cmd)

    TrustedUsersEvent event newWidget ->
      (case event of
        TrustedUsersWidget.Copy s -> ( model , CopyWidget.copy s )
        TrustedUsersWidget.CreateInvitation -> ( model , API.postCreateInvitation CreateInvitationFinished {notes=""} )
        TrustedUsersWidget.Nevermind -> Debug.todo ""
        TrustedUsersWidget.RemoveTrust who ->
          ( model , API.postSetTrusted SetTrustedFinished {who=Just who, trusted=False} )
      ) |> Tuple.mapFirst (\m -> { m | trustedUsersWidget = newWidget })

    CreateInvitationFinished res ->
      ( { model | trustedUsersWidget = model.trustedUsersWidget |> TrustedUsersWidget.handleCreateInvitationResponse model.auth res}
      , Cmd.none
      )

    SetTrustedFinished res ->
      ( { model | trustedUsersWidget = model.trustedUsersWidget |> TrustedUsersWidget.handleSetTrustedResponse res
                , trustedUsers = case res |> Result.toMaybe |> Maybe.andThen .setTrustedResult of
                    Just (Pb.SetTrustedResultOk {values}) -> values
                    _ -> model.trustedUsers
        }
      , Cmd.none
      )


view : Model -> Html Msg
view model =
  H.div []
    [ H.h2 [] [H.text "Settings"]
    , H.hr [] []
    , H.h3 [] [H.text "Email"]
    , H.map EmailSettingsMsg <| EmailSettingsWidget.view model.emailSettingsWidget
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
  Sub.batch
    [ EmailSettingsWidget.subscriptions model.emailSettingsWidget |> Sub.map EmailSettingsMsg
    , case model.userTypeSettings of
        UsernameSettings changePasswordWidget ->
          ChangePasswordWidget.subscriptions changePasswordWidget |> Sub.map ChangePasswordMsg
    ]

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
