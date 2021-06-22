module Widgets.EmailSettingsWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http

import Biatob.Proto.Mvp as Pb
import Utils exposing (EmailAddress, RequestStatus(..), isOk, viewError)

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
  , registrationRequestStatus : RequestStatus
  , updateSettingsRequestStatus : RequestStatus
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
  , registrationRequestStatus = Unstarted
  , updateSettingsRequestStatus = Unstarted
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
  { state | updateSettingsRequestStatus = case API.simplifyUpdateSettingsResponse res of
              Ok _ -> Succeeded
              Err e -> Failed e
  }

handleSetEmailResponse : Result Http.Error Pb.SetEmailResponse -> State -> State
handleSetEmailResponse res state =
  { state | registrationRequestStatus = case API.simplifySetEmailResponse res of
              Ok _ -> Succeeded
              Err e -> Failed e
  }

handleVerifyEmailResponse : Result Http.Error Pb.VerifyEmailResponse -> State -> State
handleVerifyEmailResponse res state =
  { state | registrationRequestStatus = case API.simplifyVerifyEmailResponse res of
              Ok _ -> Succeeded
              Err e -> Failed e
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
      case emailFlowState of
        Pb.EmailFlowStateKindUnstarted _ ->
          H.div [HA.class "form-group"]
            [ H.label [] [H.text "Register an email address:"]
            , H.input
              [ HA.type_ "email"
              , HA.disabled <| state.registrationRequestStatus == AwaitingResponse
              , HA.placeholder "email@ddre.ss"
              , HE.onInput (\s -> config.setState {state | emailField=s})
              , HA.value state.emailField
              , Utils.onEnter (config.setEmail {state | registrationRequestStatus = AwaitingResponse} {email=state.emailField}) config.ignore
              , HA.class "form-control form-control-sm mx-1 d-inline-block"
              , HA.class <| if state.emailField == "" then "" else if isOk (parseEmailAddress state) then "" else "is-invalid"
              , HA.style "width" "18em"
              ] []
            , H.button
                [ HE.onClick (config.setEmail {state | registrationRequestStatus = AwaitingResponse} {email=state.emailField})
                , HA.disabled <| state.registrationRequestStatus == AwaitingResponse || Result.toMaybe (parseEmailAddress state) == Nothing
                , HA.class "btn btn-sm btn-primary"
                ] [H.text "Send verification"]
              , H.text " "
              , case state.registrationRequestStatus of
                  Unstarted -> H.text ""
                  AwaitingResponse -> H.text ""
                  Succeeded -> Utils.greenText "Success!"
                  Failed e -> Utils.redText e
            , H.div [HA.class "invalid-feedback"] [viewError (parseEmailAddress state)]
            ]
        Pb.EmailFlowStateKindCodeSent {email} ->
          H.div [HA.class "form-group"]
            [ H.text "I sent a verification code to "
            , Utils.b email
            , H.text ". Enter it here: "
            , H.input
              [ HA.disabled <| state.registrationRequestStatus == AwaitingResponse
              , HA.placeholder "code"
              , Utils.onEnter (config.verifyEmail {state | registrationRequestStatus = AwaitingResponse} {code=state.codeField}) config.ignore
              , HE.onInput (\s -> config.setState {state | codeField=s})
              , HA.value state.codeField
              , HA.class "form-control form-control-sm mx-1"
              , HA.style "display" "inline-block"
              , HA.style "width" "12em"
              ] []
            , H.button
              [ HE.onClick (config.verifyEmail {state | registrationRequestStatus = AwaitingResponse} {code=state.codeField})
              , HA.disabled <| state.registrationRequestStatus == AwaitingResponse || state.codeField == ""
              , HA.class "btn btn-sm btn-primary"
              ] [H.text "Verify code"]
            , H.text " "
            -- TODO: "Resend email"
            , H.text " (Or, "
            , H.button
                [ HE.onClick (config.setEmail {state | registrationRequestStatus = AwaitingResponse} {email=""})
                , HA.class "btn btn-sm btn-outline-secondary"
                ]
                [H.text "delete email"]
            , H.text ")"
            , case state.registrationRequestStatus of
                Unstarted -> H.text ""
                AwaitingResponse -> H.text ""
                Succeeded -> H.div [] [Utils.greenText "Success!"]
                Failed e -> H.div [] [Utils.redText e]
            ]
        Pb.EmailFlowStateKindVerified email ->
          H.div []
            [ H.text "Your email address is: "
            , Utils.b email
            , H.text ". "
            , H.button
                [ HE.onClick (config.setEmail {state | registrationRequestStatus = AwaitingResponse} {email=""})
                , HA.class "btn btn-sm btn-outline-primary"
                ]
                [H.text "delete?"]
            , H.text " "
            , case state.registrationRequestStatus of
                Unstarted -> H.text ""
                AwaitingResponse -> H.text ""
                Succeeded -> Utils.greenText "Success!"
                Failed e -> Utils.redText e
            ]
  in
    H.form
      [ HA.class "needs-validation"
      , HE.onSubmit config.ignore
      ]
      [ registrationBlock
      , if isRegistered then
          H.div [HA.class "mx-4"]
          [ H.div []
            [ H.input
                [ HA.type_ "checkbox", HA.checked config.userInfo.allowEmailInvitations
                , HA.class "form-check-input"
                , HA.id "allowEmailInvitationsCheckbox"
                , HA.disabled (state.updateSettingsRequestStatus == AwaitingResponse || not isRegistered)
                , HE.onInput (\_ -> config.updateSettings {state | updateSettingsRequestStatus = AwaitingResponse} {emailRemindersToResolve=Nothing, emailResolutionNotifications=Nothing, allowEmailInvitations=Just {value=not config.userInfo.allowEmailInvitations}})
                ] []
            , H.label [HA.class "ms-1", HA.for "allowEmailInvitationsCheckbox"] [ H.text " Email notifications when new people want to bet against you?" ]
            , H.div [HA.class "ms-4"]
              [ H.text "(Highly recommended! This will make it "
                , Utils.i "way"
                , H.text " smoother when one of your friends wants to bet against you for the first time.)"
              ]
            ]
          , H.div []
              [ H.input
                  [ HA.type_ "checkbox", HA.checked config.userInfo.emailRemindersToResolve
                  , HA.class "form-check-input"
                  , HA.id "emailRemindersToResolveCheckbox"
                  , HA.disabled (state.updateSettingsRequestStatus == AwaitingResponse || not isRegistered)
                  , HE.onInput (\_ -> config.updateSettings {state | updateSettingsRequestStatus = AwaitingResponse} {emailRemindersToResolve=Just {value=not config.userInfo.emailRemindersToResolve}, emailResolutionNotifications=Nothing, allowEmailInvitations=Nothing})
                  ] []
              , H.label [HA.class "ms-1", HA.for "emailRemindersToResolveCheckbox"] [H.text " Email reminders to resolve your predictions, when it's time?"]
              ]
          , H.div []
              [ H.input
                  [ HA.type_ "checkbox", HA.checked config.userInfo.emailResolutionNotifications
                  , HA.class "form-check-input"
                  , HA.id "emailResolutionNotificationsCheckbox"
                  , HA.disabled (state.updateSettingsRequestStatus == AwaitingResponse || not isRegistered)
                  , HE.onInput (\_ -> config.updateSettings {state | updateSettingsRequestStatus = AwaitingResponse} {emailRemindersToResolve=Nothing, emailResolutionNotifications=Just {value=not config.userInfo.emailResolutionNotifications}, allowEmailInvitations=Nothing})
                  ] []
              , H.label [HA.class "ms-1", HA.for "emailResolutionNotificationsCheckbox"] [H.text "Email notifications when predictions you've bet on resolve?"]
              ]
          , H.div []
            [ case state.updateSettingsRequestStatus of
                Unstarted -> H.text ""
                AwaitingResponse -> H.text ""
                Succeeded -> Utils.greenText "Updated settings!"
                Failed e -> Utils.redText e
            ]
          ]
        else
          H.text ""
      ]

subscriptions : State -> Sub msg
subscriptions _ = Sub.none
