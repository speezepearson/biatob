module AuthWidget exposing (..)

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
import Set
import Field
import Biatob.Proto.Mvp exposing (LogInUsernameRequest)

type Event
  = LogInUsername Pb.LogInUsernameRequest
  | RegisterUsername Pb.RegisterUsernameRequest
  | SignOut Pb.SignOutRequest
  | Nevermind
type alias Context msg =
  { auth : Maybe Pb.AuthToken
  , now : Time.Posix
  , handle : Event -> State -> msg
  }
type alias State =
  { usernameField : Field () String
  , passwordField : Field () String
  , working : Bool
  , notification : Html ()
  }

handleLogInUsernameResponse : Result Http.Error Pb.LogInUsernameResponse -> State -> State
handleLogInUsernameResponse res state =
  case res of
    Err e ->
      { state | working = False , notification = Utils.redText (Debug.toString e) }
    Ok resp ->
      case resp.logInUsernameResult of
        Just (Pb.LogInUsernameResultOk _) ->
          { state | working = False , notification = H.text "" }
        Just (Pb.LogInUsernameResultError e) ->
          { state | working = False , notification = Utils.redText (Debug.toString e) }
        Nothing ->
          { state | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
handleRegisterUsernameResponse : Result Http.Error Pb.RegisterUsernameResponse -> State -> State
handleRegisterUsernameResponse res state =
  case res of
    Err e ->
      { state | working = False , notification = Utils.redText (Debug.toString e) }
    Ok resp ->
      case resp.registerUsernameResult of
        Just (Pb.RegisterUsernameResultOk _) ->
          { state | working = False , notification = H.text "" }
        Just (Pb.RegisterUsernameResultError e) ->
          { state | working = False , notification = Utils.redText (Debug.toString e) }
        Nothing ->
          { state | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
handleSignOutResponse : Result Http.Error Pb.SignOutResponse -> State -> State
handleSignOutResponse res state =
  case res of
    Err e ->
      { state | working = False , notification = Utils.redText (Debug.toString e) }
    Ok resp ->
      { state | working = False , notification = H.text "" }

illegalUsernameCharacters : String -> Set.Set Char
illegalUsernameCharacters s =
  let
    okayChars = ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" |> String.toList |> Set.fromList)
    presentChars = s |> String.toList |> Set.fromList
  in
    Set.diff presentChars okayChars

init : State
init =
  { usernameField = Field.okIfEmpty <| Field.init "" <| \() s ->
      if s=="" then
        Err ""
      else let badChars = illegalUsernameCharacters s in
      if not (Set.isEmpty badChars) then
        Err ("bad characters: " ++ Debug.toString (Set.toList badChars))
      else
        Ok s
  , passwordField = Field.okIfEmpty <| Field.init "" <| \() s ->
      if s=="" then
        Err ""
      else
        Ok s
  , working = False
  , notification = H.text ""
  }

view : Context msg -> State -> Html msg
view ctx state =
  case ctx.auth of
    Nothing ->
      let
        disableButtons = case (Field.parse () state.usernameField, Field.parse () state.passwordField) of
          (Ok _, Ok _) -> False
          _ -> True

        (loginMsg, registerMsg) = case (Field.parse () state.usernameField, Field.parse () state.passwordField) of
          (Ok username, Ok password) ->
            ( ctx.handle (LogInUsername    {username=username, password=password}) { state | working = True , notification = H.text "" }
            , ctx.handle (RegisterUsername {username=username, password=password}) { state | working = True , notification = H.text "" }
            )
          _ ->
            ( ctx.handle Nevermind state
            , ctx.handle Nevermind state
            )
      in
      H.div []
        [ Field.inputFor (\s -> ctx.handle Nevermind {state | usernameField = state.usernameField |> Field.setStr s}) () state.usernameField
            H.input
            [ HA.disabled state.working
            , HA.style "width" "8em"
            , HA.type_ "text"
            , HA.placeholder "username"
            , HA.class "username-field"
            ] []
        , Field.inputFor (\s -> ctx.handle Nevermind {state | passwordField = state.passwordField |> Field.setStr s}) () state.passwordField
            H.input
            [ HA.disabled state.working
            , HA.style "width" "8em"
            , HA.type_ "password"
            , HA.placeholder "password"
            , Utils.onEnter loginMsg (ctx.handle Nevermind state)
            ] []
        , H.button
            [ HA.disabled <| state.working || disableButtons
            , HE.onClick loginMsg
            ]
            [H.text "Log in"]
        , H.text " or "
        , H.button
            [ HA.disabled <| state.working || disableButtons
            , HE.onClick registerMsg
            ]
            [H.text "Sign up"]
        , state.notification |> H.map (\_ -> ctx.handle Nevermind state)
        ]
    Just auth ->
      H.div []
        [ H.text <| "Signed in as "
        , Utils.renderUser <| Utils.mustTokenOwner auth
        , H.text " "
        , H.button [HA.disabled state.working, HE.onClick (ctx.handle (SignOut {}) { state | working = True , notification = H.text ""})] [H.text "Sign out"]
        , state.notification |> H.map (\_ -> ctx.handle Nevermind state)
        ]
