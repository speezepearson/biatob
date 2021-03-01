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
import Page
import Field

type Msg
  = Ignore
  | SetEmailField String
  | SetCodeField String
  | SetEmailResolutionNotifications Bool
  | SetEmailRemindersToResolve Bool
  | UpdateSettingsFinished (Result Http.Error Pb.UpdateSettingsResponse)
  | SetEmail
  | SetEmailFinished (Result Http.Error Pb.SetEmailResponse)
  | VerifyEmail
  | VerifyEmailFinished (Result Http.Error Pb.VerifyEmailResponse)
type alias Model =
  { emailField : Field () String
  , codeField : Field () String
  , working : Bool
  , notification : Html Never
  }

init : Model
init =
  { emailField = Field.okIfEmpty <| Field.init "" <| \() s -> if String.contains "@" s then Ok s else Err "must be an email address"
  , codeField = Field.init "" <| \() s -> if String.isEmpty s then Err "enter code" else Ok s
  , working = False
  , notification = H.text ""
  }

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
            ]
        Pb.EmailFlowStateKindVerified email ->
          H.div []
            [ H.text "Your email address is: "
            , H.strong [] [H.text email]
            , H.div []
                [ H.input
                    [ HA.type_ "checkbox", HA.checked userInfo.emailRemindersToResolve
                    , HA.disabled model.working
                    , HE.onInput (\_ -> SetEmailRemindersToResolve (not userInfo.emailRemindersToResolve))
                    ] []
                , H.text " Email reminders to resolve your predictions, when it's time?"
                ]
            , H.div []
                [ H.input
                    [ HA.type_ "checkbox", HA.checked userInfo.emailResolutionNotifications
                    , HA.disabled model.working
                    , HE.onInput (\_ -> SetEmailResolutionNotifications (not userInfo.emailResolutionNotifications))
                    ] []
                , H.text " Email notifications when predictions you've bet on resolve?"
                ]
            , H.br [] []
            , model.notification |> H.map never
            ]
