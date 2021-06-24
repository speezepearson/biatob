module Widgets.AuthWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Html exposing (s)

import Biatob.Proto.Mvp as Pb
import Http

import API
import Utils exposing (isOk, viewError, RequestStatus(..))

type alias Config msg =
  { setState : State -> msg
  , logInUsername : State -> Pb.LogInUsernameRequest -> msg
  , register : State -> Pb.RegisterUsernameRequest -> msg
  , signOut : State -> Pb.SignOutRequest -> msg
  , ignore : msg
  , auth : Maybe Pb.AuthToken
  , id : String
  }
type alias State =
  { usernameField : String
  , passwordField : String
  , requestStatus : RequestStatus
  }

type alias DomModification =
  { authWidgetId : String
  , field : String
  , newValue : String
  }

handleDomModification : DomModification -> State -> State
handleDomModification mod state =
  case (Debug.log "handling external AuthWidget modification" mod).field of
     "username" -> { state | usernameField = mod.newValue }
     "password" -> { state | passwordField = mod.newValue }
     _ -> Debug.todo <| "invalid DomModification event; expected 'field' = 'username' or 'password', got '" ++ mod.field ++ "'"

handleLogInUsernameResponse : Result Http.Error Pb.LogInUsernameResponse -> State -> State
handleLogInUsernameResponse res state =
  { state | requestStatus = case API.simplifyLogInUsernameResponse res of
              Ok _ -> Succeeded
              Err e -> Failed e
  }
handleRegisterUsernameResponse : Result Http.Error Pb.RegisterUsernameResponse -> State -> State
handleRegisterUsernameResponse res state =
  { state | requestStatus = case API.simplifyRegisterUsernameResponse res of
              Ok _ -> Succeeded
              Err e -> Failed e
  }
handleSignOutResponse : Result Http.Error Pb.SignOutResponse -> State -> State
handleSignOutResponse res state =
  { state | requestStatus = case API.simplifySignOutResponse res of
              Ok _ -> Succeeded
              Err e -> Failed e
  }
init : State
init =
  { usernameField = ""
  , passwordField = ""
  , requestStatus = Unstarted
  }

row : List (Html msg) -> Html msg
row hs = H.div [HA.class "row"] hs

col : List (Html msg) -> Html msg
col hs = H.div [HA.class "col"] hs

view : Config msg -> State -> Html msg
view config state =
  H.div
  [ HA.id config.id
  , HA.class "row row-cols-sm-auto g-2"
  ]
  <| case config.auth of
    Nothing ->
      let
        canSubmit = case (Utils.parseUsername state.usernameField, Utils.parsePassword state.passwordField) of
          (Ok _, Ok _) -> True
          _ -> False
        logInMsg =
          if canSubmit then
            config.logInUsername
              { state | requestStatus = AwaitingResponse }
              { username = state.usernameField , password = state.passwordField }
          else
            config.ignore
        registerMsg =
          if canSubmit then
            config.register
            { state | requestStatus = AwaitingResponse }
            { username = state.usernameField , password = state.passwordField }
          else
            config.ignore
      in
      [ let username = Utils.parseUsername state.usernameField in
        H.div [HA.class "col-4"]
        [ H.input
          [ HA.disabled (state.requestStatus == AwaitingResponse)
          , HA.style "width" "8em"
          , HA.name "username"
          , HA.type_ "text"
          , HA.placeholder "username"
          , HA.class "username-field"
          , HA.class "form-control form-control-sm"
          , HA.class (if state.usernameField == "" then "" else if isOk username then "" else "is-invalid")
          , HA.attribute "data-elm-value" state.usernameField
          , HE.onInput (\s -> config.setState {state | usernameField=s})
          , HA.value state.usernameField
          ] []
        , H.div [HA.class "invalid-feedback"] [viewError username]
        ]
      , let password = Utils.parsePassword state.passwordField in
        H.div [HA.class "col-4"]
        [ H.input
          [ HA.disabled (state.requestStatus == AwaitingResponse)
          , HA.style "width" "8em"
          , HA.name "password"
          , HA.type_ "password"
          , HA.placeholder "password"
          , HA.attribute "data-elm-value" state.passwordField
          , HA.class "form-control form-control-sm"
          , HA.class (if state.passwordField == "" then "" else if isOk password then "" else "is-invalid")
          , HE.onInput (\s -> config.setState {state | passwordField=s})
          , HA.value state.passwordField
          , Utils.onEnter logInMsg config.ignore
          ] []
        , H.div [HA.class "invalid-feedback"] [viewError password]
        ]
      , H.div [HA.class "col-4"]
        [ H.button
          [ HA.disabled <| (state.requestStatus == AwaitingResponse) || not canSubmit
          , HE.onClick logInMsg
          , HA.class "btn btn-sm py-0 btn-primary"
          ]
          [H.text "Log in"]
        , H.span [] [H.text " or "]
        , H.button
          [ HA.disabled <| (state.requestStatus == AwaitingResponse) || not canSubmit
          , HE.onClick registerMsg
          , HA.class "btn btn-sm py-0 btn-secondary"
          ]
          [H.text "Sign up"]
        ]
      , case state.requestStatus of
          Unstarted -> H.text ""
          AwaitingResponse -> H.text ""
          Succeeded -> H.text ""
          Failed e -> Utils.redText e
      ]
    Just auth ->
        [ H.div [HA.class "col-8"]
          [ H.span [HA.class "align-middle"] [H.text <| "Signed in as ", Utils.b auth.owner]
          ]
        , H.div [HA.class "col-4"]
          [ H.button
            [ HA.class "btn btn-sm py-0 btn-outline-primary"
            , HA.disabled (state.requestStatus == AwaitingResponse)
            , HE.onClick (config.signOut { state | requestStatus = AwaitingResponse } {})
            ] [H.text "Sign out"]
          , case state.requestStatus of
              Unstarted -> H.text ""
              AwaitingResponse -> H.text ""
              Succeeded -> H.text ""
              Failed e -> Utils.redText e
          ]
        ]
