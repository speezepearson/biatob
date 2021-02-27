module Widgets.AuthWidget exposing (..)

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
type alias Context msg =
  { auth : Maybe Pb.AuthToken
  , now : Time.Posix
  , handle : Maybe Event -> State -> msg
  }
type alias State =
  { usernameField : Field () String
  , passwordField : Field () String
  , working : Bool
  , notification : Html Never
  }



type alias Handler a =
  { updateWidget : (State -> State) -> a -> a
  , setAuth : Maybe Pb.AuthToken -> a -> a
  }

getSuccessfulAuthFromLogInUsername : Result Http.Error Pb.LogInUsernameResponse -> Maybe Pb.AuthToken
getSuccessfulAuthFromLogInUsername res =
  case res |> Result.toMaybe |> Maybe.andThen .logInUsernameResult of
    Just (Pb.LogInUsernameResultOk authSuccess) -> Just <| Utils.mustAuthSuccessToken authSuccess
    _ -> Nothing
isSuccessfulLogInUsername res = getSuccessfulAuthFromLogInUsername res /= Nothing
handleLogInUsernameResponse : Handler a -> Result Http.Error Pb.LogInUsernameResponse -> a -> a
handleLogInUsernameResponse thing res a =
  a
  |> thing.updateWidget (\state ->
      case res of
        Err e -> { state | working = False , notification = Utils.redText (Debug.toString e)}
        Ok resp ->
          case resp.logInUsernameResult of
            Just (Pb.LogInUsernameResultOk _) ->
              { state | working = False , notification = H.text "" }
            Just (Pb.LogInUsernameResultError e) ->
              { state | working = False , notification = Utils.redText (Debug.toString e) }
            Nothing ->
              { state | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
    )
  |> case getSuccessfulAuthFromLogInUsername res of
      Just auth -> thing.setAuth (Just auth)
      _ -> identity

getSuccessfulAuthFromRegisterUsername : Result Http.Error Pb.RegisterUsernameResponse -> Maybe Pb.AuthToken
getSuccessfulAuthFromRegisterUsername res =
  case res |> Result.toMaybe |> Maybe.andThen .registerUsernameResult of
    Just (Pb.RegisterUsernameResultOk auth) -> Just <| Utils.mustAuthSuccessToken auth
    _ -> Nothing
isSuccessfulRegisterUsername res = getSuccessfulAuthFromRegisterUsername res /= Nothing
handleRegisterUsernameResponse : Handler a -> Result Http.Error Pb.RegisterUsernameResponse -> a -> a
handleRegisterUsernameResponse thing res a =
  a
  |> thing.updateWidget (\state ->
      case res of
        Err e -> { state | working = False , notification = Utils.redText (Debug.toString e)}
        Ok resp ->
          case resp.registerUsernameResult of
            Just (Pb.RegisterUsernameResultOk _) ->
              { state | working = False , notification = H.text "" }
            Just (Pb.RegisterUsernameResultError e) ->
              { state | working = False , notification = Utils.redText (Debug.toString e) }
            Nothing ->
              { state | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
    )
  |> case getSuccessfulAuthFromRegisterUsername res of
      Just auth -> thing.setAuth (Just auth)
      _ -> identity

isSuccessfulSignOut : Result Http.Error Pb.SignOutResponse -> Bool
isSuccessfulSignOut res =
  case res of
    Ok _ -> True
    Err _ -> False
handleSignOutResponse : Handler a -> Result Http.Error Pb.SignOutResponse -> a -> a
handleSignOutResponse thing res a =
  a
  |> thing.updateWidget (\state ->
      case res of
        Err e -> { state | working = False , notification = Utils.redText (Debug.toString e)}
        Ok _ -> { state | working = False , notification = H.text "" }
    )
  |> if isSuccessfulSignOut res then thing.setAuth Nothing else identity

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
            ( ctx.handle (Just <| LogInUsername    {username=username, password=password}) { state | working = True , notification = H.text "" }
            , ctx.handle (Just <| RegisterUsername {username=username, password=password}) { state | working = True , notification = H.text "" }
            )
          _ ->
            ( ctx.handle Nothing state
            , ctx.handle Nothing state
            )
      in
      H.div []
        [ Field.inputFor (\s -> ctx.handle Nothing {state | usernameField = state.usernameField |> Field.setStr s}) () state.usernameField
            H.input
            [ HA.disabled state.working
            , HA.style "width" "8em"
            , HA.type_ "text"
            , HA.placeholder "username"
            , HA.class "username-field"
            ] []
        , Field.inputFor (\s -> ctx.handle Nothing {state | passwordField = state.passwordField |> Field.setStr s}) () state.passwordField
            H.input
            [ HA.disabled state.working
            , HA.style "width" "8em"
            , HA.type_ "password"
            , HA.placeholder "password"
            , Utils.onEnter loginMsg (ctx.handle Nothing state)
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
        , state.notification |> H.map never
        ]
    Just auth ->
      H.div []
        [ H.text <| "Signed in as "
        , Utils.renderUser <| Utils.mustTokenOwner auth
        , H.text " "
        , H.button [HA.disabled state.working, HE.onClick (ctx.handle (Just <| SignOut {}) { state | working = True , notification = H.text ""})] [H.text "Sign out"]
        , state.notification |> H.map (\_ -> ctx.handle Nothing state)
        ]
