module API exposing (..)

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
import Task

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

postLogInUsername : (Result Http.Error Pb.LogInUsernameResponse -> msg) -> Pb.LogInUsernameRequest -> Cmd msg
postLogInUsername = hit {url="/api/LogInUsername", encoder=Pb.toLogInUsernameRequestEncoder, decoder=Pb.logInUsernameResponseDecoder}

postRegisterUsername : (Result Http.Error Pb.RegisterUsernameResponse -> msg) -> Pb.RegisterUsernameRequest -> Cmd msg
postRegisterUsername = hit {url="/api/RegisterUsername", encoder=Pb.toRegisterUsernameRequestEncoder, decoder=Pb.registerUsernameResponseDecoder}

postSignOut : (Result Http.Error Pb.SignOutResponse -> msg) -> Pb.SignOutRequest -> Cmd msg
postSignOut = hit {url="/api/SignOut", encoder=Pb.toSignOutRequestEncoder, decoder=Pb.signOutResponseDecoder}

postChangePassword : (Result Http.Error Pb.ChangePasswordResponse -> msg) -> Pb.ChangePasswordRequest -> Cmd msg
postChangePassword = hit {url="/api/ChangePassword", encoder=Pb.toChangePasswordRequestEncoder, decoder=Pb.changePasswordResponseDecoder }

postCreate : (Result Http.Error Pb.CreatePredictionResponse -> msg) -> Pb.CreatePredictionRequest -> Cmd msg
postCreate = hit {url="/api/CreatePrediction", encoder=Pb.toCreatePredictionRequestEncoder, decoder=Pb.createPredictionResponseDecoder }

postSetEmail : (Result Http.Error Pb.SetEmailResponse -> msg) -> Pb.SetEmailRequest -> Cmd msg
postSetEmail = hit {url="/api/SetEmail", encoder=Pb.toSetEmailRequestEncoder, decoder=Pb.setEmailResponseDecoder }

postVerifyEmail : (Result Http.Error Pb.VerifyEmailResponse -> msg) -> Pb.VerifyEmailRequest -> Cmd msg
postVerifyEmail = hit {url="/api/VerifyEmail", encoder=Pb.toVerifyEmailRequestEncoder, decoder=Pb.verifyEmailResponseDecoder}

postUpdateSettings : (Result Http.Error Pb.UpdateSettingsResponse -> msg) -> Pb.UpdateSettingsRequest -> Cmd msg
postUpdateSettings = hit {url="/api/UpdateSettings", encoder=Pb.toUpdateSettingsRequestEncoder, decoder=Pb.updateSettingsResponseDecoder}

postCreateInvitation : (Result Http.Error Pb.CreateInvitationResponse -> msg) -> Pb.CreateInvitationRequest -> Cmd msg
postCreateInvitation = hit {url="/api/CreateInvitation", encoder=Pb.toCreateInvitationRequestEncoder, decoder=Pb.createInvitationResponseDecoder }

postAcceptInvitation : (Result Http.Error Pb.AcceptInvitationResponse -> msg) -> Pb.AcceptInvitationRequest -> Cmd msg
postAcceptInvitation = hit {url="/api/AcceptInvitation", encoder=Pb.toAcceptInvitationRequestEncoder, decoder=Pb.acceptInvitationResponseDecoder }

postSetTrusted : (Result Http.Error Pb.SetTrustedResponse -> msg) -> Pb.SetTrustedRequest -> Cmd msg
postSetTrusted = hit {url="/api/SetTrusted", encoder=Pb.toSetTrustedRequestEncoder, decoder=Pb.setTrustedResponseDecoder }

postStake : (Result Http.Error Pb.StakeResponse -> msg) -> Pb.StakeRequest -> Cmd msg
postStake = hit {url="/api/Stake", encoder=Pb.toStakeRequestEncoder, decoder=Pb.stakeResponseDecoder }

postResolve : (Result Http.Error Pb.ResolveResponse -> msg) -> Pb.ResolveRequest -> Cmd msg
postResolve = hit {url="/api/Resolve", encoder=Pb.toResolveRequestEncoder, decoder=Pb.resolveResponseDecoder }
