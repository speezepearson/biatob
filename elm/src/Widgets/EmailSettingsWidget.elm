module Widgets.EmailSettingsWidget exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import Field exposing (Field)
import API

type Event
  = Ignore
  | SetEmail Pb.SetEmailRequest
  | VerifyEmail Pb.VerifyEmailRequest
  | UpdateSettings Pb.UpdateSettingsRequest
type alias Context msg =
  { handle : (Maybe Event) -> State -> msg
  , emailFlowState : Pb.EmailFlowState
  , emailRemindersToResolve : Bool
  , emailResolutionNotifications : Bool
  }
type alias State =
  { emailField : Field () String
  , codeField : Field () String
  , working : Bool
  , notification : Html Never
  }

init : State
init =
  { emailField = Field.okIfEmpty <| Field.init "" <| \() s -> if String.contains "@" s then Ok s else Err "must be an email address"
  , codeField = Field.init "" <| \() s -> if String.isEmpty s then Err "enter code" else Ok s
  , working = False
  , notification = H.text ""
  }


type alias Handler a =
  { updateWidget : (State -> State) -> a -> a
  , setEmailFlowState : Pb.EmailFlowState -> a -> a
  }

handleSetEmailResponse : Handler a -> Result Http.Error Pb.SetEmailResponse -> a -> a
handleSetEmailResponse thing res a =
  a
  |> thing.updateWidget (\state ->
      case res of
        Err e ->
          { state | working = False , notification = Utils.redText (Debug.toString e) }
        Ok resp ->
          case resp.setEmailResult of
            Just (Pb.SetEmailResultOk _) ->
              { state | working = False , notification = H.text "" }
            Just (Pb.SetEmailResultError e) ->
              { state | working = False , notification = Utils.redText (Debug.toString e) }
            Nothing ->
              { state | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
      )
  |> case res |> Result.toMaybe |> Maybe.andThen .setEmailResult of
      Just (Pb.SetEmailResultOk newState) -> thing.setEmailFlowState newState
      _ -> identity

handleVerifyEmailResponse : Handler a -> Result Http.Error Pb.VerifyEmailResponse -> a -> a
handleVerifyEmailResponse thing res a =
  a
  |> thing.updateWidget (\state ->
      case res of
        Err e ->
          { state | working = False , notification = Utils.redText (Debug.toString e) }
        Ok resp ->
          case resp.verifyEmailResult of
            Just (Pb.VerifyEmailResultOk _) ->
              { state | working = False , notification = H.text "" }
            Just (Pb.VerifyEmailResultError e) ->
              { state | working = False , notification = Utils.redText (Debug.toString e) }
            Nothing ->
              { state | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
      )
  |> case res |> Result.toMaybe |> Maybe.andThen .verifyEmailResult of
      Just (Pb.VerifyEmailResultOk newState) -> thing.setEmailFlowState newState
      _ -> identity

handleUpdateSettingsResponse : Result Http.Error Pb.UpdateSettingsResponse -> State -> State
handleUpdateSettingsResponse res state =
  case res of
    Err e ->
      { state | working = False , notification = Utils.redText (Debug.toString e) }
    Ok resp ->
      case resp.updateSettingsResult of
        Just (Pb.UpdateSettingsResultOk _) ->
          { state | working = False , notification = H.text "" }
        Just (Pb.UpdateSettingsResultError e) ->
          { state | working = False , notification = Utils.redText (Debug.toString e) }
        Nothing ->
          { state | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }

view : Context msg -> State -> Html msg
view ctx state =
  case ctx.emailFlowState.emailFlowStateKind of
    Just (Pb.EmailFlowStateKindUnstarted _) ->
      let
        submitMsg = case Field.parse () state.emailField of
          Ok email -> ctx.handle (Just <| SetEmail {email=email}) { state | working = True , notification = H.text "" }
          Err _ -> ctx.handle Nothing state
      in
      H.div []
        [ H.text "Register an email address for notifications: "
        , Field.inputFor (\s -> ctx.handle Nothing {state | emailField = state.emailField |> Field.setStr s}) () state.emailField
            H.input
            [ HA.type_ "email"
            , HA.disabled <| state.working
            , HA.placeholder "email@ddre.ss"
            , Utils.onEnter submitMsg (ctx.handle Nothing state)
            ] []
        , H.button
            [ HE.onClick submitMsg
            , HA.disabled <| state.working || Result.toMaybe (Field.parse () state.emailField) == Nothing
            ] [H.text "Send verification"]
        , state.notification |> H.map never
        ]
    Just (Pb.EmailFlowStateKindCodeSent {email}) ->
      let
        submitMsg = case Field.parse () state.codeField of
          Ok code -> ctx.handle (Just <| VerifyEmail {code=code}) { state | working = True , notification = H.text "" }
          Err _ -> ctx.handle Nothing state
      in
      H.div []
        [ H.text "I sent a verification code to "
        , Utils.b email
        , H.text ". Enter it here: "
        , Field.inputFor (\s -> ctx.handle Nothing {state | codeField = state.codeField |> Field.setStr s}) () state.codeField
            H.input
            [ HA.disabled <| state.working
            , HA.placeholder "code"
            , Utils.onEnter submitMsg (ctx.handle Nothing state)
            ] []
        , H.button
            [ HE.onClick submitMsg
            , HA.disabled <| state.working || Result.toMaybe (Field.parse () state.codeField) == Nothing
            ] [H.text "Verify code"]
          -- TODO: "Resend email"
        , state.notification |> H.map never
        ]
    Just (Pb.EmailFlowStateKindVerified email) ->
      H.div []
        [ H.text "Your email address is: "
        , H.strong [] [H.text email]
        , H.div []
            [ H.input
                [ HA.type_ "checkbox", HA.checked ctx.emailRemindersToResolve
                , HA.disabled state.working
                , HE.onInput (\_ -> ctx.handle (Just <| UpdateSettings {emailRemindersToResolve=Just <| Pb.MaybeBool <| not ctx.emailRemindersToResolve, emailResolutionNotifications=Nothing}) { state | working = True , notification = H.text "" })
                ] []
            , H.text " Email reminders to resolve your predictions, when it's time?"
            ]
        , H.div []
            [ H.input
                [ HA.type_ "checkbox", HA.checked ctx.emailResolutionNotifications
                , HA.disabled state.working
                , HE.onInput (\_ -> ctx.handle (Just <| UpdateSettings {emailRemindersToResolve=Nothing, emailResolutionNotifications=Just <| Pb.MaybeBool <| not ctx.emailResolutionNotifications}) { state | working = True , notification = H.text "" })
                ] []
            , H.text " Email notifications when predictions you've bet on resolve?"
            ]
        , H.br [] []
        , state.notification |> H.map never
        ]
    
    Nothing -> Utils.redText "Sorry, you've hit a bug! This should show your email settings."
