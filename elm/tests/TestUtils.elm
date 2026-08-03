module TestUtils exposing (..)

import Json.Decode as JD

import Dict exposing (Dict)

import Api.Types as Pb
import Api.Json
import Globals
import Utils exposing (PredictionId, Username)
import Time

exampleSettings : Pb.GenericUserInfo
exampleSettings =
  { emailAddress = "user@example.com"
  , invitations = Dict.empty
  , relationships = Dict.empty
  }

logInAs : Username -> Pb.GenericUserInfo -> Globals.Globals -> Globals.Globals
logInAs username settings globals =
  { globals | self = Just {username=username, settings=settings}}

logOut : Globals.Globals -> Globals.Globals
logOut globals =
  { globals | self = Nothing }

exampleGlobals : Globals.Globals
exampleGlobals =
  { self = Nothing
  , serverState = { predictions = Dict.empty }
  , now = Time.millisToPosix 12345678
  , timeZone = Time.customZone 42 []
  , httpOrigin = "https://example.com"
  }

addPrediction : PredictionId -> Pb.UserPredictionView -> Globals.Globals -> Globals.Globals
addPrediction predid pred globals =
  { globals | serverState = globals.serverState |> (\ss -> {ss | predictions = ss.predictions |> Dict.insert predid pred})}
