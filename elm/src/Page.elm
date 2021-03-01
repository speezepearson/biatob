module Page exposing
  ( Command(..)
  , Element
  , Globals
  , Request(..)
  , getAuth
  , getUserInfo
  , isLoggedIn
  , mapCmd
  )

import Browser
import Json.Decode as JD
import Time
import Http

import Biatob.Proto.Mvp as Pb
import Utils

type Command msg
  = NoCmd
  | BatchCmd (List (Command msg))
  | RequestCmd (Request msg)
  | CopyCmd String
  | MiscCmd (Cmd msg)
  | NavigateCmd (Maybe String)

type alias Element model msg =
  { init : JD.Value -> ( model , Command msg )
  , view : Globals -> model -> Browser.Document msg
  , update : msg -> model -> ( model , Command msg )
  , subscriptions : model -> Sub msg
  }

type alias Globals =
  { authState : Maybe Pb.AuthSuccess
  , now : Time.Posix
  , httpOrigin : String
  }

type Request msg
  = WhoamiRequest (Result Http.Error Pb.WhoamiResponse -> msg) Pb.WhoamiRequest
  | SignOutRequest (Result Http.Error Pb.SignOutResponse -> msg) Pb.SignOutRequest
  | RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse -> msg) Pb.RegisterUsernameRequest
  | LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse -> msg) Pb.LogInUsernameRequest
  | CreatePredictionRequest (Result Http.Error Pb.CreatePredictionResponse -> msg) Pb.CreatePredictionRequest
  | GetPredictionRequest (Result Http.Error Pb.GetPredictionResponse -> msg) Pb.GetPredictionRequest
  | ListMyStakesRequest (Result Http.Error Pb.ListMyStakesResponse -> msg) Pb.ListMyStakesRequest
  | ListPredictionsRequest (Result Http.Error Pb.ListPredictionsResponse -> msg) Pb.ListPredictionsRequest
  | StakeRequest (Result Http.Error Pb.StakeResponse -> msg) Pb.StakeRequest
  | ResolveRequest (Result Http.Error Pb.ResolveResponse -> msg) Pb.ResolveRequest
  | SetTrustedRequest (Result Http.Error Pb.SetTrustedResponse -> msg) Pb.SetTrustedRequest
  | GetUserRequest (Result Http.Error Pb.GetUserResponse -> msg) Pb.GetUserRequest
  | ChangePasswordRequest (Result Http.Error Pb.ChangePasswordResponse -> msg) Pb.ChangePasswordRequest
  | SetEmailRequest (Result Http.Error Pb.SetEmailResponse -> msg) Pb.SetEmailRequest
  | VerifyEmailRequest (Result Http.Error Pb.VerifyEmailResponse -> msg) Pb.VerifyEmailRequest
  | GetSettingsRequest (Result Http.Error Pb.GetSettingsResponse -> msg) Pb.GetSettingsRequest
  | UpdateSettingsRequest (Result Http.Error Pb.UpdateSettingsResponse -> msg) Pb.UpdateSettingsRequest
  | CreateInvitationRequest (Result Http.Error Pb.CreateInvitationResponse -> msg) Pb.CreateInvitationRequest
  | AcceptInvitationRequest (Result Http.Error Pb.AcceptInvitationResponse -> msg) Pb.AcceptInvitationRequest

getUserInfo : Globals -> Maybe Pb.GenericUserInfo
getUserInfo globals =
  globals.authState |> Maybe.map Utils.mustAuthSuccessUserInfo

getAuth : Globals -> Maybe Pb.AuthToken
getAuth globals =
  globals.authState |> Maybe.map Utils.mustAuthSuccessToken

isLoggedIn : Globals -> Bool
isLoggedIn globals = globals.authState /= Nothing

mapCmd : (a -> b) -> Command a -> Command b
mapCmd f cmd =
  case cmd of
    RequestCmd req -> RequestCmd <| case req of
      WhoamiRequest toMsg pbReq -> WhoamiRequest (toMsg >> f) pbReq
      SignOutRequest toMsg pbReq -> SignOutRequest (toMsg >> f) pbReq
      RegisterUsernameRequest toMsg pbReq -> RegisterUsernameRequest (toMsg >> f) pbReq
      LogInUsernameRequest toMsg pbReq -> LogInUsernameRequest (toMsg >> f) pbReq
      CreatePredictionRequest toMsg pbReq -> CreatePredictionRequest (toMsg >> f) pbReq
      GetPredictionRequest toMsg pbReq -> GetPredictionRequest (toMsg >> f) pbReq
      ListMyStakesRequest toMsg pbReq -> ListMyStakesRequest (toMsg >> f) pbReq
      ListPredictionsRequest toMsg pbReq -> ListPredictionsRequest (toMsg >> f) pbReq
      StakeRequest toMsg pbReq -> StakeRequest (toMsg >> f) pbReq
      ResolveRequest toMsg pbReq -> ResolveRequest (toMsg >> f) pbReq
      SetTrustedRequest toMsg pbReq -> SetTrustedRequest (toMsg >> f) pbReq
      GetUserRequest toMsg pbReq -> GetUserRequest (toMsg >> f) pbReq
      ChangePasswordRequest toMsg pbReq -> ChangePasswordRequest (toMsg >> f) pbReq
      SetEmailRequest toMsg pbReq -> SetEmailRequest (toMsg >> f) pbReq
      VerifyEmailRequest toMsg pbReq -> VerifyEmailRequest (toMsg >> f) pbReq
      GetSettingsRequest toMsg pbReq -> GetSettingsRequest (toMsg >> f) pbReq
      UpdateSettingsRequest toMsg pbReq -> UpdateSettingsRequest (toMsg >> f) pbReq
      CreateInvitationRequest toMsg pbReq -> CreateInvitationRequest (toMsg >> f) pbReq
      AcceptInvitationRequest toMsg pbReq -> AcceptInvitationRequest (toMsg >> f) pbReq
    MiscCmd c -> MiscCmd <| Cmd.map f c
    BatchCmd cs -> BatchCmd <| List.map (mapCmd f) cs
    NoCmd -> NoCmd
    CopyCmd s -> CopyCmd s
    NavigateCmd dest -> NavigateCmd dest

