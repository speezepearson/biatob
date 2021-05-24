module Globals exposing
  ( Globals
  , getAuth
  , getUserInfo
  , isLoggedIn
  , isSelf
  , getRelationship
  , ServerState
  , globalsDecoder
  , tick
  , handleWhoamiResponse
  , handleSignOutResponse
  , handleRegisterUsernameResponse
  , handleLogInUsernameResponse
  , handleCreatePredictionResponse
  , handleGetPredictionResponse
  , handleListMyStakesResponse
  , handleListPredictionsResponse
  , handleStakeResponse
  , handleResolveResponse
  , handleSetTrustedResponse
  , handleGetUserResponse
  , handleChangePasswordResponse
  , handleSetEmailResponse
  , handleVerifyEmailResponse
  , handleGetSettingsResponse
  , handleUpdateSettingsResponse
  , handleCreateInvitationResponse
  , handleAcceptInvitationResponse
  )

import Dict exposing (Dict)
import Json.Decode as JD
import Time
import Http

import Biatob.Proto.Mvp as Pb
import Utils exposing (Username, PredictionId)

type alias Globals =
  { authToken : Maybe Pb.AuthToken
  , serverState : ServerState
  , now : Time.Posix
  , timeZone : Time.Zone
  , httpOrigin : String
  }

type alias ServerState =
  { settings : Maybe Pb.GenericUserInfo
  , predictions : Dict PredictionId Pb.UserPredictionView
  }

handleWhoamiResponse : Pb.WhoamiRequest -> Result Http.Error Pb.WhoamiResponse -> Globals -> Globals
handleWhoamiResponse _ _ globals = globals
handleSignOutResponse : Pb.SignOutRequest -> Result Http.Error Pb.SignOutResponse -> Globals -> Globals
handleSignOutResponse _ res globals =
  case res of
    Ok _ -> { globals | authToken = Nothing , serverState = globals.serverState |> \s -> { s | settings = Nothing } }
    Err _ -> globals
handleRegisterUsernameResponse : Pb.RegisterUsernameRequest -> Result Http.Error Pb.RegisterUsernameResponse -> Globals -> Globals
handleRegisterUsernameResponse _ res globals =
  case res of
    Ok {registerUsernameResult} -> case registerUsernameResult of
      Just (Pb.RegisterUsernameResultOk authSuccess) -> { globals | authToken = Just (authSuccess |> Utils.mustAuthSuccessToken) , serverState = globals.serverState |> \s -> { s | settings = Just (Utils.mustAuthSuccessUserInfo authSuccess)} }
      _ -> globals
    Err _ -> globals
handleLogInUsernameResponse : Pb.LogInUsernameRequest -> Result Http.Error Pb.LogInUsernameResponse -> Globals -> Globals
handleLogInUsernameResponse _ res globals =
  case res of
    Ok {logInUsernameResult} -> case logInUsernameResult of
      Just (Pb.LogInUsernameResultOk authSuccess) -> { globals | authToken = Just (authSuccess |> Utils.mustAuthSuccessToken) , serverState = globals.serverState |> \s -> { s | settings = Just (Utils.mustAuthSuccessUserInfo authSuccess)} }
      _ -> globals
    Err _ -> globals
handleCreatePredictionResponse : Pb.CreatePredictionRequest -> Result Http.Error Pb.CreatePredictionResponse -> Globals -> Globals
handleCreatePredictionResponse _ _ globals = globals
handleGetPredictionResponse : Pb.GetPredictionRequest -> Result Http.Error Pb.GetPredictionResponse -> Globals -> Globals
handleGetPredictionResponse req res globals =
  case res of
    Ok {getPredictionResult} -> case getPredictionResult of
      Just (Pb.GetPredictionResultPrediction prediction) -> { globals | serverState = globals.serverState |> addPrediction req.predictionId prediction }
      _ -> globals
    Err _ -> globals
handleListMyStakesResponse : Pb.ListMyStakesRequest -> Result Http.Error Pb.ListMyStakesResponse -> Globals -> Globals
handleListMyStakesResponse _ res globals =
  case res of
    Ok {listMyStakesResult} -> case listMyStakesResult of
      Just (Pb.ListMyStakesResultOk predictions) -> { globals | serverState = globals.serverState |> addPredictions predictions }
      _ -> globals
    Err _ -> globals
handleListPredictionsResponse : Pb.ListPredictionsRequest -> Result Http.Error Pb.ListPredictionsResponse -> Globals -> Globals
handleListPredictionsResponse _ res globals =
  case res of
    Ok {listPredictionsResult} -> case listPredictionsResult of
      Just (Pb.ListPredictionsResultOk predictions) -> { globals | serverState = globals.serverState |> addPredictions predictions }
      _ -> globals
    Err _ -> globals
handleStakeResponse : Pb.StakeRequest -> Result Http.Error Pb.StakeResponse -> Globals -> Globals
handleStakeResponse req res globals =
  case res of
    Ok {stakeResult} -> case Debug.log "stakeResult" stakeResult of
      Just (Pb.StakeResultOk newPrediction) -> { globals | serverState = globals.serverState |> addPrediction req.predictionId newPrediction }
      _ -> globals
    Err _ -> globals
handleResolveResponse : Pb.ResolveRequest -> Result Http.Error Pb.ResolveResponse -> Globals -> Globals
handleResolveResponse req res globals =
  case res of
    Ok {resolveResult} -> case Debug.log "resolveResult" resolveResult of
      Just (Pb.ResolveResultOk newPrediction) -> { globals | serverState = globals.serverState |> addPrediction req.predictionId newPrediction }
      _ -> globals
    Err _ -> globals
handleSetTrustedResponse : Pb.SetTrustedRequest -> Result Http.Error Pb.SetTrustedResponse -> Globals -> Globals
handleSetTrustedResponse _ res globals =
  case res of
    Ok {setTrustedResult} -> case Debug.log "setTrustedResult" setTrustedResult of
      Just (Pb.SetTrustedResultOk userInfo) -> Debug.log "globals before update" globals |> updateUserInfo (\_ -> userInfo) |> Debug.log "globals after update"
      _ -> globals
    Err _ -> globals
handleGetUserResponse : Pb.GetUserRequest -> Result Http.Error Pb.GetUserResponse -> Globals -> Globals
handleGetUserResponse req res globals =
  case res of
    Ok {getUserResult} -> case Debug.log "getUserResult" getUserResult of
      Just (Pb.GetUserResultOk relationship) -> { globals | serverState = globals.serverState |> addRelationship req.who relationship }
      _ -> globals
    Err _ -> globals
handleChangePasswordResponse : Pb.ChangePasswordRequest -> Result Http.Error Pb.ChangePasswordResponse -> Globals -> Globals
handleChangePasswordResponse _ _ globals = globals
handleSetEmailResponse : Pb.SetEmailRequest -> Result Http.Error Pb.SetEmailResponse -> Globals -> Globals
handleSetEmailResponse _ res globals =
  case res of
    Ok {setEmailResult} -> case setEmailResult of
      Just (Pb.SetEmailResultOk email) -> globals |> updateUserInfo (\u -> { u | email = Just email })
      _ -> globals
    Err _ -> globals
handleVerifyEmailResponse : Pb.VerifyEmailRequest -> Result Http.Error Pb.VerifyEmailResponse -> Globals -> Globals
handleVerifyEmailResponse _ res globals =
  case res of
    Ok {verifyEmailResult} -> case verifyEmailResult of
      Just (Pb.VerifyEmailResultOk email) -> globals |> updateUserInfo (\u -> { u | email = Just email })
      _ -> globals
    Err _ -> globals
handleGetSettingsResponse : Pb.GetSettingsRequest -> Result Http.Error Pb.GetSettingsResponse -> Globals -> Globals
handleGetSettingsResponse _ res globals =
  case res of
    Ok {getSettingsResult} -> case getSettingsResult of
      Just (Pb.GetSettingsResultOk newInfo) -> globals |> updateUserInfo (always newInfo)
      _ -> globals
    Err _ -> globals
handleUpdateSettingsResponse : Pb.UpdateSettingsRequest -> Result Http.Error Pb.UpdateSettingsResponse -> Globals -> Globals
handleUpdateSettingsResponse _ res globals =
  case res of
    Ok {updateSettingsResult} -> case updateSettingsResult of
      Just (Pb.UpdateSettingsResultOk newInfo) -> globals |> updateUserInfo (always newInfo)
      _ -> globals
    Err _ -> globals
handleCreateInvitationResponse : Pb.CreateInvitationRequest -> Result Http.Error Pb.CreateInvitationResponse -> Globals -> Globals
handleCreateInvitationResponse _ res globals =
  case res of
    Ok {createInvitationResult} -> case createInvitationResult of
      Just (Pb.CreateInvitationResultOk result) -> globals |> updateUserInfo (\_ -> Utils.must "TODO" result.userInfo)
      _ -> globals
    Err _ -> globals
handleAcceptInvitationResponse : Pb.AcceptInvitationRequest -> Result Http.Error Pb.AcceptInvitationResponse -> Globals -> Globals
handleAcceptInvitationResponse _ res globals =
  case res of
    Ok {acceptInvitationResult} -> case acceptInvitationResult of
      Just (Pb.AcceptInvitationResultOk userInfo) -> globals |> updateUserInfo (\_ -> userInfo)
      _ -> globals
    Err _ -> globals

addPrediction : PredictionId -> Pb.UserPredictionView -> ServerState -> ServerState
addPrediction predictionId prediction state =
  { state | predictions = state.predictions |> Dict.insert predictionId prediction }

addPredictions : Pb.PredictionsById -> ServerState -> ServerState
addPredictions predictions state =
  { state | predictions = state.predictions |> Dict.union (Utils.mustMapValues predictions.predictions) }

addRelationship : Username -> Pb.Relationship -> ServerState -> ServerState
addRelationship username relationship state =
  { state | settings = state.settings |> Maybe.map (\s -> { s | relationships = s.relationships |> Dict.insert username (Just relationship) }) }

updateUserInfo : (Pb.GenericUserInfo -> Pb.GenericUserInfo) -> Globals -> Globals
updateUserInfo f globals =
  { globals | serverState = globals.serverState |> \s -> {s | settings = s.settings |> Maybe.map f } }

getUserInfo : Globals -> Maybe Pb.GenericUserInfo
getUserInfo globals =
  globals.serverState.settings

getAuth : Globals -> Maybe Pb.AuthToken
getAuth globals =
  globals.authToken

tick : Time.Posix -> Globals -> Globals
tick now globals =
  { globals | now = now }

isLoggedIn : Globals -> Bool
isLoggedIn globals = globals.authToken /= Nothing

isSelf : Globals -> Username -> Bool
isSelf globals who =
  case getAuth globals of
    Nothing -> False
    Just token -> token.owner == who

getRelationship : Globals -> Username -> Maybe Pb.Relationship
getRelationship globals who =
  globals.serverState.settings
  |> Maybe.map .relationships
  |> Maybe.andThen (Dict.get who)
  |> Maybe.andThen identity

globalsDecoder : JD.Decoder Globals
globalsDecoder =
  (JD.field "authSuccessPbB64" <| JD.nullable <| Utils.pbB64Decoder Pb.authSuccessDecoder) |> JD.andThen (\authSuccess ->
  (JD.maybe <| JD.field "predictionsPbB64" <| Utils.pbB64Decoder Pb.predictionsByIdDecoder) |> JD.map (Maybe.map .predictions >> Maybe.withDefault Dict.empty) |> JD.andThen (\predictions ->
  (JD.field "initUnixtime" JD.float |> JD.map Utils.unixtimeToTime) |> JD.andThen (\now ->
  (JD.field "timeZoneOffsetMinutes" JD.int |> JD.map (\n -> Time.customZone n [])) |> JD.andThen (\timeZone ->
  (JD.field "httpOrigin" JD.string) |> JD.andThen (\httpOrigin ->
    JD.succeed
      { authToken = Maybe.map Utils.mustAuthSuccessToken authSuccess
      , serverState =
          { settings = Maybe.map Utils.mustAuthSuccessUserInfo authSuccess
          , predictions = predictions |> Utils.mustMapValues
          }
      , now = now
      , timeZone = timeZone
      , httpOrigin = httpOrigin
      }
  )))))
