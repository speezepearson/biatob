module ChangePasswordWidget exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD
import Protobuf.Encode as PE
import Protobuf.Decode as PD

import Biatob.Proto.Mvp as Pb
import Utils

import Biatob.Proto.Mvp exposing (StakeResult(..))

type alias Model =
  { oldPasswordField : String
  , newPasswordField : String
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
  ( { oldPasswordField = ""
    , newPasswordField = ""
    , working = False
    , error = Nothing
    }
  , Cmd.none
  )

postChangePassword : Pb.ChangePasswordRequest -> Cmd Msg
postChangePassword req =
  Http.post
    { url = "/api/ChangePassword"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toChangePasswordRequestEncoder req
    , expect = PD.expectBytes ChangePasswordFinished Pb.changePasswordResponseDecoder }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetOldPasswordField s -> ( { model | oldPasswordField = s } , Cmd.none)
    SetNewPasswordField s -> ( { model | newPasswordField = s } , Cmd.none)
    ChangePassword ->
      ( { model | working = True , error = Nothing }
      , postChangePassword {oldPassword=model.oldPasswordField, newPassword=model.newPasswordField}
      )
    ChangePasswordFinished (Err e) ->
      ( { model | working = False , error = Just (Debug.toString e) }
      , Cmd.none
      )
    ChangePasswordFinished (Ok resp) ->
      case resp.changePasswordResult of
        Just (Pb.ChangePasswordResultOk _) ->
          ( { model | oldPasswordField = "", newPasswordField = "", working = False }
          , Cmd.none
          )
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
  H.div []
    [ H.input [HA.type_ "password", HA.disabled model.working, HE.onInput SetOldPasswordField, HA.placeholder "old password", HA.value model.oldPasswordField] []
    , H.input [HA.type_ "password", HA.disabled model.working, HE.onInput SetNewPasswordField, HA.placeholder "new password", HA.value model.newPasswordField] []
    , H.button [HA.disabled model.working, HE.onClick ChangePassword] [H.text <| if model.working then "Changing..." else "Change password"]
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
