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

{-| For endpoints still using the `oneof foo_result {Ok ok; Error error;}`
pattern, where every answer is a 200 and you inspect the body to find out
whether it worked.
-}
hit : Endpoint req resp -> (Result Http.Error resp -> msg) -> req -> Cmd msg
hit endpoint toMsg req =
  Http.post
    { url = endpoint.url
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| endpoint.encoder req
    , expect = PD.expectBytes toMsg endpoint.decoder
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

{-| Like `hit`, but for endpoints migrated to HTTP-status error propagation:
the 200 body is the payload itself, and failures arrive as a non-2xx with an
ErrorResponse body.

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

postWhoami : (Result Http.Error Pb.WhoamiResponse -> msg) -> Pb.WhoamiRequest -> Cmd msg
postWhoami = hit {url="/api/Whoami", encoder=Pb.toWhoamiRequestEncoder, decoder=Pb.whoamiResponseDecoder}
postSignOut : (Result Http.Error Pb.SignOutResponse -> msg) -> Pb.SignOutRequest -> Cmd msg
postSignOut = hit {url="/api/SignOut", encoder=Pb.toSignOutRequestEncoder, decoder=Pb.signOutResponseDecoder}
postSendVerificationEmail : (Result Http.Error Pb.SendVerificationEmailResponse -> msg) -> Pb.SendVerificationEmailRequest -> Cmd msg
postSendVerificationEmail = hit {url="/api/SendVerificationEmail", encoder=Pb.toSendVerificationEmailRequestEncoder, decoder=Pb.sendVerificationEmailResponseDecoder}
postRegisterUsername : (Result Http.Error Pb.RegisterUsernameResponse -> msg) -> Pb.RegisterUsernameRequest -> Cmd msg
postRegisterUsername = hit {url="/api/RegisterUsername", encoder=Pb.toRegisterUsernameRequestEncoder, decoder=Pb.registerUsernameResponseDecoder}
postLogInUsername : (Result Error Pb.AuthSuccess -> msg) -> Pb.LogInUsernameRequest -> Cmd msg
postLogInUsername = call {url="/api/LogInUsername", encoder=Pb.toLogInUsernameRequestEncoder, decoder=Pb.authSuccessDecoder}
postCreatePrediction : (Result Http.Error Pb.CreatePredictionResponse -> msg) -> Pb.CreatePredictionRequest -> Cmd msg
postCreatePrediction = hit {url="/api/CreatePrediction", encoder=Pb.toCreatePredictionRequestEncoder, decoder=Pb.createPredictionResponseDecoder}
postGetPrediction : (Result Error Pb.UserPredictionView -> msg) -> Pb.GetPredictionRequest -> Cmd msg
postGetPrediction = call {url="/api/GetPrediction", encoder=Pb.toGetPredictionRequestEncoder, decoder=Pb.userPredictionViewDecoder}
postListMyStakes : (Result Http.Error Pb.ListMyStakesResponse -> msg) -> Pb.ListMyStakesRequest -> Cmd msg
postListMyStakes = hit {url="/api/ListMyStakes", encoder=Pb.toListMyStakesRequestEncoder, decoder=Pb.listMyStakesResponseDecoder}
postListPredictions : (Result Http.Error Pb.ListPredictionsResponse -> msg) -> Pb.ListPredictionsRequest -> Cmd msg
postListPredictions = hit {url="/api/ListPredictions", encoder=Pb.toListPredictionsRequestEncoder, decoder=Pb.listPredictionsResponseDecoder}
postStake : (Result Http.Error Pb.StakeResponse -> msg) -> Pb.StakeRequest -> Cmd msg
postStake = hit {url="/api/Stake", encoder=Pb.toStakeRequestEncoder, decoder=Pb.stakeResponseDecoder}
postFollow : (Result Http.Error Pb.FollowResponse -> msg) -> Pb.FollowRequest -> Cmd msg
postFollow = hit {url="/api/Follow", encoder=Pb.toFollowRequestEncoder, decoder=Pb.followResponseDecoder}
postResolve : (Result Http.Error Pb.ResolveResponse -> msg) -> Pb.ResolveRequest -> Cmd msg
postResolve = hit {url="/api/Resolve", encoder=Pb.toResolveRequestEncoder, decoder=Pb.resolveResponseDecoder}
postSetTrusted : (Result Http.Error Pb.SetTrustedResponse -> msg) -> Pb.SetTrustedRequest -> Cmd msg
postSetTrusted = hit {url="/api/SetTrusted", encoder=Pb.toSetTrustedRequestEncoder, decoder=Pb.setTrustedResponseDecoder}
postGetUser : (Result Http.Error Pb.GetUserResponse -> msg) -> Pb.GetUserRequest -> Cmd msg
postGetUser = hit {url="/api/GetUser", encoder=Pb.toGetUserRequestEncoder, decoder=Pb.getUserResponseDecoder}
postChangePassword : (Result Http.Error Pb.ChangePasswordResponse -> msg) -> Pb.ChangePasswordRequest -> Cmd msg
postChangePassword = hit {url="/api/ChangePassword", encoder=Pb.toChangePasswordRequestEncoder, decoder=Pb.changePasswordResponseDecoder}
postGetSettings : (Result Http.Error Pb.GetSettingsResponse -> msg) -> Pb.GetSettingsRequest -> Cmd msg
postGetSettings = hit {url="/api/GetSettings", encoder=Pb.toGetSettingsRequestEncoder, decoder=Pb.getSettingsResponseDecoder}
postSendInvitation : (Result Http.Error Pb.SendInvitationResponse -> msg) -> Pb.SendInvitationRequest -> Cmd msg
postSendInvitation = hit {url="/api/SendInvitation", encoder=Pb.toSendInvitationRequestEncoder, decoder=Pb.sendInvitationResponseDecoder}
postAcceptInvitation : (Result Http.Error Pb.AcceptInvitationResponse -> msg) -> Pb.AcceptInvitationRequest -> Cmd msg
postAcceptInvitation = hit {url="/api/AcceptInvitation", encoder=Pb.toAcceptInvitationRequestEncoder, decoder=Pb.acceptInvitationResponseDecoder}

httpErrorToString : Http.Error -> String
httpErrorToString e =
  case e of
    Http.BadUrl _ -> "unintelligible URL"
    Http.Timeout -> "timed out"
    Http.NetworkError -> "network error"
    Http.BadStatus code -> "HTTP error code " ++ String.fromInt code
    Http.BadBody _ -> "unintelligible response"

{-| Kept so the ten call sites don't change shape. Note what disappeared: the
`Nothing -> Err "neither Ok nor Error"` arm. That state was unrepresentable in
HTTP terms, but the protobuf `oneof` forced us to have an opinion about it.
-}
simplifyLogInUsernameResponse : Result Error Pb.AuthSuccess -> Result String Pb.AuthSuccess
simplifyLogInUsernameResponse = Result.mapError errorToString

simplifySendVerificationEmailResponse : Result Http.Error Pb.SendVerificationEmailResponse -> Result String Pb.Void
simplifySendVerificationEmailResponse res =
  case res of
    Err e -> Err (httpErrorToString e)
    Ok resp ->
      case resp.sendVerificationEmailResult of
        Just (Pb.SendVerificationEmailResultOk success) ->
          Ok success
        Just (Pb.SendVerificationEmailResultError e) ->
          Err e.catchall
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifyRegisterUsernameResponse : Result Http.Error Pb.RegisterUsernameResponse -> Result String Pb.AuthSuccess
simplifyRegisterUsernameResponse res =
  case res of
    Err e -> Err (httpErrorToString e)
    Ok resp ->
      case resp.registerUsernameResult of
        Just (Pb.RegisterUsernameResultOk success) ->
          Ok success
        Just (Pb.RegisterUsernameResultError e) ->
          Err e.catchall
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifySignOutResponse : Result Http.Error Pb.SignOutResponse -> Result String ()
simplifySignOutResponse res =
  case res of
    Err e -> Err (httpErrorToString e)
    Ok {} -> Ok ()

simplifySendInvitationResponse : Result Http.Error Pb.SendInvitationResponse -> Result String ()
simplifySendInvitationResponse res =
  case res of
    Err e -> Err (httpErrorToString e)
    Ok resp ->
      case resp.sendInvitationResult of
        Just (Pb.SendInvitationResultOk _) ->
          Ok ()
        Just (Pb.SendInvitationResultError e) ->
          Err e.catchall
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifyAcceptInvitationResponse : Result Http.Error Pb.AcceptInvitationResponse -> Result String Pb.GenericUserInfo
simplifyAcceptInvitationResponse res =
  case res of
    Err e -> Err (httpErrorToString e)
    Ok resp ->
      case resp.acceptInvitationResult of
        Just (Pb.AcceptInvitationResultOk result) ->
          Ok result
        Just (Pb.AcceptInvitationResultError e) ->
          Err e.catchall
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifyCreatePredictionResponse : Result Http.Error Pb.CreatePredictionResponse -> Result String PredictionId
simplifyCreatePredictionResponse res =
  case res of
    Err e -> Err (httpErrorToString e)
    Ok resp ->
      case resp.createPredictionResult of
        Just (Pb.CreatePredictionResultNewPredictionId result) ->
          Ok result
        Just (Pb.CreatePredictionResultError e) ->
          Err e.catchall
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifyStakeResponse : Result Http.Error Pb.StakeResponse -> Result String Pb.UserPredictionView
simplifyStakeResponse res =
  case res of
    Err e -> Err (httpErrorToString e)
    Ok resp ->
      case resp.stakeResult of
        Just (Pb.StakeResultOk result) ->
          Ok result
        Just (Pb.StakeResultError e) ->
          Err e.catchall
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifyFollowResponse : Result Http.Error Pb.FollowResponse -> Result String Pb.UserPredictionView
simplifyFollowResponse res =
  case res of
    Err e -> Err (httpErrorToString e)
    Ok resp ->
      case resp.followResult of
        Just (Pb.FollowResultOk result) ->
          Ok result
        Just (Pb.FollowResultError e) ->
          Err e.catchall
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifyResolveResponse : Result Http.Error Pb.ResolveResponse -> Result String Pb.UserPredictionView
simplifyResolveResponse res =
  case res of
    Err e -> Err (httpErrorToString e)
    Ok resp ->
      case resp.resolveResult of
        Just (Pb.ResolveResultOk result) ->
          Ok result
        Just (Pb.ResolveResultError e) ->
          Err e.catchall
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifyChangePasswordResponse : Result Http.Error Pb.ChangePasswordResponse -> Result String Pb.Void
simplifyChangePasswordResponse res =
  case res of
    Err e -> Err (httpErrorToString e)
    Ok resp ->
      case resp.changePasswordResult of
        Just (Pb.ChangePasswordResultOk result) ->
          Ok result
        Just (Pb.ChangePasswordResultError e) ->
          Err e.catchall
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifySetTrustedResponse : Result Http.Error Pb.SetTrustedResponse -> Result String Pb.GenericUserInfo
simplifySetTrustedResponse res =
  case res of
    Err e -> Err (httpErrorToString e)
    Ok resp ->
      case resp.setTrustedResult of
        Just (Pb.SetTrustedResultOk result) ->
          Ok result
        Just (Pb.SetTrustedResultError e) ->
          Err e.catchall
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"
