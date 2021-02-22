port module Elements.AuthWidget exposing (main)

import Browser
import Http
import Json.Decode as JD
import Time

import Biatob.Proto.Mvp as Pb
import Utils

import Task
import API

import Widgets.AuthWidget as Widget

port authChanged : () -> Cmd msg

type alias Model = ( Widget.Context Msg , Widget.State )
type Msg
  = WidgetEvent (Maybe Widget.Event) Widget.State
  | LogInUsernameFinished (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsernameFinished (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOutFinished (Result Http.Error Pb.SignOutResponse)
  | Tick Time.Posix

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

authHandler : Widget.Handler Model
authHandler =
  { updateWidget = \f (ctx, m) -> (ctx, m |> f)
  , setAuth = \a (ctx, m) -> ({ctx | auth = a}, m)
  }

update : Msg -> Model -> ( Model, Cmd Msg )
update msg (ctx, state) =
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
    Tick now -> (({ctx | now = now}, state), Cmd.none)

    LogInUsernameFinished res ->
      ( Widget.handleLogInUsernameResponse authHandler res (ctx, state)
      , if Widget.isSuccessfulLogInUsername res then authChanged () else Cmd.none
      )
    RegisterUsernameFinished res ->
      ( Widget.handleRegisterUsernameResponse authHandler res (ctx, state)
      , if Widget.isSuccessfulRegisterUsername res then authChanged () else Cmd.none
      )
    SignOutFinished res ->
      ( Widget.handleSignOutResponse authHandler res (ctx, state)
      , if Widget.isSuccessfulSignOut res then authChanged () else Cmd.none
      )

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = \_ -> Time.every 1000 Tick
    , view = \(ctx, model) -> Widget.view ctx model
    , update = update
    }
