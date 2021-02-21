module Widgets.ChangePasswordWidget exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http

import Biatob.Proto.Mvp as Pb

import Biatob.Proto.Mvp exposing (StakeResult(..))
import Field exposing (Field)
import API

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

init : () -> (Model, Cmd Msg)
init _ =
  ( { oldPasswordField = Field.okIfEmpty <| Field.init "" <| \() s -> if s=="" then Err "" else Ok s
    , newPasswordField = Field.okIfEmpty <| Field.init "" <| \() s -> if s=="" then Err "" else Ok s
    , working = False
    , error = Nothing
    }
  , Cmd.none
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetOldPasswordField s -> ( { model | oldPasswordField = model.oldPasswordField |> Field.setStr s } , Cmd.none)
    SetNewPasswordField s -> ( { model | newPasswordField = model.newPasswordField |> Field.setStr s } , Cmd.none)
    ChangePassword ->
      ( { model | working = True , error = Nothing }
      , case (Field.parse () model.oldPasswordField, Field.parse () model.newPasswordField) of
          (Ok old, Ok new) -> API.postChangePassword ChangePasswordFinished {oldPassword=old, newPassword=new}
          _ -> Cmd.none
      )
    ChangePasswordFinished (Err e) ->
      ( { model | working = False , error = Just (Debug.toString e) }
      , Cmd.none
      )
    ChangePasswordFinished (Ok resp) ->
      case resp.changePasswordResult of
        Just (Pb.ChangePasswordResultOk _) ->
          init ()
        Just (Pb.ChangePasswordResultError e) ->
          ( { model | working = False , error = Just (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , error = Just "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
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

main : Program () Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
