module Widgets.CreatePredictionWidget exposing (..)

import Html as H exposing (Html)
import Html.Events as HE
import Html.Attributes as HA
import Utils exposing (i, Cents)
import Time

import Biatob.Proto.Mvp as Pb
import Utils
import Page

maxLegalStakeCents = 500000
epsilon = 0.000001

type OpenForUnit = Days | Weeks
unitToSeconds : OpenForUnit -> Int
unitToSeconds u =
  case u of
    Days -> 60 * 60 * 24
    Weeks -> unitToSeconds Days * 7

type alias Model =
  { predictionField : String
  , resolvesAtField : String
  , stakeField : String
  , lowPField : String
  , highPField : String
  , openForUnitField : String
  , openForSecondsField : String
  , specialRulesField : String
  }
type Msg
  = SetPredictionField String
  | SetResolvesAtField String
  | SetStakeField String
  | SetLowPField String
  | SetHighPField String
  | SetOpenForUnitField String
  | SetOpenForSecondsField String
  | SetSpecialRulesField String

toCreateRequest : Time.Posix -> Time.Zone -> Model -> Maybe Pb.CreatePredictionRequest
toCreateRequest now _ model =
  parsePrediction model |> Result.toMaybe |> Maybe.andThen (\prediction ->
  parseResolvesAt now model |> Result.toMaybe |> Maybe.andThen (\resolvesAt ->
  parseStake model |> Result.toMaybe |> Maybe.andThen (\stake ->
  parseLowProbability model |> Result.toMaybe |> Maybe.andThen (\lowP ->
  parseHighProbability model |> Result.toMaybe |> Maybe.andThen (\highP -> if highP < lowP then Nothing else
  parseOpenForSeconds now model |> Result.toMaybe |> Maybe.andThen (\openForSeconds ->
    Just
      { prediction = prediction
      , certainty = Just { low=lowP, high=highP }
      , maximumStakeCents = stake
      , openSeconds = openForSeconds
      , specialRules = model.specialRulesField
      , resolvesAtUnixtime = Utils.timeToUnixtime resolvesAt
      }
  ))))))
