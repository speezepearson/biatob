module Widgets.ChangePasswordWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http

import Biatob.Proto.Mvp as Pb

import Biatob.Proto.Mvp exposing (StakeResult(..))
import Field exposing (Field)
import Page

type alias Model =
  { oldPasswordField : Field () String
  , newPasswordField : Field () String
  , working : Bool
  , error : Maybe String
  }

type Msg
  = SetOldPasswordField String
  | SetNewPasswordField String
  | ChangePassword
  | ChangePasswordFinished (Result Http.Error Pb.ChangePasswordResponse)

init : Model
init =
  { oldPasswordField = Field.okIfEmpty <| Field.init "" <| \() s -> if s=="" then Err "" else Ok s
  , newPasswordField = Field.okIfEmpty <| Field.init "" <| \() s -> if s=="" then Err "" else Ok s
  , working = False
  , error = Nothing
  }

update : Msg -> Model -> (Model, Page.Command Msg)
update msg model =
  case msg of
    SetOldPasswordField s -> ( { model | oldPasswordField = model.oldPasswordField |> Field.setStr s } , Page.NoCmd)
    SetNewPasswordField s -> ( { model | newPasswordField = model.newPasswordField |> Field.setStr s } , Page.NoCmd)
    ChangePassword ->
      ( { model | working = True , error = Nothing }
      , case (Field.parse () model.oldPasswordField, Field.parse () model.newPasswordField) of
          (Ok old, Ok new) -> Page.RequestCmd <| Page.ChangePasswordRequest ChangePasswordFinished {oldPassword=old, newPassword=new}
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
  let
    disableButton = not (Field.isValid () model.oldPasswordField && Field.isValid () model.newPasswordField)
  in
  H.div []
    [ Field.inputFor SetOldPasswordField () model.oldPasswordField
        H.input
        [ HA.type_ "password"
        , HA.disabled <| model.working
        , HA.placeholder "old password"
        ] []
    , Field.inputFor SetNewPasswordField () model.newPasswordField
        H.input
        [ HA.type_ "password"
        , HA.disabled <| model.working
        , HA.placeholder "new password"
        ] []
    , H.button [HA.disabled <| model.working || disableButton, HE.onClick ChangePassword] [H.text <| if model.working then "Changing..." else "Change password"]
    , case model.error of
        Just e -> H.span [HA.style "color" "red"] [H.text e]
        Nothing -> H.text ""
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
