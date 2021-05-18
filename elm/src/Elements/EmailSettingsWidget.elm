port module Elements.EmailSettingsWidget exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils exposing (WorkingState(..))

import Field exposing (Field)
import Parser exposing ((|.), (|=))
import Set
import API

port emailSettingsChanged : () -> Cmd msg

type Msg
  = Ignore
  | SetEmailField String
  | SetCodeField String
  | SetEmailResolutionNotifications Bool
  | SetEmailRemindersToResolve Bool
  | UpdateSettingsFinished (Result Http.Error Pb.UpdateSettingsResponse)
  | DissociateEmail
  | SetEmail
  | SetEmailFinished (Result Http.Error Pb.SetEmailResponse)
  | VerifyEmail
  | VerifyEmailFinished (Result Http.Error Pb.VerifyEmailResponse)

type alias Model =
  { userInfo : Pb.GenericUserInfo
  , emailField : Field () String
  , codeField : Field () String
  , setEmailWorking : WorkingState
  , updateSettingsWorking : WorkingState
  }

init : JD.Value -> ( Model , Cmd Msg )
init flags =
  ( { userInfo = Utils.mustDecodePbFromFlags Pb.genericUserInfoDecoder "userInfoPbB64" flags
    , emailField = Field.okIfEmpty <| Field.init "" <| \() s ->
        case Parser.run emailParser s of
          Ok _ -> Ok s
          Err _ -> Err "doesn't look valid, sorry"
    , codeField = Field.init "" <| \() s -> if String.isEmpty s then Err "enter code" else Ok s
    , setEmailWorking = Awaiting { notification = H.text "" }
    , updateSettingsWorking = Awaiting { notification = H.text "" }
    }
  , Cmd.none
  )

emailParser : Parser.Parser String
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

update : Msg -> Model -> ( Model , Cmd Msg )
update msg model =
  case msg of
    Ignore -> ( model , Cmd.none )
    SetEmailField s -> ( { model | emailField = model.emailField |> Field.setStr s } , Cmd.none )
    SetCodeField s -> ( { model | codeField = model.codeField |> Field.setStr s } , Cmd.none )
    SetEmailRemindersToResolve value ->
      ( { model | updateSettingsWorking = Working }
      , API.postUpdateSettings UpdateSettingsFinished {emailRemindersToResolve=Just {value=value}, emailResolutionNotifications=Nothing}
      )
    SetEmailResolutionNotifications value ->
      ( { model | updateSettingsWorking = Working }
      , API.postUpdateSettings UpdateSettingsFinished {emailRemindersToResolve=Nothing, emailResolutionNotifications=Just {value=value}}
      )
    UpdateSettingsFinished res ->
      case res of
        Err e ->
          ( { model | updateSettingsWorking = Awaiting { notification = Utils.redText (Debug.toString e) } }
          , Cmd.none
          )
        Ok resp ->
          case resp.updateSettingsResult of
            Just (Pb.UpdateSettingsResultOk _) ->
              ( { model | updateSettingsWorking = Awaiting { notification = H.text "" } }
              , emailSettingsChanged ()
              )
            Just (Pb.UpdateSettingsResultError e) ->
              ( { model | updateSettingsWorking = Awaiting { notification = Utils.redText (Debug.toString e) } }
              , Cmd.none
              )
            Nothing ->
              ( { model | updateSettingsWorking = Awaiting { notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" } }
              , Cmd.none
              )

    DissociateEmail ->
      ( { model | setEmailWorking = Working }
      , API.postSetEmail SetEmailFinished {email=""}
      )
    SetEmail ->
      case Field.parse () model.emailField of
        Err _ -> ( model , Cmd.none )
        Ok email ->
          ( { model | setEmailWorking = Working }
          , API.postSetEmail SetEmailFinished {email=email}
          )
    SetEmailFinished res ->
      case res of
        Err e ->
          ( { model | setEmailWorking = Awaiting { notification = Utils.redText (Debug.toString e) } }
          , Cmd.none
          )
        Ok resp ->
          case resp.setEmailResult of
            Just (Pb.SetEmailResultOk _) ->
              ( { model | setEmailWorking = Awaiting { notification = H.text "" } }
              , emailSettingsChanged ()
              )
            Just (Pb.SetEmailResultError e) ->
              ( { model | setEmailWorking = Awaiting { notification = Utils.redText (Debug.toString e) } }
              , Cmd.none
              )
            Nothing ->
              ( { model | setEmailWorking = Awaiting { notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" } }
              , Cmd.none
              )

    VerifyEmail ->
      case Field.parse () model.codeField of
        Err _ -> ( model , Cmd.none )
        Ok code ->
          ( { model | setEmailWorking = Working }
          , API.postVerifyEmail VerifyEmailFinished {code=code}
          )
    VerifyEmailFinished res ->
      case res of
        Err e ->
          ( { model | setEmailWorking = Awaiting { notification = Utils.redText (Debug.toString e) } }
          , Cmd.none
          )
        Ok resp ->
          case resp.verifyEmailResult of
            Just (Pb.VerifyEmailResultOk _) ->
              ( { model | setEmailWorking = Awaiting { notification = H.text "" } }
              , emailSettingsChanged ()
              )
            Just (Pb.VerifyEmailResultError e) ->
              ( { model | setEmailWorking = Awaiting { notification = Utils.redText (Debug.toString e) } }
              , Cmd.none
              )
            Nothing ->
              ( { model | setEmailWorking = Awaiting { notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" } }
              , Cmd.none
              )

view : Model -> Html Msg
view model =
  let
    emailFlowState : Pb.EmailFlowStateKind
    emailFlowState = model.userInfo |> Utils.mustUserInfoEmail |> Utils.mustEmailFlowStateKind

    isRegistered : Bool
    isRegistered = case emailFlowState of
      Pb.EmailFlowStateKindUnstarted _ -> False
      Pb.EmailFlowStateKindCodeSent _ -> False
      Pb.EmailFlowStateKindVerified _ -> True
    registrationBlock : Html Msg
    registrationBlock =
      case model.userInfo |> Utils.mustUserInfoEmail |> Utils.mustEmailFlowStateKind of
        Pb.EmailFlowStateKindUnstarted _ ->
          H.div []
            [ H.text "Register an email address for notifications: "
            , Field.inputFor SetEmailField () model.emailField
                H.input
                [ HA.type_ "email"
                , HA.disabled <| (model.setEmailWorking==Working)
                , HA.placeholder "email@ddre.ss"
                , Utils.onEnter SetEmail Ignore
                ] []
            , H.button
                [ HE.onClick SetEmail
                , HA.disabled <| (model.setEmailWorking==Working) || Result.toMaybe (Field.parse () model.emailField) == Nothing
                ] [H.text "Send verification"]
            ]
        Pb.EmailFlowStateKindCodeSent {email} ->
          H.div []
            [ H.text "I sent a verification code to "
            , Utils.b email
            , H.text ". Enter it here: "
            , Field.inputFor SetCodeField () model.codeField
                H.input
                [ HA.disabled <| (model.setEmailWorking==Working)
                , HA.placeholder "code"
                , Utils.onEnter VerifyEmail Ignore
                ] []
            , H.button
                [ HE.onClick VerifyEmail
                , HA.disabled <| (model.setEmailWorking==Working) || Result.toMaybe (Field.parse () model.codeField) == Nothing
                ] [H.text "Verify code"]
              -- TODO: "Resend email"
            , H.text " (Or, "
            , H.button [HE.onClick DissociateEmail] [H.text "delete email"]
            , H.text ")"
            ]
        Pb.EmailFlowStateKindVerified email ->
          H.div []
            [ H.text "Your email address is: "
            , H.strong [] [H.text email]
            , H.text ". "
            , H.button [HE.onClick DissociateEmail] [H.text "delete?"]
            , H.br [] []
            ]
  in
    H.div []
      [ registrationBlock
      , case model.setEmailWorking of
          Awaiting {notification} -> notification |> H.map never
          _ -> H.text ""
      , H.div []
          [ H.input
              [ HA.type_ "checkbox", HA.checked model.userInfo.emailRemindersToResolve
              , HA.disabled (model.updateSettingsWorking==Working || not isRegistered)
              , HE.onInput (\_ -> SetEmailRemindersToResolve (not model.userInfo.emailRemindersToResolve))
              ] []
          , H.text " Email reminders to resolve your predictions, when it's time?"
          ]
      , H.div []
          [ H.input
              [ HA.type_ "checkbox", HA.checked model.userInfo.emailResolutionNotifications
              , HA.disabled (model.updateSettingsWorking==Working || not isRegistered)
              , HE.onInput (\_ -> SetEmailResolutionNotifications (not model.userInfo.emailResolutionNotifications))
              ] []
          , H.text " Email notifications when predictions you've bet on resolve?"
          ]
      ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main =
  Browser.element {init=init, view=view, update=update, subscriptions=subscriptions}
