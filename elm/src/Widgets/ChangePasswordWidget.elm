module Widgets.ChangePasswordWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http

import Biatob.Proto.Mvp as Pb

import Biatob.Proto.Mvp exposing (StakeResult(..))
import API
import Utils exposing (Password, RequestStatus(..), isOk, viewError)

type alias Config msg =
  { setState : State -> msg
  , ignore : msg
  , changePassword : State -> Pb.ChangePasswordRequest -> msg
  }
type alias State =
  { oldPasswordField : String
  , newPasswordField : String
  , requestStatus : RequestStatus
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
  , requestStatus = Unstarted
  }

handleChangePasswordResponse : Result Http.Error Pb.ChangePasswordResponse -> State -> State
handleChangePasswordResponse res state =
  case API.simplifyChangePasswordResponse res of
    Ok _ ->
      { state | requestStatus = Succeeded
              , oldPasswordField = ""
              , newPasswordField = ""
      }
    Err e ->
      { state | requestStatus = Failed e
      }

view : Config msg -> State -> Html msg
view config state =
  H.div []
    [ H.div [HA.class "row m-2"]
      [ H.div [HA.class "col-2"]
        [ H.input
          [ HA.type_ "password"
          , HA.disabled <| state.requestStatus == AwaitingResponse
          , HA.placeholder "old password"
          , HE.onInput (\s -> config.setState {state | oldPasswordField=s})
          , HA.value state.oldPasswordField
          , HA.class "form-control form-control-sm d-inline-block"
          , HA.style "max-width" "16em"
          ] []
        ]
      , H.div [HA.class "col-2"]
        [ H.input
          [ HA.type_ "password"
          , HA.disabled <| state.requestStatus == AwaitingResponse
          , HA.placeholder "new password"
          , HE.onInput (\s -> config.setState {state | newPasswordField=s})
          , HA.value state.newPasswordField
          , HA.class "form-control form-control-sm d-inline-block"
          , HA.class (if state.newPasswordField == "" then "" else if isOk (Utils.parsePassword state.newPasswordField) then "" else "is-invalid")
          , HA.style "max-width" "16em"
          ] []
        , H.div [HA.class "invalid-feedback"] [viewError (Utils.parsePassword state.newPasswordField)]
        ]
      , H.div [HA.class "col-8"]
        [ H.button
          [ HA.disabled <| state.requestStatus == AwaitingResponse || state.oldPasswordField == "" || (Utils.isErr <| Utils.parsePassword state.newPasswordField)
          , HE.onClick (config.changePassword {state | requestStatus=AwaitingResponse} {oldPassword=state.oldPasswordField, newPassword=state.newPasswordField})
          , HA.class "btn btn-sm py-0 btn-outline-primary"
          ]
          [ H.text <| if state.requestStatus == AwaitingResponse then "Changing..." else "Change password" ]
        , H.text " "
        , case state.requestStatus of
            Unstarted -> H.text ""
            AwaitingResponse -> H.text ""
            Succeeded -> Utils.greenText "Success!"
            Failed e -> Utils.redText e
        ]
      ]
    ]
