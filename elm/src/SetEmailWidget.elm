module SetEmailWidget exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Protobuf.Encode as PE
import Protobuf.Decode as PD
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import Field exposing (Field)

type Model
  = NoEmailYet
      { emailField : Field () String
      , working : Bool
      , notification : Html Msg
      }
  | NeedsVerification
      { codeField : Field () String
      , working : Bool
      , notification : Html Msg
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

initNoEmailYet : Model
initNoEmailYet =
  NoEmailYet
    { emailField = Field.init "" <| \() s -> if String.contains "@" s then Ok s else Err "must be an email address"
    , working = False
    , notification = H.text ""
    }

initNeedsVerification : Model
initNeedsVerification =
  NeedsVerification
    { codeField = Field.init "" <| \() s -> if String.isEmpty s then Err "enter code" else Ok s
    , working = False
    , notification = H.text ""
    }

initVerified : String -> Model
initVerified email =
  Verified
    { email = email
    }

initFromFlowState : Pb.EmailFlowStateKind -> Model
initFromFlowState kind =
  case kind of
    Pb.EmailFlowStateKindUnstarted _ ->
      initNoEmailYet
    Pb.EmailFlowStateKindCodeSent _ ->
      initNeedsVerification
    Pb.EmailFlowStateKindVerified email ->
      initVerified email

init : JD.Value -> (Model, Cmd Msg)
init flags =
  ( initFromFlowState <| Maybe.withDefault (Pb.EmailFlowStateKindUnstarted Pb.Void) <| (Utils.mustDecodePbFromFlags Pb.emailFlowStateDecoder "emailFlowPbB64" flags).emailFlowStateKind
  , Cmd.none
  )

postSetEmail : Pb.SetEmailRequest -> Cmd Msg
postSetEmail req =
  Http.post
    { url = "/api/SetEmail"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toSetEmailRequestEncoder req
    , expect = PD.expectBytes SetEmailFinished Pb.setEmailResponseDecoder }

postVerifyEmail : Pb.VerifyEmailRequest -> Cmd Msg
postVerifyEmail req =
  Http.post
    { url = "/api/VerifyEmail"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toVerifyEmailRequestEncoder req
    , expect = PD.expectBytes VerifyEmailFinished Pb.verifyEmailResponseDecoder
    }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case (model, msg) of
    (NoEmailYet m, SetEmailField s) ->
      ( NoEmailYet { m | emailField = m.emailField |> Field.setStr s }
      , Cmd.none
      )
    (NoEmailYet m, SetEmail) ->
      ( NoEmailYet { m | working = True , notification = H.text "" }
      , case Field.parse () m.emailField of
          Ok email -> postSetEmail {email=email}
          _ -> Cmd.none
      )
    (NoEmailYet m, SetEmailFinished (Err e)) ->
      ( NoEmailYet { m | working = False , notification = Utils.redText (Debug.toString e) }
      , Cmd.none
      )
    (NoEmailYet m, SetEmailFinished (Ok resp)) ->
      case resp.setEmailResult of
        Just (Pb.SetEmailResultOk _) ->
          ( initNeedsVerification , Cmd.none )
        Just (Pb.SetEmailResultError e) ->
          ( NoEmailYet { m | working = False , notification = Utils.redText (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( NoEmailYet { m | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )

    (NeedsVerification m, SetCodeField s) ->
      ( NeedsVerification { m | codeField = m.codeField |> Field.setStr s }
      , Cmd.none
      )
    (NeedsVerification m, VerifyEmail) ->
      ( NeedsVerification { m | working = True , notification = H.text "" }
      , case Field.parse () m.codeField of
          Ok code -> postVerifyEmail {code=code}
          _ -> Cmd.none
      )
    (NeedsVerification m, VerifyEmailFinished (Err e)) ->
      ( NeedsVerification { m | working = False , notification = Utils.redText (Debug.toString e) }
      , Cmd.none
      )
    (NeedsVerification m, VerifyEmailFinished (Ok resp)) ->
      case resp.verifyEmailResult of
        Just (Pb.VerifyEmailResultVerifiedEmail email) ->
          ( initVerified email , Cmd.none )
        Just (Pb.VerifyEmailResultError e) ->
          ( NeedsVerification { m | working = False , notification = Utils.redText (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( NeedsVerification { m | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )

    _ -> ( model , Cmd.none )

view : Model -> Html Msg
view model =
  case model of
    NoEmailYet m ->
      H.div []
        [ H.text "Register an email address for notifications: "
        , Field.inputFor SetEmailField () m.emailField
            H.input
            [ HA.type_ "email"
            , HA.disabled <| m.working
            , HA.placeholder "email@ddre.ss"
            ] []
        , H.button
            [ HE.onClick SetEmail
            , HA.disabled <| m.working || Result.toMaybe (Field.parse () m.emailField) == Nothing
            ] [H.text "Send verification"]
        , m.notification
        ]
    NeedsVerification m ->
      H.div []
        [ H.text "Enter the code I sent to your email: "
        , Field.inputFor SetCodeField () m.codeField
            H.input
            [ HA.disabled <| m.working
            , HA.placeholder "code"
            ] []
        , H.button
            [ HE.onClick VerifyEmail
            , HA.disabled <| m.working || Result.toMaybe (Field.parse () m.codeField) == Nothing
            ] [H.text "Verify code"]
          -- TODO: "Resend email"
        , m.notification
        ]
    Verified m ->
      H.div []
        [ H.text "Your email address is: "
        , H.strong [] [H.text m.email]
        ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
