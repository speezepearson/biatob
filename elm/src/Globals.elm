module Globals exposing
  ( Globals
  , getUserInfo
  , isLoggedIn
  , isSelf
  , TrustRelationship(..)
  , getTrustRelationship
  , getRelationship
  , getOwnUsername
  , ServerState
  , globalsDecoder
  , tick
  , handleWhoamiResponse
  , handleSignOutResponse
  , handleSendVerificationEmailResponse
  , handleRegisterUsernameResponse
  , handleLogInUsernameResponse
  , handleCreatePredictionResponse
  , handleGetPredictionResponse
  , handleListMyStakesResponse
  , handleListPredictionsResponse
  , handleStakeResponse
  , handleFollowResponse
  , handleResolveResponse
  , handleSetTrustedResponse
  , handleGetUserResponse
  , handleChangePasswordResponse
  , handleGetSettingsResponse
  , handleSendInvitationResponse
  , handleAcceptInvitationResponse
  )

import Dict exposing (Dict)
import Json.Decode as JD
import Time
import Http

import API
import Biatob.Proto.Mvp as Pb
import Utils exposing (Username, PredictionId)

type alias Globals =
  { self : Maybe {username:Username, settings:Pb.GenericUserInfo}
  , serverState : ServerState
  , now : Time.Posix
  , timeZone : Time.Zone
  , httpOrigin : String
  }

type alias ServerState =
  { predictions : Dict PredictionId Pb.UserPredictionView
  }

type TrustRelationship = LoggedOut | Self | Friends | TrustsCurrentUser | TrustedByCurrentUser | NoRelation
getTrustRelationship : Globals -> Username -> TrustRelationship
getTrustRelationship globals who =
  if not (isLoggedIn globals) then
    LoggedOut
  else if isSelf globals who then
    Self
  else case getRelationship globals who |> Maybe.map (\r -> (r.trustsYou, r.trustedByYou)) |> Maybe.withDefault (False, False) of
    (True, True) -> Friends
    (True, False) -> TrustsCurrentUser
    (False, True) -> TrustedByCurrentUser
    (False, False) -> NoRelation

handleWhoamiResponse : Pb.WhoamiRequest -> Result API.Error Pb.WhoamiResponse -> Globals -> Globals
handleWhoamiResponse _ _ globals = globals
handleSignOutResponse : Pb.SignOutRequest -> Result API.Error Pb.SignOutResponse -> Globals -> Globals
handleSignOutResponse _ res globals =
  case res of
    Ok _ -> { globals | self = Nothing }
    Err _ -> globals
handleSendVerificationEmailResponse : Pb.SendVerificationEmailRequest -> Result API.Error Pb.Empty -> Globals -> Globals
handleSendVerificationEmailResponse _ _ globals = globals
handleRegisterUsernameResponse : Pb.RegisterUsernameRequest -> Result API.Error Pb.AuthSuccess -> Globals -> Globals
handleRegisterUsernameResponse _ res globals =
  case res of
    Ok authSuccess -> { globals | self = Just {username=Utils.mustAuthSuccessToken authSuccess |> .owner, settings=Utils.mustAuthSuccessUserInfo authSuccess} }
    Err _ -> globals
handleLogInUsernameResponse : Pb.LogInUsernameRequest -> Result API.Error Pb.AuthSuccess -> Globals -> Globals
handleLogInUsernameResponse _ res globals =
  case res of
    Ok authSuccess -> { globals | self = Just {username=Utils.mustAuthSuccessToken authSuccess |> .owner, settings=Utils.mustAuthSuccessUserInfo authSuccess} }
    Err _ -> globals
handleCreatePredictionResponse : Pb.CreatePredictionRequest -> Result API.Error Pb.CreatePredictionResponse -> Globals -> Globals
handleCreatePredictionResponse _ _ globals = globals
handleGetPredictionResponse : Pb.GetPredictionRequest -> Result API.Error Pb.UserPredictionView -> Globals -> Globals
handleGetPredictionResponse req res globals =
  case res of
    Ok prediction -> { globals | serverState = globals.serverState |> addPrediction req.predictionId prediction }
    Err _ -> globals
handleListMyStakesResponse : Pb.ListMyStakesRequest -> Result API.Error Pb.PredictionsById -> Globals -> Globals
handleListMyStakesResponse _ res globals =
  case res of
    Ok predictions -> { globals | serverState = globals.serverState |> addPredictions predictions }
    Err _ -> globals
handleListPredictionsResponse : Pb.ListPredictionsRequest -> Result API.Error Pb.PredictionsById -> Globals -> Globals
handleListPredictionsResponse _ res globals =
  case res of
    Ok predictions -> { globals | serverState = globals.serverState |> addPredictions predictions }
    Err _ -> globals
handleStakeResponse : Pb.StakeRequest -> Result API.Error Pb.UserPredictionView -> Globals -> Globals
handleStakeResponse req res globals =
  case res of
    Ok newPrediction -> { globals | serverState = globals.serverState |> addPrediction req.predictionId newPrediction }
    Err _ -> globals
handleFollowResponse : Pb.FollowRequest -> Result API.Error Pb.UserPredictionView -> Globals -> Globals
handleFollowResponse req res globals =
  case res of
    Ok newPrediction -> { globals | serverState = globals.serverState |> addPrediction req.predictionId newPrediction }
    Err _ -> globals
handleResolveResponse : Pb.ResolveRequest -> Result API.Error Pb.UserPredictionView -> Globals -> Globals
handleResolveResponse req res globals =
  case res of
    Ok newPrediction -> { globals | serverState = globals.serverState |> addPrediction req.predictionId newPrediction }
    Err _ -> globals
handleSetTrustedResponse : Pb.SetTrustedRequest -> Result API.Error Pb.GenericUserInfo -> Globals -> Globals
handleSetTrustedResponse _ res globals =
  case res of
    Ok userInfo -> Debug.log "globals before update" globals |> updateUserInfo (\_ -> userInfo) |> Debug.log "globals after update"
    Err _ -> globals
handleGetUserResponse : Pb.GetUserRequest -> Result API.Error Pb.Relationship -> Globals -> Globals
handleGetUserResponse req res globals =
  case res of
    Ok relationship -> globals |> addRelationship req.who relationship
    Err _ -> globals
handleChangePasswordResponse : Pb.ChangePasswordRequest -> Result API.Error Pb.Empty -> Globals -> Globals
handleChangePasswordResponse _ _ globals = globals
handleGetSettingsResponse : Pb.GetSettingsRequest -> Result API.Error Pb.GenericUserInfo -> Globals -> Globals
handleGetSettingsResponse _ res globals =
  case res of
    Ok newInfo -> globals |> updateUserInfo (always newInfo)
    Err _ -> globals
handleSendInvitationResponse : Pb.SendInvitationRequest -> Result API.Error Pb.GenericUserInfo -> Globals -> Globals
handleSendInvitationResponse req res globals =
  case res of
    Ok newInfo -> globals |> updateUserInfo (always newInfo)
    Err _ -> globals

handleAcceptInvitationResponse : Pb.AcceptInvitationRequest -> Result API.Error Pb.GenericUserInfo -> Globals -> Globals
handleAcceptInvitationResponse _ res globals =
  case res of
    Ok userInfo -> globals |> updateUserInfo (\_ -> userInfo)
    Err _ -> globals

addPrediction : PredictionId -> Pb.UserPredictionView -> ServerState -> ServerState
addPrediction predictionId prediction state =
  { state | predictions = state.predictions |> Dict.insert predictionId prediction }

addPredictions : Pb.PredictionsById -> ServerState -> ServerState
addPredictions predictions state =
  { state | predictions = state.predictions |> Dict.union (Utils.mustMapValues predictions.predictions) }

addRelationship : Username -> Pb.Relationship -> Globals -> Globals
addRelationship username relationship globals =
  { globals | self = globals.self |> Maybe.map (\self -> { self | settings = self.settings |> (\settings -> { settings | relationships = settings.relationships |> Dict.insert username (Just relationship) }) }) }

updateUserInfo : (Pb.GenericUserInfo -> Pb.GenericUserInfo) -> Globals -> Globals
updateUserInfo f globals =
  { globals | self = globals.self |> Maybe.map (\self -> {self | settings = self.settings |> f}) }

getUserInfo : Globals -> Maybe Pb.GenericUserInfo
getUserInfo globals =
  globals.self |> Maybe.map .settings

tick : Time.Posix -> Globals -> Globals
tick now globals =
  { globals | now = now }

isLoggedIn : Globals -> Bool
isLoggedIn globals = globals.self /= Nothing

isSelf : Globals -> Username -> Bool
isSelf globals who =
  case globals.self of
    Nothing -> False
    Just {username} -> username == who

getRelationship : Globals -> Username -> Maybe Pb.Relationship
getRelationship globals who =
  globals.self
  |> Maybe.map (.settings >> .relationships)
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
      { self = authSuccess |> Maybe.map (\succ -> {username=Utils.mustAuthSuccessToken succ |> .owner , settings=Utils.mustAuthSuccessUserInfo succ})
      , serverState =
          { predictions = predictions |> Utils.mustMapValues
          }
      , now = now
      , timeZone = timeZone
      , httpOrigin = httpOrigin
      }
  )))))

getOwnUsername : Globals -> Maybe Username
getOwnUsername globals =
  globals.self |> Maybe.map .username
