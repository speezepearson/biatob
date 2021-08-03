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

hit : Endpoint req resp -> (Result Http.Error resp -> msg) -> req -> Cmd msg
hit endpoint toMsg req =
  Http.post
    { url = endpoint.url
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| endpoint.encoder req
    , expect = PD.expectBytes toMsg endpoint.decoder
    }

postWhoami : (Result Http.Error Pb.WhoamiResponse -> msg) -> Pb.WhoamiRequest -> Cmd msg
postWhoami = hit {url="/api/Whoami", encoder=Pb.toWhoamiRequestEncoder, decoder=Pb.whoamiResponseDecoder}
postSignOut : (Result Http.Error Pb.SignOutResponse -> msg) -> Pb.SignOutRequest -> Cmd msg
postSignOut = hit {url="/api/SignOut", encoder=Pb.toSignOutRequestEncoder, decoder=Pb.signOutResponseDecoder}
postSendVerificationEmail : (Result Http.Error Pb.SendVerificationEmailResponse -> msg) -> Pb.SendVerificationEmailRequest -> Cmd msg
postSendVerificationEmail = hit {url="/api/SendVerificationEmail", encoder=Pb.toSendVerificationEmailRequestEncoder, decoder=Pb.sendVerificationEmailResponseDecoder}
postRegisterUsername : (Result Http.Error Pb.RegisterUsernameResponse -> msg) -> Pb.RegisterUsernameRequest -> Cmd msg
postRegisterUsername = hit {url="/api/RegisterUsername", encoder=Pb.toRegisterUsernameRequestEncoder, decoder=Pb.registerUsernameResponseDecoder}
postLogInUsername : (Result Http.Error Pb.LogInUsernameResponse -> msg) -> Pb.LogInUsernameRequest -> Cmd msg
postLogInUsername = hit {url="/api/LogInUsername", encoder=Pb.toLogInUsernameRequestEncoder, decoder=Pb.logInUsernameResponseDecoder}
postCreatePrediction : (Result Http.Error Pb.CreatePredictionResponse -> msg) -> Pb.CreatePredictionRequest -> Cmd msg
postCreatePrediction = hit {url="/api/CreatePrediction", encoder=Pb.toCreatePredictionRequestEncoder, decoder=Pb.createPredictionResponseDecoder}
postGetPrediction : (Result Http.Error Pb.GetPredictionResponse -> msg) -> Pb.GetPredictionRequest -> Cmd msg
postGetPrediction = hit {url="/api/GetPrediction", encoder=Pb.toGetPredictionRequestEncoder, decoder=Pb.getPredictionResponseDecoder}
postListMyStakes : (Result Http.Error Pb.ListMyStakesResponse -> msg) -> Pb.ListMyStakesRequest -> Cmd msg
postListMyStakes = hit {url="/api/ListMyStakes", encoder=Pb.toListMyStakesRequestEncoder, decoder=Pb.listMyStakesResponseDecoder}
postListPredictions : (Result Http.Error Pb.ListPredictionsResponse -> msg) -> Pb.ListPredictionsRequest -> Cmd msg
postListPredictions = hit {url="/api/ListPredictions", encoder=Pb.toListPredictionsRequestEncoder, decoder=Pb.listPredictionsResponseDecoder}
postStake : (Result Http.Error Pb.StakeResponse -> msg) -> Pb.StakeRequest -> Cmd msg
postStake = hit {url="/api/Stake", encoder=Pb.toStakeRequestEncoder, decoder=Pb.stakeResponseDecoder}
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

simplifyLogInUsernameResponse : Result Http.Error Pb.LogInUsernameResponse -> Result String Pb.AuthSuccess
simplifyLogInUsernameResponse res =
  case res of
    Err e -> Err (httpErrorToString e)
    Ok resp ->
      case resp.logInUsernameResult of
        Just (Pb.LogInUsernameResultOk success) ->
          Ok success
        Just (Pb.LogInUsernameResultError e) ->
          Err e.catchall
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

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
