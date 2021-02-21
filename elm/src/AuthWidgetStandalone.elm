port module AuthWidgetStandalone exposing (..)

import Browser
import Http
import Json.Decode as JD
import Time

import Biatob.Proto.Mvp as Pb
import Utils

import Task
import CopyWidget
import API

import AuthWidget as Widget

port authChanged : () -> Cmd msg

type alias Model = ( Widget.Context Msg , Widget.State )
type Msg
  = WidgetEvent (Maybe Widget.Event) Widget.State
  | LogInUsernameFinished (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsernameFinished (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOutFinished (Result Http.Error Pb.SignOutResponse)
  | Tick Time.Posix
  | Ignore

init : JD.Value -> (Model, Cmd Msg)
init flags =
  ( ( { auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
      , now = Time.millisToPosix 0
      , handle = WidgetEvent
      }
    , Widget.init
    )
  , Task.perform Tick Time.now
  )

update : Msg -> Model -> ( Model, Cmd Msg )
update msg (ctx, model) =
  case msg of
    WidgetEvent event newState ->
      let
        cmd = case event of
          Just (Widget.LogInUsername req) -> API.postLogInUsername LogInUsernameFinished req
          Just (Widget.RegisterUsername req) -> API.postRegisterUsername RegisterUsernameFinished req
          Just (Widget.SignOut req) -> API.postSignOut SignOutFinished req
          Nothing -> Cmd.none
      in
        ((ctx, newState), cmd)
    Tick now -> (({ctx | now = now}, model), Cmd.none)
    LogInUsernameFinished res ->
      ( ( { ctx | auth = case res |> Result.toMaybe |> Maybe.andThen .logInUsernameResult of
                    Just (Pb.LogInUsernameResultOk auth) -> Just auth
                    _ -> ctx.auth
          }
        , model |> Widget.handleLogInUsernameResponse res
        )
      , authChanged ()
      )
    RegisterUsernameFinished res ->
      ( ( { ctx | auth = case res |> Result.toMaybe |> Maybe.andThen .registerUsernameResult of
                    Just (Pb.RegisterUsernameResultOk auth) -> Just auth
                    _ -> ctx.auth
          }
        , model |> Widget.handleRegisterUsernameResponse res
        )
      , authChanged ()
      )
    SignOutFinished res ->
      ( ( { ctx | auth = case res of
                    Ok _ -> Nothing
                    Err _ -> ctx.auth
          }
        , model |> Widget.handleSignOutResponse res
        )
      , authChanged ()
      )
    Ignore -> ((ctx, model), Cmd.none)

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = \_ -> Time.every 1000 Tick
    , view = \(ctx, model) -> Widget.view ctx model
    , update = update
    }
