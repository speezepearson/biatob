module API exposing (..)

import Protobuf.Decode as PD
import Protobuf.Encode as PE
import Biatob.Proto.Mvp as Pb
import Http

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
postSetEmail : (Result Http.Error Pb.SetEmailResponse -> msg) -> Pb.SetEmailRequest -> Cmd msg
postSetEmail = hit {url="/api/SetEmail", encoder=Pb.toSetEmailRequestEncoder, decoder=Pb.setEmailResponseDecoder}
postVerifyEmail : (Result Http.Error Pb.VerifyEmailResponse -> msg) -> Pb.VerifyEmailRequest -> Cmd msg
postVerifyEmail = hit {url="/api/VerifyEmail", encoder=Pb.toVerifyEmailRequestEncoder, decoder=Pb.verifyEmailResponseDecoder}
postGetSettings : (Result Http.Error Pb.GetSettingsResponse -> msg) -> Pb.GetSettingsRequest -> Cmd msg
postGetSettings = hit {url="/api/GetSettings", encoder=Pb.toGetSettingsRequestEncoder, decoder=Pb.getSettingsResponseDecoder}
postUpdateSettings : (Result Http.Error Pb.UpdateSettingsResponse -> msg) -> Pb.UpdateSettingsRequest -> Cmd msg
postUpdateSettings = hit {url="/api/UpdateSettings", encoder=Pb.toUpdateSettingsRequestEncoder, decoder=Pb.updateSettingsResponseDecoder}
postCreateInvitation : (Result Http.Error Pb.CreateInvitationResponse -> msg) -> Pb.CreateInvitationRequest -> Cmd msg
postCreateInvitation = hit {url="/api/CreateInvitation", encoder=Pb.toCreateInvitationRequestEncoder, decoder=Pb.createInvitationResponseDecoder}
postAcceptInvitation : (Result Http.Error Pb.AcceptInvitationResponse -> msg) -> Pb.AcceptInvitationRequest -> Cmd msg
postAcceptInvitation = hit {url="/api/AcceptInvitation", encoder=Pb.toAcceptInvitationRequestEncoder, decoder=Pb.acceptInvitationResponseDecoder}

simplifyLogInUsernameResponse : Result Http.Error Pb.LogInUsernameResponse -> Result String Pb.AuthSuccess
simplifyLogInUsernameResponse res =
  case res of
    Err e -> Err (Debug.toString e)
    Ok resp ->
      case resp.logInUsernameResult of
        Just (Pb.LogInUsernameResultOk success) ->
          Ok success
        Just (Pb.LogInUsernameResultError e) ->
          Err (Debug.toString e)
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifyRegisterUsernameResponse : Result Http.Error Pb.RegisterUsernameResponse -> Result String Pb.AuthSuccess
simplifyRegisterUsernameResponse res =
  case res of
    Err e -> Err (Debug.toString e)
    Ok resp ->
      case resp.registerUsernameResult of
        Just (Pb.RegisterUsernameResultOk success) ->
          Ok success
        Just (Pb.RegisterUsernameResultError e) ->
          Err (Debug.toString e)
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifySignOutResponse : Result Http.Error Pb.SignOutResponse -> Result String ()
simplifySignOutResponse res =
  case res of
    Err e -> Err (Debug.toString e)
    Ok {} -> Ok ()

simplifyCreateInvitationResponse : Result Http.Error Pb.CreateInvitationResponse -> Result String Pb.CreateInvitationResponseResult
simplifyCreateInvitationResponse res =
  case res of
    Err e -> Err (Debug.toString e)
    Ok resp ->
      case resp.createInvitationResult of
        Just (Pb.CreateInvitationResultOk result) ->
          Ok result
        Just (Pb.CreateInvitationResultError e) ->
          Err (Debug.toString e)
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifyStakeResponse : Result Http.Error Pb.StakeResponse -> Result String Pb.UserPredictionView
simplifyStakeResponse res =
  case res of
    Err e -> Err (Debug.toString e)
    Ok resp ->
      case resp.stakeResult of
        Just (Pb.StakeResultOk result) ->
          Ok result
        Just (Pb.StakeResultError e) ->
          Err (Debug.toString e)
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifyUpdateSettingsResponse : Result Http.Error Pb.UpdateSettingsResponse -> Result String Pb.GenericUserInfo
simplifyUpdateSettingsResponse res =
  case res of
    Err e -> Err (Debug.toString e)
    Ok resp ->
      case resp.updateSettingsResult of
        Just (Pb.UpdateSettingsResultOk result) ->
          Ok result
        Just (Pb.UpdateSettingsResultError e) ->
          Err (Debug.toString e)
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifySetEmailResponse : Result Http.Error Pb.SetEmailResponse -> Result String Pb.EmailFlowState
simplifySetEmailResponse res =
  case res of
    Err e -> Err (Debug.toString e)
    Ok resp ->
      case resp.setEmailResult of
        Just (Pb.SetEmailResultOk result) ->
          Ok result
        Just (Pb.SetEmailResultError e) ->
          Err (Debug.toString e)
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifyVerifyEmailResponse : Result Http.Error Pb.VerifyEmailResponse -> Result String Pb.EmailFlowState
simplifyVerifyEmailResponse res =
  case res of
    Err e -> Err (Debug.toString e)
    Ok resp ->
      case resp.verifyEmailResult of
        Just (Pb.VerifyEmailResultOk result) ->
          Ok result
        Just (Pb.VerifyEmailResultError e) ->
          Err (Debug.toString e)
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifyChangePasswordResponse : Result Http.Error Pb.ChangePasswordResponse -> Result String Pb.Void
simplifyChangePasswordResponse res =
  case res of
    Err e -> Err (Debug.toString e)
    Ok resp ->
      case resp.changePasswordResult of
        Just (Pb.ChangePasswordResultOk result) ->
          Ok result
        Just (Pb.ChangePasswordResultError e) ->
          Err (Debug.toString e)
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"

simplifySetTrustedResponse : Result Http.Error Pb.SetTrustedResponse -> Result String Pb.GenericUserInfo
simplifySetTrustedResponse res =
  case res of
    Err e -> Err (Debug.toString e)
    Ok resp ->
      case resp.setTrustedResult of
        Just (Pb.SetTrustedResultOk result) ->
          Ok result
        Just (Pb.SetTrustedResultError e) ->
          Err (Debug.toString e)
        Nothing ->
          Err "Invalid server response (neither Ok nor Error in protobuf)"
