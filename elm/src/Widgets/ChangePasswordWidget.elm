module Widgets.ChangePasswordWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Utils exposing (Password)

import Biatob.Proto.Mvp as Pb

import Biatob.Proto.Mvp exposing (StakeResult(..))
import API
import Utils exposing (isOk)
import Utils exposing (viewError)

type alias Config msg =
  { setState : State -> msg
  , ignore : msg
  , changePassword : State -> Pb.ChangePasswordRequest -> msg
  }
type alias State =
  { oldPasswordField : String
  , newPasswordField : String
  , working : Bool
  , notification : Html Never
  }

type Msg
  = SetOldPasswordField Password
  | SetNewPasswordField Password
  | ChangePassword
  | ChangePasswordFinished (Result Http.Error Pb.ChangePasswordResponse)

init : State
init =
  { oldPasswordField = ""
  , newPasswordField = ""
  , working = False
  , notification = H.text ""
  }

handleChangePasswordResponse : Result Http.Error Pb.ChangePasswordResponse -> State -> State
handleChangePasswordResponse res state =
  case API.simplifyChangePasswordResponse res of
    Ok _ ->
      { state | working = False
              , notification = H.text ""
              , oldPasswordField = ""
              , newPasswordField = ""
      }
    Err e ->
      { state | working = False
              , notification = Utils.redText e
      }

view : Config msg -> State -> Html msg
view config state =
  H.form [HE.onSubmit config.ignore]
    [ H.input
      [ HA.type_ "password"
      , HA.disabled <| state.working
      , HA.placeholder "old password"
      , HE.onInput (\s -> config.setState {state | oldPasswordField=s})
      , HA.value state.oldPasswordField
      , HA.class "form-control form-control-sm d-inline-block"
      , HA.style "max-width" "16em"
      ] []
    , H.input
      [ HA.type_ "password"
      , HA.disabled <| state.working
      , HA.placeholder "new password"
      , HE.onInput (\s -> config.setState {state | newPasswordField=s})
      , HA.value state.newPasswordField
      , HA.class "form-control form-control-sm d-inline-block"
      , HA.style "max-width" "16em"
      ] []
    , H.button
        [ HA.disabled <| state.working || state.oldPasswordField == "" || (Utils.isErr <| Utils.parsePassword state.newPasswordField)
        , HE.onClick (config.changePassword {state | working=True, notification=H.text ""} {oldPassword=state.oldPasswordField, newPassword=state.newPasswordField})
        , HA.class "btn btn-sm btn-outline-primary"
        ]
        [ H.text <| if state.working then "Changing..." else "Change password" ]
    , state.notification |> H.map never
    ]
