port module AuthWidget exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as JD
import Json.Encode as JE
import Time
import Html exposing (s)

import Protobuf.Decode as PD
import Protobuf.Encode as PE
import Biatob.Proto.Mvp as Pb
import Utils
import Http

port authChanged : () -> Cmd msg

type Model
  = NoToken
      { usernameField : String
      , passwordField : String
      , working : Bool
      , error : Maybe String
      }
  | HasToken
      { token : Pb.AuthToken
      , working : Bool
      , error : Maybe String
      }

type Msg
  = SetUsernameField String
  | SetPasswordField String
  | LogInUsername
  | LogInUsernameComplete (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername
  | RegisterUsernameComplete (Result Http.Error Pb.RegisterUsernameResponse)
  | Tick Time.Posix
  | SignOut
  | SignOutComplete (Result Http.Error Pb.SignOutResponse)

initNoToken : Model
initNoToken =
  NoToken
    { usernameField = ""
    , passwordField = ""
    , working = False
    , error = Nothing
    }

initHasToken : Pb.AuthToken -> Model
initHasToken token =
  HasToken
    { token = token
    , working = False
    , error = Nothing
    }

init : JD.Value -> ( Model , Cmd Msg )
init flags =
  ( case flags |> JD.decodeValue (JD.field "authTokenPbB64" JD.string) |> Result.toMaybe |> Maybe.andThen (Utils.decodePbB64 Pb.authTokenDecoder) of
      Just token -> initHasToken token
      Nothing -> initNoToken
  , Cmd.none
  )

view : Model -> Html Msg
view model =
  case model of
    NoToken m ->
      H.div []
        [ H.input [HA.disabled m.working, HA.style "width" "8em", HA.type_ "username", HA.placeholder "username", HA.value m.usernameField, HE.onInput SetUsernameField] []
        , H.input [HA.disabled m.working, HA.style "width" "8em", HA.type_ "password", HA.placeholder "password", HA.value m.passwordField, HE.onInput SetPasswordField] []
        , H.button [HA.disabled m.working, HE.onClick LogInUsername] [H.text "Log in"]
        , H.text " or "
        , H.button [HA.disabled m.working, HE.onClick RegisterUsername] [H.text "Sign up"]
        , case m.error of
            Just e -> H.div [HA.style "color" "red"] [H.text e]
            Nothing -> H.text ""
        ]
    HasToken m ->
      H.div []
        [ H.text <| "Signed in as " ++ Debug.toString m.token.owner ++ "; "
        , H.button [HA.disabled m.working, HE.onClick SignOut] [H.text "Sign out"]
        , case m.error of
            Just e -> H.div [HA.style "color" "red"] [H.text e]
            Nothing -> H.text ""
        ]

postLogInUsername : Pb.LogInUsernameRequest -> Cmd Msg
postLogInUsername req =
  Http.post
    { url = "/api/log_in_username"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toLogInUsernameRequestEncoder req
    , expect = PD.expectBytes LogInUsernameComplete Pb.logInUsernameResponseDecoder
    }

postRegisterUsername : Pb.RegisterUsernameRequest -> Cmd Msg
postRegisterUsername req =
  Http.post
    { url = "/api/register_username"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toRegisterUsernameRequestEncoder req
    , expect = PD.expectBytes RegisterUsernameComplete Pb.registerUsernameResponseDecoder
    }

postSignOut : Cmd Msg
postSignOut =
  Http.post
    { url = "/api/sign_out"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toSignOutRequestEncoder {}
    , expect = PD.expectBytes SignOutComplete Pb.signOutResponseDecoder
    }

update : Msg -> Model -> ( Model , Cmd Msg )
update msg model =
  case (msg, model) of
  (SetUsernameField s, NoToken m) ->
    ( NoToken { m | usernameField = s } , Cmd.none )
  (SetPasswordField s, NoToken m) ->
    ( NoToken { m | passwordField = s } , Cmd.none )
  (LogInUsername, NoToken m) ->
    ( NoToken { m | working = True }
    , postLogInUsername {username=m.usernameField, password=m.passwordField}
    )
  (LogInUsernameComplete (Err e), NoToken m) ->
    ( NoToken { m | working = False , error = Just (Debug.toString e) }
    , Cmd.none
    )
  (LogInUsernameComplete (Ok resp), NoToken m) ->
    case resp.logInUsernameResult of
      Just (Pb.LogInUsernameResultOk token) ->
        ( initHasToken token
        , authChanged ()
        )
      Just (Pb.LogInUsernameResultError e) ->
        ( NoToken { m | working = False , error = Just (Debug.toString e) }
        , Cmd.none
        )
      Nothing ->
        ( NoToken { m | working = False , error = Just "Invalid server response (neither Ok nor Error in protobuf)" }
        , Cmd.none
        )
  (RegisterUsername, NoToken m) ->
    ( NoToken { m | working = True }
    , postRegisterUsername {username=m.usernameField, password=m.passwordField}
    )
  (RegisterUsernameComplete (Err e), NoToken m) ->
    ( NoToken { m | working = False , error = Just (Debug.toString e) }
    , Cmd.none )
  (RegisterUsernameComplete (Ok resp), NoToken m) ->
    case resp.registerUsernameResult of
      Just (Pb.RegisterUsernameResultOk token) ->
        ( initHasToken token
        , authChanged ()
        )
      Just (Pb.RegisterUsernameResultError e) ->
        ( NoToken { m | working = False , error = Just (Debug.toString e) }
        , Cmd.none
        )
      Nothing ->
        ( NoToken { m | working = False , error = Just "Invalid server response (neither Ok nor Error in protobuf)" }
        , Cmd.none
        )
  (Tick _, NoToken _) ->
    ( model , Cmd.none )
  (SignOut, NoToken _) ->
    ( model , Cmd.none )
  (SignOutComplete _, NoToken _) ->
    ( model , Cmd.none )

  (SetUsernameField _, HasToken _) ->
    ( model , Cmd.none )
  (SetPasswordField _, HasToken _) ->
    ( model , Cmd.none )
  (LogInUsername, HasToken _) ->
    ( model , Cmd.none )
  (LogInUsernameComplete _, HasToken _) ->
    ( model , Cmd.none )
  (RegisterUsername, HasToken _) ->
    ( model , Cmd.none )
  (RegisterUsernameComplete _, HasToken _) ->
    ( model , Cmd.none )
  (Tick now, HasToken {token}) ->
    if Time.posixToMillis now > 1000*token.expiresUnixtime then
      ( init JE.null |> Tuple.first
      , authChanged ()
      )
    else
      ( model , Cmd.none )
  (SignOut, HasToken m) ->
    ( HasToken { m | working = True , error = Nothing }
    , postSignOut
    )
  (SignOutComplete _, HasToken _) ->
    ( initNoToken , authChanged () )

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , view = view
    , update = update
    , subscriptions = always (Time.every 1000 Tick)
    }
