module Widgets.EmailSettingsWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http

import Biatob.Proto.Mvp as Pb
import Utils exposing (EmailAddress, Password)

import Field exposing (Field)
import Page
import Parser exposing ((|.), (|=))
import Set

type Msg
  = Ignore
  | SetEmailField EmailAddress
  | SetCodeField Password
  | SetEmailResolutionNotifications Bool
  | SetEmailRemindersToResolve Bool
  | UpdateSettingsFinished (Result Http.Error Pb.UpdateSettingsResponse)
  | DissociateEmail
  | SetEmail
  | SetEmailFinished (Result Http.Error Pb.SetEmailResponse)
  | VerifyEmail
  | VerifyEmailFinished (Result Http.Error Pb.VerifyEmailResponse)
type alias Model =
  { emailField : Field () EmailAddress
  , codeField : Field () Password
  , working : Bool
  , notification : Html Never
  }

init : Model
init =
  { emailField = Field.okIfEmpty <| Field.init "" <| \() s ->
      case Parser.run emailParser s of
        Ok _ -> Ok s
        Err _ -> Err "doesn't look valid, sorry"
  , codeField = Field.init "" <| \() s -> if String.isEmpty s then Err "enter code" else Ok s
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

update : Msg -> Model -> ( Model , Page.Command Msg )
update msg model =
  case msg of
    Ignore -> ( model , Page.NoCmd )
    SetEmailField s -> ( { model | emailField = model.emailField |> Field.setStr s } , Page.NoCmd )
    SetCodeField s -> ( { model | codeField = model.codeField |> Field.setStr s } , Page.NoCmd )
    SetEmailRemindersToResolve value ->
      ( { model | working = True , notification = H.text "" }
      , Page.RequestCmd <| Page.UpdateSettingsRequest UpdateSettingsFinished {emailRemindersToResolve=Just {value=value}, emailResolutionNotifications=Nothing}
      )
    SetEmailResolutionNotifications value ->
      ( { model | working = True , notification = H.text "" }
      , Page.RequestCmd <| Page.UpdateSettingsRequest UpdateSettingsFinished {emailRemindersToResolve=Nothing, emailResolutionNotifications=Just {value=value}}
      )
    UpdateSettingsFinished res ->
      ( case res of
        Err e ->
          { model | working = False , notification = Utils.redText (Debug.toString e) }
        Ok resp ->
          case resp.updateSettingsResult of
            Just (Pb.UpdateSettingsResultOk _) ->
              { model | working = False , notification = H.text "" }
            Just (Pb.UpdateSettingsResultError e) ->
              { model | working = False , notification = Utils.redText (Debug.toString e) }
            Nothing ->
              { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
      , Page.NoCmd
      )

    DissociateEmail ->
      ( { model | working = True , notification = H.text "" }
      , Page.RequestCmd <| Page.SetEmailRequest SetEmailFinished {email=""}
      )
    SetEmail ->
      case Field.parse () model.emailField of
        Err _ -> ( model , Page.NoCmd )
        Ok email ->
          ( { model | working = True , notification = H.text "" }
          , Page.RequestCmd <| Page.SetEmailRequest SetEmailFinished {email=email}
          )
    SetEmailFinished res ->
      ( case res of
        Err e ->
          { model | working = False , notification = Utils.redText (Debug.toString e) }
        Ok resp ->
          case resp.setEmailResult of
            Just (Pb.SetEmailResultOk _) ->
              { model | working = False , notification = H.text "" }
            Just (Pb.SetEmailResultError e) ->
              { model | working = False , notification = Utils.redText (Debug.toString e) }
            Nothing ->
              { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
      , Page.NoCmd
      )

    VerifyEmail ->
      case Field.parse () model.codeField of
        Err _ -> ( model , Page.NoCmd )
        Ok code ->
          ( { model | working = True , notification = H.text "" }
          , Page.RequestCmd <| Page.VerifyEmailRequest VerifyEmailFinished {code=code}
          )
    VerifyEmailFinished res ->
      ( case res of
        Err e ->
          { model | working = False , notification = Utils.redText (Debug.toString e) }
        Ok resp ->
          case resp.verifyEmailResult of
            Just (Pb.VerifyEmailResultOk _) ->
              { model | working = False , notification = H.text "" }
            Just (Pb.VerifyEmailResultError e) ->
              { model | working = False , notification = Utils.redText (Debug.toString e) }
            Nothing ->
              { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
      , Page.NoCmd
      )

view : Page.Globals -> Model -> Html Msg
view globals model =
  case Page.getUserInfo globals of
    Nothing -> H.text "(Log in to view your email settings!)"
    Just userInfo ->
      let
        emailFlowState : Pb.EmailFlowStateKind
        emailFlowState = userInfo |> Utils.mustUserInfoEmail |> Utils.mustEmailFlowStateKind

        isRegistered : Bool
        isRegistered = case emailFlowState of
          Pb.EmailFlowStateKindUnstarted _ -> False
          Pb.EmailFlowStateKindCodeSent _ -> False
          Pb.EmailFlowStateKindVerified _ -> True
        registrationBlock : Html Msg
        registrationBlock =
          case userInfo |> Utils.mustUserInfoEmail |> Utils.mustEmailFlowStateKind of
            Pb.EmailFlowStateKindUnstarted _ ->
              H.div []
                [ H.text "Register an email address for notifications: "
                , Field.inputFor SetEmailField () model.emailField
                    H.input
                    [ HA.type_ "email"
                    , HA.disabled <| model.working
                    , HA.placeholder "email@ddre.ss"
                    , Utils.onEnter SetEmail Ignore
                    ] []
                , H.button
                    [ HE.onClick SetEmail
                    , HA.disabled <| model.working || Result.toMaybe (Field.parse () model.emailField) == Nothing
                    ] [H.text "Send verification"]
                , model.notification |> H.map never
                ]
            Pb.EmailFlowStateKindCodeSent {email} ->
              H.div []
                [ H.text "I sent a verification code to "
                , Utils.b email
                , H.text ". Enter it here: "
                , Field.inputFor SetCodeField () model.codeField
                    H.input
                    [ HA.disabled <| model.working
                    , HA.placeholder "code"
                    , Utils.onEnter VerifyEmail Ignore
                    ] []
                , H.button
                    [ HE.onClick VerifyEmail
                    , HA.disabled <| model.working || Result.toMaybe (Field.parse () model.codeField) == Nothing
                    ] [H.text "Verify code"]
                  -- TODO: "Resend email"
                , model.notification |> H.map never
                , H.text " (Or, "
                , H.button [HE.onClick DissociateEmail] [H.text "delete email"]
                , H.text ")"
                ]
            Pb.EmailFlowStateKindVerified email ->
              H.div []
                [ H.text "Your email address is: "
                , Utils.b email
                , H.text ". "
                , H.button [HE.onClick DissociateEmail] [H.text "delete?"]
                , H.br [] []
                , model.notification |> H.map never
                ]
      in
        H.div []
          [ registrationBlock
          , H.div []
              [ H.input
                  [ HA.type_ "checkbox", HA.checked userInfo.emailRemindersToResolve
                  , HA.disabled (model.working || not isRegistered)
                  , HE.onInput (\_ -> SetEmailRemindersToResolve (not userInfo.emailRemindersToResolve))
                  ] []
              , H.text " Email reminders to resolve your predictions, when it's time?"
              ]
          , H.div []
              [ H.input
                  [ HA.type_ "checkbox", HA.checked userInfo.emailResolutionNotifications
                  , HA.disabled (model.working || not isRegistered)
                  , HE.onInput (\_ -> SetEmailResolutionNotifications (not userInfo.emailResolutionNotifications))
                  ] []
              , H.text " Email notifications when predictions you've bet on resolve?"
              ]
          ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
