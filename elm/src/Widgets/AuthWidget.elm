module Widgets.AuthWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Html exposing (s)

import Biatob.Proto.Mvp as Pb
import Utils exposing (Username, Password)
import Http

import API
import Utils

type Msg
  = SetUsernameField Username
  | SetPasswordField Password
  | Ignore
  | LogInUsername
  | LogInUsernameFinished (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername
  | RegisterUsernameFinished (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut
  | SignOutFinished (Result Http.Error Pb.SignOutResponse)
type alias Config msg =
  { setState : State -> msg
  , logInUsername : State -> Pb.LogInUsernameRequest -> msg
  , register : State -> Pb.RegisterUsernameRequest -> msg
  , signOut : State -> Pb.SignOutRequest -> msg
  , ignore : msg
  , auth : Maybe Pb.AuthToken
  }
type alias State =
  { usernameField : String
  , passwordField : String
  , working : Bool
  , notification : Html Never
  }


handleLogInUsernameResponse : Result Http.Error Pb.LogInUsernameResponse -> State -> State
handleLogInUsernameResponse res state =
  { state | working = False
          , notification = case API.simplifyLogInUsernameResponse res of
              Ok _ -> H.text ""
              Err e -> Utils.redText e
  }
handleRegisterUsernameResponse : Result Http.Error Pb.RegisterUsernameResponse -> State -> State
handleRegisterUsernameResponse res state =
  { state | working = False
          , notification = case API.simplifyRegisterUsernameResponse res of
              Ok _ -> H.text ""
              Err e -> Utils.redText e
  }
handleSignOutResponse : Result Http.Error Pb.SignOutResponse -> State -> State
handleSignOutResponse res state =
  { state | working = False
          , notification = case API.simplifySignOutResponse res of
              Ok _ -> H.text ""
              Err e -> Utils.redText e
  }
init : State
init =
  { usernameField = ""
  , passwordField = ""
  , working = False
  , notification = H.text ""
  }

view : Config msg -> State -> Html msg
view config state =
  let
    logInMsg = config.logInUsername
      { state | working = True , notification = H.text "" }
      { username = state.usernameField , password = state.passwordField }
    registerMsg = config.register
      { state | working = True , notification = H.text "" }
      { username = state.usernameField , password = state.passwordField }
    signOutMsg = config.signOut
      { state | working = True , notification = H.text "" }
      {}
  in
  case config.auth of
    Nothing ->
      let
        disableButtons = case (Utils.parseUsername state.usernameField, Utils.parsePassword state.passwordField) of
          (Ok _, Ok _) -> False
          _ -> True
      in
      H.div []
        [ H.input
            [ HA.disabled state.working
            , HA.style "width" "8em"
            , HA.type_ "text"
            , HA.placeholder "username"
            , HA.class "username-field"
            , HA.class "watch-for-password-manager-fill"
            , HA.attribute "data-password-manager-target" "username"
            , HA.attribute "data-elm-value" state.usernameField
            , HE.onInput (\s -> config.setState {state | usernameField=s})
            , HA.value state.usernameField
            ] []
          |> Utils.appendValidationError (if state.usernameField == "" then Nothing else Utils.resultToErr (Utils.parseUsername state.usernameField))
        , H.input
            [ HA.disabled state.working
            , HA.style "width" "8em"
            , HA.type_ "password"
            , HA.placeholder "password"
            , HA.class "watch-for-password-manager-fill"
            , HA.attribute "data-password-manager-target" "password"
            , HA.attribute "data-elm-value" state.passwordField
            , HE.onInput (\s -> config.setState {state | passwordField=s})
            , HA.value state.passwordField
            , Utils.onEnter logInMsg config.ignore
            ] []
          |> Utils.appendValidationError (if state.passwordField == "" then Nothing else Utils.resultToErr (Utils.parsePassword state.passwordField))
        , H.button
            [ HA.disabled <| state.working || disableButtons
            , HE.onClick logInMsg
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
        , Utils.renderUser auth.owner
        , H.text " "
        , H.button [HA.disabled state.working, HE.onClick signOutMsg] [H.text "Sign out"]
        , state.notification |> H.map never
        ]
