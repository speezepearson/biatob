module API exposing (..)

import Protobuf.Decode as PD
import Protobuf.Encode as PE
import Biatob.Proto.Mvp as Pb
import Http
import Utils exposing (PredictionId)

type alias Endpoint req resp =
  { encoder : (req -> PE.Encoder)
  , decoder : PD.Decoder resp
  , url : String
  }

{-| A failed call to an endpoint that reports failure via HTTP status.

`ApiError` is a failure the server *chose* to report: a non-2xx carrying an
ErrorResponse that explains itself. `TransportError` is everything else -- the
request never reached a considered answer, so there's nobody to quote.
-}
type Error
  = ApiError { status : Int, catchall : String }
  | TransportError Http.Error

errorToString : Error -> String
errorToString e =
  case e of
    ApiError {catchall} -> catchall
    TransportError httpError -> httpErrorToString httpError

{-| Make an API call. The 200 body is the payload itself; failures arrive as a
non-2xx carrying an ErrorResponse.

This can't use `PD.expectBytes`. On a non-2xx, elm/http's `expectBytes`
discards the body and hands back only `BadStatus statusCode` -- see the
`BadStatus_ metadata _ -> Err (BadStatus metadata.statusCode)` branch in
Http.elm. The body is exactly where the server explains itself, so we go
through `expectBytesResponse` and handle that branch ourselves.
-}
call : Endpoint req resp -> (Result Error resp -> msg) -> req -> Cmd msg
call endpoint toMsg req =
  Http.post
    { url = endpoint.url
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| endpoint.encoder req
    , expect = expectProtoOrError endpoint.decoder toMsg
    }

expectProtoOrError : PD.Decoder resp -> (Result Error resp -> msg) -> Http.Expect msg
expectProtoOrError decoder toMsg =
  Http.expectBytesResponse toMsg <| \response ->
    case response of
      Http.BadUrl_ url -> Err (TransportError (Http.BadUrl url))
      Http.Timeout_ -> Err (TransportError Http.Timeout)
      Http.NetworkError_ -> Err (TransportError Http.NetworkError)
      Http.BadStatus_ metadata body ->
        case PD.decode Pb.errorResponseDecoder body of
          Just err -> Err (ApiError {status = metadata.statusCode, catchall = err.catchall})
          -- A non-2xx that isn't one of ours (a proxy's 502 page, say).
          Nothing -> Err (TransportError (Http.BadStatus metadata.statusCode))
      Http.GoodStatus_ _ body ->
        case PD.decode decoder body of
          Just value -> Ok value
          Nothing -> Err (TransportError (Http.BadBody "unintelligible response"))

postWhoami : (Result Error Pb.WhoamiResponse -> msg) -> Pb.WhoamiRequest -> Cmd msg
postWhoami = call {url="/api/Whoami", encoder=Pb.toWhoamiRequestEncoder, decoder=Pb.whoamiResponseDecoder}
postSignOut : (Result Error Pb.SignOutResponse -> msg) -> Pb.SignOutRequest -> Cmd msg
postSignOut = call {url="/api/SignOut", encoder=Pb.toSignOutRequestEncoder, decoder=Pb.signOutResponseDecoder}
postSendVerificationEmail : (Result Error Pb.Empty -> msg) -> Pb.SendVerificationEmailRequest -> Cmd msg
postSendVerificationEmail = call {url="/api/SendVerificationEmail", encoder=Pb.toSendVerificationEmailRequestEncoder, decoder=Pb.emptyDecoder}
postRegisterUsername : (Result Error Pb.AuthSuccess -> msg) -> Pb.RegisterUsernameRequest -> Cmd msg
postRegisterUsername = call {url="/api/RegisterUsername", encoder=Pb.toRegisterUsernameRequestEncoder, decoder=Pb.authSuccessDecoder}
postLogInUsername : (Result Error Pb.AuthSuccess -> msg) -> Pb.LogInUsernameRequest -> Cmd msg
postLogInUsername = call {url="/api/LogInUsername", encoder=Pb.toLogInUsernameRequestEncoder, decoder=Pb.authSuccessDecoder}
postCreatePrediction : (Result Error Pb.CreatePredictionResponse -> msg) -> Pb.CreatePredictionRequest -> Cmd msg
postCreatePrediction = call {url="/api/CreatePrediction", encoder=Pb.toCreatePredictionRequestEncoder, decoder=Pb.createPredictionResponseDecoder}
postGetPrediction : (Result Error Pb.UserPredictionView -> msg) -> Pb.GetPredictionRequest -> Cmd msg
postGetPrediction = call {url="/api/GetPrediction", encoder=Pb.toGetPredictionRequestEncoder, decoder=Pb.userPredictionViewDecoder}
postListMyStakes : (Result Error Pb.PredictionsById -> msg) -> Pb.ListMyStakesRequest -> Cmd msg
postListMyStakes = call {url="/api/ListMyStakes", encoder=Pb.toListMyStakesRequestEncoder, decoder=Pb.predictionsByIdDecoder}
postListPredictions : (Result Error Pb.PredictionsById -> msg) -> Pb.ListPredictionsRequest -> Cmd msg
postListPredictions = call {url="/api/ListPredictions", encoder=Pb.toListPredictionsRequestEncoder, decoder=Pb.predictionsByIdDecoder}
postStake : (Result Error Pb.UserPredictionView -> msg) -> Pb.StakeRequest -> Cmd msg
postStake = call {url="/api/Stake", encoder=Pb.toStakeRequestEncoder, decoder=Pb.userPredictionViewDecoder}
postFollow : (Result Error Pb.UserPredictionView -> msg) -> Pb.FollowRequest -> Cmd msg
postFollow = call {url="/api/Follow", encoder=Pb.toFollowRequestEncoder, decoder=Pb.userPredictionViewDecoder}
postResolve : (Result Error Pb.UserPredictionView -> msg) -> Pb.ResolveRequest -> Cmd msg
postResolve = call {url="/api/Resolve", encoder=Pb.toResolveRequestEncoder, decoder=Pb.userPredictionViewDecoder}
postSetTrusted : (Result Error Pb.GenericUserInfo -> msg) -> Pb.SetTrustedRequest -> Cmd msg
postSetTrusted = call {url="/api/SetTrusted", encoder=Pb.toSetTrustedRequestEncoder, decoder=Pb.genericUserInfoDecoder}
postGetUser : (Result Error Pb.Relationship -> msg) -> Pb.GetUserRequest -> Cmd msg
postGetUser = call {url="/api/GetUser", encoder=Pb.toGetUserRequestEncoder, decoder=Pb.relationshipDecoder}
postChangePassword : (Result Error Pb.Empty -> msg) -> Pb.ChangePasswordRequest -> Cmd msg
postChangePassword = call {url="/api/ChangePassword", encoder=Pb.toChangePasswordRequestEncoder, decoder=Pb.emptyDecoder}
postGetSettings : (Result Error Pb.GenericUserInfo -> msg) -> Pb.GetSettingsRequest -> Cmd msg
postGetSettings = call {url="/api/GetSettings", encoder=Pb.toGetSettingsRequestEncoder, decoder=Pb.genericUserInfoDecoder}
postSendInvitation : (Result Error Pb.GenericUserInfo -> msg) -> Pb.SendInvitationRequest -> Cmd msg
postSendInvitation = call {url="/api/SendInvitation", encoder=Pb.toSendInvitationRequestEncoder, decoder=Pb.genericUserInfoDecoder}
postAcceptInvitation : (Result Error Pb.GenericUserInfo -> msg) -> Pb.AcceptInvitationRequest -> Cmd msg
postAcceptInvitation = call {url="/api/AcceptInvitation", encoder=Pb.toAcceptInvitationRequestEncoder, decoder=Pb.genericUserInfoDecoder}

httpErrorToString : Http.Error -> String
httpErrorToString e =
  case e of
    Http.BadUrl _ -> "unintelligible URL"
    Http.Timeout -> "timed out"
    Http.NetworkError -> "network error"
    Http.BadStatus code -> "HTTP error code " ++ String.fromInt code
    Http.BadBody _ -> "unintelligible response"

{-| Adapters kept so call sites keep their `Result String payload` shape.

Every one of these used to be a twelve-line `case` unwrapping a `oneof`, with a
dead third arm for "neither Ok nor Error" -- a state the protobuf forced us to
have an opinion about, and which HTTP simply cannot express. Now that failure
is carried by the status code, they're all one-liners, and the impossible arm
is gone from all of them.
-}
simplifyLogInUsernameResponse : Result Error Pb.AuthSuccess -> Result String Pb.AuthSuccess
simplifyLogInUsernameResponse = Result.mapError errorToString

simplifySendVerificationEmailResponse : Result Error Pb.Empty -> Result String Pb.Empty
simplifySendVerificationEmailResponse = Result.mapError errorToString

simplifyRegisterUsernameResponse : Result Error Pb.AuthSuccess -> Result String Pb.AuthSuccess
simplifyRegisterUsernameResponse = Result.mapError errorToString

simplifySignOutResponse : Result Error Pb.SignOutResponse -> Result String ()
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
