module SettingsPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import ChangePasswordWidget
import EmailSettingsWidget
import TrustedUsersWidget

type UserTypeSpecificSettings
  = UsernameSettings ChangePasswordWidget.Model

type alias Model =
  { auth : Maybe Pb.AuthToken
  , emailSettingsWidget : EmailSettingsWidget.Model
  , trustedUsersWidget : TrustedUsersWidget.Model
  , userTypeSettings : UserTypeSpecificSettings
  }

type Msg
  = EmailSettingsMsg EmailSettingsWidget.Msg
  | TrustedUsersMsg TrustedUsersWidget.Msg
  | ChangePasswordMsg ChangePasswordWidget.Msg

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    pbResp = Utils.mustDecodePbFromFlags Pb.getSettingsResponseDecoder "settingsRespPbB64" flags
    genericInfo = case pbResp.getSettingsResult of
      Nothing -> Debug.todo "TODO: add a must to Utils"
      Just (Pb.GetSettingsResultError e) -> Debug.todo (Debug.toString e)
      Just (Pb.GetSettingsResultOkUsername usernameInfo) -> Utils.mustUsernameGenericInfo usernameInfo
    (emailSettingsWidget, emailSettingsCmd) = EmailSettingsWidget.initFromUserInfo genericInfo
    (trustedUsersWidget, trustedUsersCmd) = TrustedUsersWidget.init <| genericInfo.trustedUsers
  in
  case pbResp.getSettingsResult of
    Nothing -> Debug.todo "TODO: add a must to Utils"
    Just (Pb.GetSettingsResultError e) -> Debug.todo (Debug.toString e)
    Just (Pb.GetSettingsResultOkUsername usernameInfo) ->
      let
        (changePasswordWidget, changePasswordCmd) = ChangePasswordWidget.init ()
      in
      ( { auth = auth
        , emailSettingsWidget = emailSettingsWidget
        , trustedUsersWidget = trustedUsersWidget
        , userTypeSettings = UsernameSettings changePasswordWidget
        }
      , Cmd.batch
          [ Cmd.map ChangePasswordMsg changePasswordCmd
          , Cmd.map TrustedUsersMsg trustedUsersCmd
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

    TrustedUsersMsg widgetMsg ->
      let (newWidget, cmd) = TrustedUsersWidget.update widgetMsg model.trustedUsersWidget in
      ( { model | trustedUsersWidget = newWidget }, Cmd.map TrustedUsersMsg cmd)


view : Model -> Html Msg
view model =
  H.div []
    [ H.h2 [] [H.text "Settings"]
    , H.hr [] []
    , H.h3 [] [H.text "Email"]
    , H.map EmailSettingsMsg <| EmailSettingsWidget.view model.emailSettingsWidget
    , H.hr [] []
    , H.h3 [] [H.text "Trusted users:"]
    , H.map TrustedUsersMsg <| TrustedUsersWidget.view model.trustedUsersWidget
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
