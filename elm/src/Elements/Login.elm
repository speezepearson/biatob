port module Elements.Login exposing (main)

import Browser
import Html as H
import Http
import Json.Decode as JD

import Globals
import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Biatob.Proto.Mvp as Pb
import API
import Utils

port copy : String -> Cmd msg
port navigate : Maybe String -> Cmd msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , destination : String
  }
type Msg
  = SetAuthWidget AuthWidget.State
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | Ignore

init : JD.Value -> ( Model , Cmd Msg )
init flags =
  let
    model =
      { globals = JD.decodeValue Globals.globalsDecoder flags |> Result.toMaybe |> Utils.must "flags"
      , navbarAuth = AuthWidget.init
      , destination = Utils.mustDecodeFromFlags JD.string "destination" flags
      }
  in
    ( model
    , case model.globals.authToken of
        Nothing -> Cmd.none
        Just _ -> navigate <| Just model.destination
    )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetAuthWidget widgetState ->
      ( { model | navbarAuth = widgetState } , Cmd.none )
    LogInUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postLogInUsername (LogInUsernameFinished req) req
      )
    LogInUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleLogInUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleLogInUsernameResponse res
        }
      , navigate <| Just model.destination
      )
    RegisterUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postRegisterUsername (RegisterUsernameFinished req) req
      )
    RegisterUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleRegisterUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleRegisterUsernameResponse res
        }
      , navigate <| Just model.destination
      )
    SignOut widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postSignOut (SignOutFinished req) req
      )
    SignOutFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSignOutResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleSignOutResponse res
        }
      , navigate (Just "/")
      )
    Ignore ->
      ( model , Cmd.none )


view : Model -> Browser.Document Msg
view model =
  { title = "Log in"
  , body = [
    Navbar.view
        { setState = SetAuthWidget
        , logInUsername = LogInUsername
        , register = RegisterUsername
        , signOut = SignOut
        , ignore = Ignore
        , auth = Globals.getAuth model.globals
        }
        model.navbarAuth
    ,
    H.main_ []
    [ H.h2 [] [H.text "Log in"]
    , H.text "...using the navbar at the top."
    ]
  ]}

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
