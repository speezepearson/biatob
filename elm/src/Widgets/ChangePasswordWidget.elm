module Widgets.ChangePasswordWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Utils exposing (Password)

import Biatob.Proto.Mvp as Pb

import Biatob.Proto.Mvp exposing (StakeResult(..))
import Page

type alias Model =
  { oldPasswordField : String
  , newPasswordField : String
  , working : Bool
  , error : Maybe String
  }

type Msg
  = SetOldPasswordField Password
  | SetNewPasswordField Password
  | ChangePassword
  | ChangePasswordFinished (Result Http.Error Pb.ChangePasswordResponse)

init : Model
init =
  { oldPasswordField = ""
  , newPasswordField = ""
  , working = False
  , error = Nothing
  }

update : Msg -> Model -> (Model, Page.Command Msg)
update msg model =
  case msg of
    SetOldPasswordField s -> ( { model | oldPasswordField = s } , Page.NoCmd)
    SetNewPasswordField s -> ( { model | newPasswordField = s } , Page.NoCmd)
    ChangePassword ->
      ( { model | working = True , error = Nothing }
      , case Utils.parsePassword model.newPasswordField of
          Ok new -> Page.RequestCmd <| Page.ChangePasswordRequest ChangePasswordFinished {oldPassword=model.oldPasswordField, newPassword=new}
          _ -> Page.NoCmd
      )
    ChangePasswordFinished (Err e) ->
      ( { model | working = False , error = Just (Debug.toString e) }
      , Page.NoCmd
      )
    ChangePasswordFinished (Ok resp) ->
      case resp.changePasswordResult of
        Just (Pb.ChangePasswordResultOk _) ->
          ( init , Page.NoCmd )
        Just (Pb.ChangePasswordResultError e) ->
          ( { model | working = False , error = Just (Debug.toString e) }
          , Page.NoCmd
          )
        Nothing ->
          ( { model | working = False , error = Just "Invalid server response (neither Ok nor Error in protobuf)" }
          , Page.NoCmd
          )

view : Model -> Html Msg
view model =
  H.div []
    [ H.input
        [ HA.type_ "password"
        , HA.disabled <| model.working
        , HA.placeholder "old password"
        , HE.onInput SetOldPasswordField
        , HA.value model.oldPasswordField
        ] []
    , H.input
        [ HA.type_ "password"
        , HA.disabled <| model.working
        , HA.placeholder "new password"
        , HE.onInput SetNewPasswordField
        , HA.value model.newPasswordField
        ] []
      |> Utils.appendValidationError (Utils.resultToErr (Utils.parsePassword model.newPasswordField))
    , H.button
        [ HA.disabled <| model.working || model.oldPasswordField == "" || (Utils.isErr <| Utils.parsePassword model.newPasswordField)
        , HE.onClick ChangePassword
        ]
        [ H.text <| if model.working then "Changing..." else "Change password" ]
    , case model.error of
        Just e -> H.span [HA.style "color" "red"] [H.text e]
        Nothing -> H.text ""
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
