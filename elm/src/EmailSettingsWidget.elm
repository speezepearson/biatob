module EmailSettingsWidget exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http

import Biatob.Proto.Mvp as Pb
import Utils

import Field exposing (Field)
import API

type alias Model =
  { registration : Registration
  , emailRemindersToResolve : Bool
  , emailResolutionNotifications : Bool
  , working : Bool
  , notification : Html Msg
  }
type Registration
  = NoEmailYet
      { emailField : Field () String
      }
  | NeedsVerification
      { codeField : Field () String
      }
  | Verified
      { email : String
      }

type Msg
  = SetEmailField String
  | SetEmail
  | SetEmailFinished (Result Http.Error Pb.SetEmailResponse)
  | SetCodeField String
  | VerifyEmail
  | VerifyEmailFinished (Result Http.Error Pb.VerifyEmailResponse)
  | ToggleEmailRemindersToResolve
  | ToggleEmailResolutionNotifications
  | UpdateSettingsFinished (Result Http.Error Pb.UpdateSettingsResponse)

initNoEmailYet : Registration
initNoEmailYet =
  NoEmailYet
    { emailField = Field.init "" <| \() s -> if String.contains "@" s then Ok s else Err "must be an email address"
    }

initNeedsVerification : Registration
initNeedsVerification =
  NeedsVerification
    { codeField = Field.init "" <| \() s -> if String.isEmpty s then Err "enter code" else Ok s
    }

initVerified : String -> Registration
initVerified email =
  Verified
    { email = email
    }

initFromUserInfo : Pb.GenericUserInfo -> ( Model , Cmd Msg )
initFromUserInfo info =
  ( { registration =
        case info.email
              |> Maybe.andThen .emailFlowStateKind
              |> Maybe.withDefault (Pb.EmailFlowStateKindUnstarted Pb.Void)
              of
          Pb.EmailFlowStateKindUnstarted _ ->
            initNoEmailYet
          Pb.EmailFlowStateKindCodeSent _ ->
            initNeedsVerification
          Pb.EmailFlowStateKindVerified email ->
            initVerified email
    , emailRemindersToResolve = info.emailRemindersToResolve
    , emailResolutionNotifications = info.emailResolutionNotifications
    , working = False
    , notification = H.text ""
    }
  , Cmd.none
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    ToggleEmailRemindersToResolve ->
      ( { model | working = True , notification = H.text "" }
      , API.postUpdateSettings UpdateSettingsFinished
          { emailRemindersToResolve = Just <| Pb.MaybeBool <| not <| model.emailRemindersToResolve
          , emailResolutionNotifications = Nothing
          }
      )
    ToggleEmailResolutionNotifications ->
      ( { model | working = True , notification = H.text "" }
      , API.postUpdateSettings UpdateSettingsFinished
          { emailRemindersToResolve = Nothing
          , emailResolutionNotifications = Just <| Pb.MaybeBool <| not <| model.emailResolutionNotifications
          }
      )

    UpdateSettingsFinished (Err e) ->
      case model.registration of
        NoEmailYet m ->
          ( { model | working = False , notification = Utils.redText (Debug.toString e) }
          , Cmd.none
          )
        _ -> ( model , Cmd.none )

    UpdateSettingsFinished (Ok resp) ->
      case resp.updateSettingsResult of
        Just (Pb.UpdateSettingsResultOk newUserInfo) ->
          initFromUserInfo newUserInfo
        Just (Pb.UpdateSettingsResultError e) ->
          ( { model | working = False , notification = Utils.redText (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )

    SetEmailField s ->
      case model.registration of
        NoEmailYet m ->
          ( { model | registration = NoEmailYet { m | emailField = m.emailField |> Field.setStr s } }
          , Cmd.none
          )
        _ -> ( model , Cmd.none )

    SetEmail ->
      case model.registration of
        NoEmailYet m ->
          case Field.parse () m.emailField of
            Ok email ->
              ( { model | working = True , notification = H.text "" }
              , API.postSetEmail SetEmailFinished {email=email}
              )
            Err e -> ( model , Cmd.none )
        _ -> ( model , Cmd.none )

    SetEmailFinished (Err e) ->
      case model.registration of
        NoEmailYet m ->
          ( { model | working = False , notification = Utils.redText (Debug.toString e) }
          , Cmd.none
          )
        _ -> ( model , Cmd.none )

    SetEmailFinished (Ok resp) ->
      case model.registration of
        NoEmailYet m ->
          case resp.setEmailResult of
            Just (Pb.SetEmailResultOk _) ->
              ( { model | working = False , notification = H.text "" , registration = initNeedsVerification } , Cmd.none )
            Just (Pb.SetEmailResultError e) ->
              ( { model | working = False , notification = Utils.redText (Debug.toString e) }
              , Cmd.none
              )
            Nothing ->
              ( { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
              , Cmd.none
              )
        _ -> ( model , Cmd.none )

    SetCodeField s ->
      case model.registration of
        NeedsVerification m ->
          ( { model | registration = NeedsVerification { m | codeField = m.codeField |> Field.setStr s } }
          , Cmd.none
          )
        _ -> ( model , Cmd.none )
    VerifyEmail ->
      case model.registration of
        NeedsVerification m ->
          case Field.parse () m.codeField of
            Ok code ->
              ( { model | working = True , notification = H.text "" }
              , API.postVerifyEmail VerifyEmailFinished {code=code}
              )
            Err e -> Debug.todo e
        _ -> ( model , Cmd.none )
    VerifyEmailFinished (Err e) ->
      case model.registration of
        NeedsVerification m ->
          ( { model | working = False , notification = Utils.redText (Debug.toString e) }
          , Cmd.none
          )
        _ -> ( model , Cmd.none )
    VerifyEmailFinished (Ok resp) ->
      case model.registration of
        NeedsVerification m ->
          case resp.verifyEmailResult of
            Just (Pb.VerifyEmailResultVerifiedEmail email) ->
              ( { model | working = False , notification = H.text "" , registration = initVerified email } , Cmd.none )
            Just (Pb.VerifyEmailResultError e) ->
              ( { model | working = False , notification = Utils.redText (Debug.toString e) }
              , Cmd.none
              )
            Nothing ->
              ( { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
              , Cmd.none
              )
        _ -> ( model , Cmd.none )

view : Model -> Html Msg
view model =
  case model.registration of
    NoEmailYet m ->
      H.div []
        [ H.text "Register an email address for notifications: "
        , Field.inputFor SetEmailField () m.emailField
            H.input
            [ HA.type_ "email"
            , HA.disabled <| model.working
            , HA.placeholder "email@ddre.ss"
            ] []
        , H.button
            [ HE.onClick SetEmail
            , HA.disabled <| model.working || Result.toMaybe (Field.parse () m.emailField) == Nothing
            ] [H.text "Send verification"]
        , model.notification
        ]
    NeedsVerification m ->
      H.div []
        [ H.text "Enter the code I sent to your email: "
        , Field.inputFor SetCodeField () m.codeField
            H.input
            [ HA.disabled <| model.working
            , HA.placeholder "code"
            ] []
        , H.button
            [ HE.onClick VerifyEmail
            , HA.disabled <| model.working || Result.toMaybe (Field.parse () m.codeField) == Nothing
            ] [H.text "Verify code"]
          -- TODO: "Resend email"
        , model.notification
        ]
    Verified m ->
      H.div []
        [ H.text "Your email address is: "
        , H.strong [] [H.text m.email]
        , H.div []
            [ H.input
                [ HA.type_ "checkbox", HA.checked model.emailRemindersToResolve
                , HA.disabled model.working
                , HE.onInput (always ToggleEmailRemindersToResolve)
                ] []
            , H.text " Email reminders to resolve your predictions, when it's time?"
            ]
        , H.div []
            [ H.input
                [ HA.type_ "checkbox", HA.checked model.emailResolutionNotifications
                , HA.disabled model.working
                , HE.onInput (always ToggleEmailResolutionNotifications)
                ] []
            , H.text " Email notifications when predictions you've bet on resolve?"
            ]
        , H.br [] []
        , model.notification
        ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
