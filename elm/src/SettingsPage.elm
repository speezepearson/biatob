module SettingsPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Events as HE
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import ChangePasswordWidget
import SetEmailWidget

type UserTypeSpecificSettings
  = UsernameSettings ChangePasswordWidget.Model

type alias Model =
  { auth : Maybe Pb.AuthToken
  , setEmailWidget : SetEmailWidget.Model
  , userTypeSettings : UserTypeSpecificSettings
  }

type Msg
  = SetEmailMsg SetEmailWidget.Msg
  | ChangePasswordMsg ChangePasswordWidget.Msg

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    pbResp = Utils.mustDecodePbFromFlags Pb.getSettingsResponseDecoder "settingsRespPbB64" flags
  in
  case pbResp.getSettingsResult of
    Nothing -> Debug.todo "TODO: add a must to Utils"
    Just (Pb.GetSettingsResultError e) -> Debug.todo (Debug.toString e)
    Just (Pb.GetSettingsResultOkUsername usernameInfo) ->
      let
        (setEmailWidget, setEmailCmd) = SetEmailWidget.initFromFlowState <| Utils.mustEmailFlowStateKind <| Utils.mustUserInfoEmail <| Utils.mustUsernameGenericInfo usernameInfo
        (changePasswordWidget, changePasswordCmd) = ChangePasswordWidget.init ()
      in
      ( { auth = auth
        , setEmailWidget = setEmailWidget
        , userTypeSettings = UsernameSettings changePasswordWidget
        }
      , Cmd.batch
          [ Cmd.map ChangePasswordMsg changePasswordCmd
          , Cmd.map SetEmailMsg setEmailCmd
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

    SetEmailMsg widgetMsg ->
      let (newWidget, cmd) = SetEmailWidget.update widgetMsg model.setEmailWidget in
      ( { model | setEmailWidget = newWidget }, Cmd.map SetEmailMsg cmd)

view : Model -> Html Msg
view model =
  H.div []
    [ H.h2 [] [H.text "Settings"]
    , H.ul []
        [ H.li [] [H.map SetEmailMsg <| SetEmailWidget.view model.setEmailWidget]
        , viewUserTypeSettings model.userTypeSettings
        ]
    ]

viewUserTypeSettings : UserTypeSpecificSettings -> Html Msg
viewUserTypeSettings settings =
  case settings of
    UsernameSettings changePasswordWidget ->
      H.li [] [H.map ChangePasswordMsg <| ChangePasswordWidget.view changePasswordWidget]

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ SetEmailWidget.subscriptions model.setEmailWidget |> Sub.map SetEmailMsg
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
