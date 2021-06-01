module Widgets.EmailSettingsWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http

import Biatob.Proto.Mvp as Pb
import Utils exposing (EmailAddress)

import API
import Parser exposing ((|.), (|=))
import Set

type alias Config msg =
  { setState : State -> msg
  , ignore : msg
  , setEmail : State -> Pb.SetEmailRequest -> msg
  , verifyEmail : State -> Pb.VerifyEmailRequest -> msg
  , updateSettings : State -> Pb.UpdateSettingsRequest -> msg
  , userInfo : Pb.GenericUserInfo
  }
type alias State =
  { emailField : String
  , codeField : String
  , working : Bool
  , notification : Html Never
  }

parseEmailAddress : State -> Result String EmailAddress
parseEmailAddress state =
  case Parser.run emailParser state.emailField of
    Ok s -> Ok s
    Err _ -> Err "doesn't look valid, sorry"

init : State
init =
  { emailField = ""
  , codeField = ""
  , working = False
  , notification = H.text ""
  }

emailParser : Parser.Parser EmailAddress
emailParser =
  let
    validNameChars = Set.fromList <| String.toList "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-+."
    validDomainChars = Set.fromList <| String.toList "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-+."
  in
  Parser.succeed (\s1 s2 -> s1 ++ "@" ++ s2)
    |= Parser.variable {start=\c -> Set.member c validNameChars, inner=\c -> Set.member c validNameChars, reserved=Set.empty}
    |. Parser.symbol "@"
    |= Parser.variable {start=\c -> Set.member c validDomainChars, inner=\c -> Set.member c validDomainChars, reserved=Set.empty}
    |. Parser.end

handleUpdateSettingsResponse : Result Http.Error Pb.UpdateSettingsResponse -> State -> State
handleUpdateSettingsResponse res state =
  { state | working = False
          , notification = case API.simplifyUpdateSettingsResponse res of
              Ok _ -> H.text ""
              Err e -> Utils.redText e
  }

handleSetEmailResponse : Result Http.Error Pb.SetEmailResponse -> State -> State
handleSetEmailResponse res state =
  { state | working = False
          , notification = case API.simplifySetEmailResponse res of
              Ok _ -> H.text ""
              Err e -> Utils.redText e
  }

handleVerifyEmailResponse : Result Http.Error Pb.VerifyEmailResponse -> State -> State
handleVerifyEmailResponse res state =
  { state | working = False
          , notification = case API.simplifyVerifyEmailResponse res of
              Ok _ -> H.text ""
              Err e -> Utils.redText e
  }

view : Config msg -> State -> Html msg
view config state =
  let
    emailFlowState : Pb.EmailFlowStateKind
    emailFlowState = config.userInfo |> Utils.mustUserInfoEmail |> Utils.mustEmailFlowStateKind

    isRegistered : Bool
    isRegistered = case emailFlowState of
      Pb.EmailFlowStateKindUnstarted _ -> False
      Pb.EmailFlowStateKindCodeSent _ -> False
      Pb.EmailFlowStateKindVerified _ -> True
    registrationBlock : Html msg
    registrationBlock =
      case config.userInfo |> Utils.mustUserInfoEmail |> Utils.mustEmailFlowStateKind of
        Pb.EmailFlowStateKindUnstarted _ ->
          H.div []
            [ H.text "Register an email address for notifications: "
            , H.input
                [ HA.type_ "email"
                , HA.disabled <| state.working
                , HA.placeholder "email@ddre.ss"
                , HE.onInput (\s -> config.setState {state | emailField=s})
                , HA.value state.emailField
                , Utils.onEnter (config.setEmail {state | working=True, notification=H.text ""} {email=state.emailField}) config.ignore
                ] []
              |> Utils.appendValidationError (if state.emailField == "" then Nothing else Utils.resultToErr (parseEmailAddress state))
            , H.button
                [ HE.onClick (config.setEmail {state | working=True, notification=H.text ""} {email=state.emailField})
                , HA.disabled <| state.working || Result.toMaybe (parseEmailAddress state) == Nothing
                ] [H.text "Send verification"]
            , state.notification |> H.map never
            ]
        Pb.EmailFlowStateKindCodeSent {email} ->
          H.div []
            [ H.text "I sent a verification code to "
            , Utils.b email
            , H.text ". Enter it here: "
            , H.input
                [ HA.disabled <| state.working
                , HA.placeholder "code"
                , Utils.onEnter (config.verifyEmail {state | working=True, notification=H.text ""} {code=state.codeField}) config.ignore
                , HE.onInput (\s -> config.setState {state | codeField=s})
                , HA.value state.codeField
                ] []
            , H.button
                [ HE.onClick (config.verifyEmail {state | working=True, notification=H.text ""} {code=state.codeField})
                , HA.disabled <| state.working || state.codeField == ""
                ] [H.text "Verify code"]
              -- TODO: "Resend email"
            , state.notification |> H.map never
            , H.text " (Or, "
            , H.button [HE.onClick (config.setEmail {state | working=True, notification=H.text ""} {email=""})] [H.text "delete email"]
            , H.text ")"
            ]
        Pb.EmailFlowStateKindVerified email ->
          H.div []
            [ H.text "Your email address is: "
            , Utils.b email
            , H.text ". "
            , H.button [HE.onClick (config.setEmail {state | working=True, notification=H.text ""} {email=""})] [H.text "delete?"]
            , H.br [] []
            , state.notification |> H.map never
            ]
  in
    H.div []
      [ registrationBlock
      , H.div []
          [ H.input
              [ HA.type_ "checkbox", HA.checked config.userInfo.emailRemindersToResolve
              , HA.disabled (state.working || not isRegistered)
              , HE.onInput (\_ -> config.updateSettings {state | working=True, notification=H.text ""} {emailRemindersToResolve=Just {value=not config.userInfo.emailRemindersToResolve}, emailResolutionNotifications=Nothing})
              ] []
          , H.text " Email reminders to resolve your predictions, when it's time?"
          ]
      , H.div []
          [ H.input
              [ HA.type_ "checkbox", HA.checked config.userInfo.emailResolutionNotifications
              , HA.disabled (state.working || not isRegistered)
              , HE.onInput (\_ -> config.updateSettings {state | working=True, notification=H.text ""} {emailRemindersToResolve=Nothing, emailResolutionNotifications=Just {value=not config.userInfo.emailResolutionNotifications}})
              ] []
          , H.text " Email notifications when predictions you've bet on resolve?"
          ]
      ]

subscriptions : State -> Sub msg
subscriptions _ = Sub.none
