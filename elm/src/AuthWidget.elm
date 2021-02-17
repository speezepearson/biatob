port module AuthWidget exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as JD
import Json.Encode as JE
import Time
import Html exposing (s)

import Biatob.Proto.Mvp as Pb
import Utils
import Http
import Task

import API
import Field exposing (Field)

port authChanged : {loggedIn:Bool} -> Cmd msg

type Model
  = NoToken
      { usernameField : Field () String
      , passwordField : Field () String
      , working : Bool
      , error : Maybe String
      }
  | HasToken
      { token : Pb.AuthToken
      , working : Bool
      , error : Maybe String
      }

type Msg
  = SetUsernameField String
  | SetPasswordField String
  | LogInUsername
  | LogInUsernameComplete (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername
  | RegisterUsernameComplete (Result Http.Error Pb.RegisterUsernameResponse)
  | Tick Time.Posix
  | SignOut
  | SignOutComplete (Result Http.Error Pb.SignOutResponse)
  | Ignore

getAuth : Model -> Maybe Pb.AuthToken
getAuth model =
  case model of
     NoToken _ -> Nothing
     HasToken {token} -> Just token
hasAuth : Model -> Bool
hasAuth model =
  getAuth model /= Nothing

initNoToken : Model
initNoToken =
  NoToken
    { usernameField = Field.okIfEmpty <| Field.init "" <| \() s -> if s=="" then Err "" else Ok s
    , passwordField = Field.okIfEmpty <| Field.init "" <| \() s -> if s=="" then Err "" else Ok s
    , working = False
    , error = Nothing
    }

initHasToken : Pb.AuthToken -> Model
initHasToken token =
  HasToken
    { token = token
    , working = False
    , error = Nothing
    }

init : JD.Value -> ( Model , Cmd Msg )
init flags =
  ( case Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags of
      Just token -> initHasToken token
      Nothing -> initNoToken
  , Task.perform Tick Time.now
  )

view : Model -> Html Msg
view model =
  case model of
    NoToken m ->
      let
        disableButtons = case (Field.parse () m.usernameField, Field.parse () m.passwordField) of
          (Ok _, Ok _) -> False
          _ -> True
      in
      H.div []
        [ Field.inputFor SetUsernameField () m.usernameField
            H.input
            [ HA.disabled m.working
            , HA.style "width" "8em"
            , HA.type_ "text"
            , HA.placeholder "username"
            , HA.class "username-field"
            ] []
        , Field.inputFor SetPasswordField () m.passwordField
            H.input
            [ HA.disabled m.working
            , HA.style "width" "8em"
            , HA.type_ "password"
            , HA.placeholder "password"
            , Utils.onEnter LogInUsername Ignore
            ] []
        , H.button
            [ HA.disabled <| m.working || disableButtons
            , HE.onClick LogInUsername
            ]
            [H.text "Log in"]
        , H.text " or "
        , H.button
            [ HA.disabled <| m.working || disableButtons
            , HE.onClick RegisterUsername
            ]
            [H.text "Sign up"]
        , case m.error of
            Just e -> H.div [HA.style "color" "red"] [H.text e]
            Nothing -> H.text ""
        ]
    HasToken m ->
      H.div []
        [ H.text <| "Signed in as "
        , Utils.renderUser <| Utils.mustTokenOwner m.token
        , H.text " "
        , H.button [HA.disabled m.working, HE.onClick SignOut] [H.text "Sign out"]
        , case m.error of
            Just e -> H.div [HA.style "color" "red"] [H.text e]
            Nothing -> H.text ""
        ]

update : Msg -> Model -> ( Model , Cmd Msg )
update msg model =
  case (msg, model) of
  (SetUsernameField s, NoToken m) ->
    ( NoToken { m | usernameField = m.usernameField |> Field.setStr s } , Cmd.none )
  (SetPasswordField s, NoToken m) ->
    ( NoToken { m | passwordField = m.passwordField |> Field.setStr s } , Cmd.none )
  (LogInUsername, NoToken m) ->
    ( NoToken { m | working = True }
    , case (Field.parse () m.usernameField, Field.parse () m.passwordField) of
       (Ok username, Ok password) -> API.postLogInUsername LogInUsernameComplete {username=username, password=password}
       _ -> Cmd.none
    )
  (LogInUsernameComplete (Err e), NoToken m) ->
    ( NoToken { m | working = False , error = Just (Debug.toString e) }
    , Cmd.none
    )
  (LogInUsernameComplete (Ok resp), NoToken m) ->
    case resp.logInUsernameResult of
      Just (Pb.LogInUsernameResultOk token) ->
        ( initHasToken token
        , authChanged {loggedIn=True}
        )
      Just (Pb.LogInUsernameResultError e) ->
        ( NoToken { m | working = False , error = Just (Debug.toString e) }
        , Cmd.none
        )
      Nothing ->
        ( NoToken { m | working = False , error = Just "Invalid server response (neither Ok nor Error in protobuf)" }
        , Cmd.none
        )
  (RegisterUsername, NoToken m) ->
    ( NoToken { m | working = True }
    , case (Field.parse () m.usernameField, Field.parse () m.passwordField) of
       (Ok username, Ok password) -> API.postRegisterUsername RegisterUsernameComplete {username=username, password=password}
       _ -> Cmd.none
    )
  (RegisterUsernameComplete (Err e), NoToken m) ->
    ( NoToken { m | working = False , error = Just (Debug.toString e) }
    , Cmd.none )
  (RegisterUsernameComplete (Ok resp), NoToken m) ->
    case resp.registerUsernameResult of
      Just (Pb.RegisterUsernameResultOk token) ->
        ( initHasToken token
        , authChanged {loggedIn=True}
        )
      Just (Pb.RegisterUsernameResultError e) ->
        ( NoToken { m | working = False , error = Just (Debug.toString e) }
        , Cmd.none
        )
      Nothing ->
        ( NoToken { m | working = False , error = Just "Invalid server response (neither Ok nor Error in protobuf)" }
        , Cmd.none
        )
  (Tick _, NoToken _) ->
    ( model , Cmd.none )
  (SignOut, NoToken _) ->
    ( model , Cmd.none )
  (SignOutComplete _, NoToken _) ->
    ( model , Cmd.none )

  (SetUsernameField _, HasToken _) ->
    ( model , Cmd.none )
  (SetPasswordField _, HasToken _) ->
    ( model , Cmd.none )
  (LogInUsername, HasToken _) ->
    ( model , Cmd.none )
  (LogInUsernameComplete _, HasToken _) ->
    ( model , Cmd.none )
  (RegisterUsername, HasToken _) ->
    ( model , Cmd.none )
  (RegisterUsernameComplete _, HasToken _) ->
    ( model , Cmd.none )
  (Tick now, HasToken {token}) ->
    if Time.posixToMillis now > 1000*token.expiresUnixtime then
      ( init JE.null |> Tuple.first
      , authChanged {loggedIn=False}
      )
    else
      ( model , Cmd.none )
  (SignOut, HasToken m) ->
    ( HasToken { m | working = True , error = Nothing }
    , API.postSignOut SignOutComplete {}
    )
  (SignOutComplete _, HasToken _) ->
    ( initNoToken , authChanged {loggedIn=False} )

  (Ignore, _) ->
    ( model , Cmd.none )

subscriptions : Model -> Sub Msg
subscriptions _ = Time.every 1000 Tick

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }
