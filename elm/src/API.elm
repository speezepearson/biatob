module API exposing (..)

import Json.Decode as JD
import Json.Encode as JE
import Api.Types as Pb
import Api.Json
import Http
import Utils exposing (PredictionId)

type alias Endpoint req resp =
  { encoder : (req -> JE.Value)
  , decoder : JD.Decoder resp
  , url : String
  }

{-| A failed call. `ApiError` is a failure the server chose to report -- a
non-2xx carrying an ErrorResponse that explains itself. `TransportError` is
everything else: the request never reached a considered answer.
-}
type Error
  = ApiError { status : Int, catchall : String }
  | TransportError Http.Error

errorToString : Error -> String
errorToString e =
  case e of
    ApiError {catchall} -> catchall
    TransportError httpError -> httpErrorToString httpError

httpErrorToString : Http.Error -> String
httpErrorToString e =
  case e of
    Http.BadUrl _ -> "unintelligible URL"
    Http.Timeout -> "timed out"
    Http.NetworkError -> "network error"
    Http.BadStatus code -> "HTTP error code " ++ String.fromInt code
    Http.BadBody _ -> "unintelligible response"

call : Endpoint req resp -> (Result Error resp -> msg) -> req -> Cmd msg
call endpoint toMsg req =
  Http.post
    { url = endpoint.url
    , body = Http.jsonBody (endpoint.encoder req)
    , expect = expectJsonOrError endpoint.decoder toMsg
    }

expectJsonOrError : JD.Decoder resp -> (Result Error resp -> msg) -> Http.Expect msg
expectJsonOrError decoder toMsg =
  Http.expectStringResponse toMsg <| \response ->
    case response of
      Http.BadUrl_ url -> Err (TransportError (Http.BadUrl url))
      Http.Timeout_ -> Err (TransportError Http.Timeout)
      Http.NetworkError_ -> Err (TransportError Http.NetworkError)
      Http.BadStatus_ metadata body ->
        case JD.decodeString (JD.field "catchall" JD.string) body of
          Ok catchall -> Err (ApiError {status = metadata.statusCode, catchall = catchall})
          Err _ -> Err (TransportError (Http.BadStatus metadata.statusCode))
      Http.GoodStatus_ _ body ->
        case JD.decodeString decoder body of
          Ok value -> Ok value
          Err _ -> Err (TransportError (Http.BadBody "unintelligible response"))

postLogInUsername : (Result Error Pb.AuthSuccess -> msg) -> Pb.LogInUsernameRequest -> Cmd msg
postLogInUsername = call {url="/api/LogInUsername", encoder=Api.Json.encodeLogInUsernameRequest, decoder=Api.Json.decodeAuthSuccess}
postSignOut : (Result Error Pb.Empty -> msg) -> Pb.SignOutRequest -> Cmd msg
postSignOut = call {url="/api/SignOut", encoder=Api.Json.encodeSignOutRequest, decoder=Api.Json.decodeEmpty}
postSendVerificationEmail : (Result Error Pb.Empty -> msg) -> Pb.SendVerificationEmailRequest -> Cmd msg
postSendVerificationEmail = call {url="/api/SendVerificationEmail", encoder=Api.Json.encodeSendVerificationEmailRequest, decoder=Api.Json.decodeEmpty}
postRegisterUsername : (Result Error Pb.AuthSuccess -> msg) -> Pb.RegisterUsernameRequest -> Cmd msg
postRegisterUsername = call {url="/api/RegisterUsername", encoder=Api.Json.encodeRegisterUsernameRequest, decoder=Api.Json.decodeAuthSuccess}
postCreatePrediction : (Result Error Pb.CreatePredictionResponse -> msg) -> Pb.CreatePredictionRequest -> Cmd msg
postCreatePrediction = call {url="/api/CreatePrediction", encoder=Api.Json.encodeCreatePredictionRequest, decoder=Api.Json.decodeCreatePredictionResponse}
postStake : (Result Error Pb.UserPredictionView -> msg) -> Pb.StakeRequest -> Cmd msg
postStake = call {url="/api/Stake", encoder=Api.Json.encodeStakeRequest, decoder=Api.Json.decodeUserPredictionView}
postFollow : (Result Error Pb.UserPredictionView -> msg) -> Pb.FollowRequest -> Cmd msg
postFollow = call {url="/api/Follow", encoder=Api.Json.encodeFollowRequest, decoder=Api.Json.decodeUserPredictionView}
postResolve : (Result Error Pb.UserPredictionView -> msg) -> Pb.ResolveRequest -> Cmd msg
postResolve = call {url="/api/Resolve", encoder=Api.Json.encodeResolveRequest, decoder=Api.Json.decodeUserPredictionView}
postSetTrusted : (Result Error Pb.GenericUserInfo -> msg) -> Pb.SetTrustedRequest -> Cmd msg
postSetTrusted = call {url="/api/SetTrusted", encoder=Api.Json.encodeSetTrustedRequest, decoder=Api.Json.decodeGenericUserInfo}
postSendInvitation : (Result Error Pb.GenericUserInfo -> msg) -> Pb.SendInvitationRequest -> Cmd msg
postSendInvitation = call {url="/api/SendInvitation", encoder=Api.Json.encodeSendInvitationRequest, decoder=Api.Json.decodeGenericUserInfo}
postAcceptInvitation : (Result Error Pb.GenericUserInfo -> msg) -> Pb.AcceptInvitationRequest -> Cmd msg
postAcceptInvitation = call {url="/api/AcceptInvitation", encoder=Api.Json.encodeAcceptInvitationRequest, decoder=Api.Json.decodeGenericUserInfo}
postChangePassword : (Result Error Pb.Empty -> msg) -> Pb.ChangePasswordRequest -> Cmd msg
postChangePassword = call {url="/api/ChangePassword", encoder=Api.Json.encodeChangePasswordRequest, decoder=Api.Json.decodeEmpty}


{-| Adapters that flatten an `API.Error` down to its user-facing string, so call
sites can work in terms of `Result String payload`.
-}
simplifyLogInUsernameResponse : Result Error Pb.AuthSuccess -> Result String Pb.AuthSuccess
simplifyLogInUsernameResponse = Result.mapError errorToString

simplifySendVerificationEmailResponse : Result Error Pb.Empty -> Result String Pb.Empty
simplifySendVerificationEmailResponse = Result.mapError errorToString

simplifyRegisterUsernameResponse : Result Error Pb.AuthSuccess -> Result String Pb.AuthSuccess
simplifyRegisterUsernameResponse = Result.mapError errorToString

simplifySignOutResponse : Result Error Pb.Empty -> Result String ()
simplifySignOutResponse = Result.mapError errorToString >> Result.map (always ())

simplifySendInvitationResponse : Result Error Pb.GenericUserInfo -> Result String ()
simplifySendInvitationResponse = Result.mapError errorToString >> Result.map (always ())

simplifyAcceptInvitationResponse : Result Error Pb.GenericUserInfo -> Result String Pb.GenericUserInfo
simplifyAcceptInvitationResponse = Result.mapError errorToString

simplifyCreatePredictionResponse : Result Error Pb.CreatePredictionResponse -> Result String PredictionId
simplifyCreatePredictionResponse = Result.mapError errorToString >> Result.map .newPredictionId

simplifyStakeResponse : Result Error Pb.UserPredictionView -> Result String Pb.UserPredictionView
simplifyStakeResponse = Result.mapError errorToString

simplifyFollowResponse : Result Error Pb.UserPredictionView -> Result String Pb.UserPredictionView
simplifyFollowResponse = Result.mapError errorToString

simplifyResolveResponse : Result Error Pb.UserPredictionView -> Result String Pb.UserPredictionView
simplifyResolveResponse = Result.mapError errorToString

simplifyChangePasswordResponse : Result Error Pb.Empty -> Result String Pb.Empty
simplifyChangePasswordResponse = Result.mapError errorToString

simplifySetTrustedResponse : Result Error Pb.GenericUserInfo -> Result String Pb.GenericUserInfo
simplifySetTrustedResponse = Result.mapError errorToString
