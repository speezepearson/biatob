module Widgets.StakeWidget exposing (..)

import Browser
import Dict
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Time
import Http

import Biatob.Proto.Mvp as Pb
import Utils exposing (b, Cents, PredictionId)

import Page
import API

epsilon = 0.0000001 -- 🎵 I hate floating-point arithmetic 🎶

type alias Config msg =
  { setState : State -> msg
  , stake : State -> Pb.StakeRequest -> msg
  , predictionId : PredictionId
  , prediction : Pb.UserPredictionView
  , now : Time.Posix
  }
type alias State =
  { believerStakeField : String
  , skepticStakeField : String
  , working : Bool
  , notification : Html Never
  , disableCommit : Bool
  , predictionId : PredictionId
  }

handleStakeResponse : Result Http.Error Pb.StakeResponse -> State -> State
handleStakeResponse res state =
  case API.simplifyStakeResponse res of
    Ok resp ->
      { state | working = False
              , notification = Utils.greenText "Committed!"
              , believerStakeField = "0"
              , skepticStakeField = "0"
      }
    Err e ->
      { state | working = False
              , notification = Utils.redText e
      }

view : Config msg -> State -> Html msg
view config state =
  let
    creator = config.prediction.creator
    certainty = Utils.mustPredictionCertainty config.prediction

    isClosed = Utils.timeToUnixtime config.now > config.prediction.closesUnixtime
    disableInputs = isClosed || Utils.resolutionIsTerminal (Utils.currentResolution config.prediction)
    creatorStakeFactorVsBelievers = (1 - certainty.high) / certainty.high
    creatorStakeFactorVsSkeptics = certainty.low / (1 - certainty.low)
    maxBelieverStakeCents = if creatorStakeFactorVsBelievers == 0 then 0 else toFloat config.prediction.remainingStakeCentsVsBelievers / creatorStakeFactorVsBelievers + 0.001 |> floor
    maxSkepticStakeCents = if creatorStakeFactorVsSkeptics == 0 then 0 else toFloat config.prediction.remainingStakeCentsVsSkeptics / creatorStakeFactorVsSkeptics + 0.001 |> floor
  in
  H.div []
    [ if certainty.low == 0 then H.text "" else
      let skepticStakeCents = parseCents {max=maxSkepticStakeCents} state.skepticStakeField in
      H.p []
      [ H.text "Do you ", b "strongly doubt", H.text " that this will happen? Then stake $"
      , H.input
          [ HA.style "width" "5em"
          , HA.type_"number", HA.min "0", HA.max (toFloat maxSkepticStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
          , HA.disabled disableInputs
          , HE.onInput (\s -> config.setState {state | skepticStakeField = s})
          , HA.value state.skepticStakeField
          ]
          []
        |> Utils.appendValidationError (Utils.resultToErr skepticStakeCents)
      , H.text " that it won't, against ", Utils.renderUser creator, H.text "'s "
      , Utils.b (skepticStakeCents |> Result.map (toFloat >> (*) creatorStakeFactorVsSkeptics >> round >> Utils.formatCents) |> Result.withDefault "???")
      , H.text ". "
      , H.button
          (case skepticStakeCents of
            Ok stake ->
              [ HE.onClick (config.stake {state | working=True, notification=H.text ""} {predictionId=config.predictionId, bettorIsASkeptic=True, bettorStakeCents=stake}) ]
            Err _ ->
              [ HA.disabled True ]
          )
          [H.text "Commit"]
      ]
    , if certainty.high == 1 then H.text "" else
      let believerStakeCents = parseCents {max=maxBelieverStakeCents} state.believerStakeField in
      H.p []
      [ H.text "Do you ", b "strongly believe", H.text " that this will happen? Then stake $"
      , H.input
          [ HA.style "width" "5em"
          , HA.type_"number", HA.min "0", HA.max (toFloat maxBelieverStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
          , HA.disabled disableInputs
          , HE.onInput (\s -> config.setState {state | believerStakeField=s})
          , HA.value state.believerStakeField
          ]
          []
        |> Utils.appendValidationError (Utils.resultToErr believerStakeCents)
      , H.text " that it will, against ", Utils.renderUser creator, H.text "'s "
      , Utils.b (believerStakeCents |> Result.map (toFloat >> (*) creatorStakeFactorVsBelievers >> round >> Utils.formatCents) |> Result.withDefault "???")
      , H.text ". "
      , H.button
          (case believerStakeCents of
            Ok stake ->
              [ HE.onClick (config.stake {state | working=True, notification=H.text ""} {predictionId=config.predictionId, bettorIsASkeptic=False, bettorStakeCents=stake}) ]
            Err _ ->
              [ HA.disabled True ]
          )
          [H.text "Commit"]
      ]
    , state.notification |> H.map never
    ]

init : PredictionId -> State
init predictionId =
  { believerStakeField = "0"
  , skepticStakeField = "0"
  , working = False
  , notification = H.text ""
  , disableCommit = False
  , predictionId = predictionId
  }

parseCents : {max:Cents} -> String -> Result String Cents
parseCents {max} s =
  case String.toFloat s of
    Nothing -> Err "must be a number"
    Just dollars ->
      let n = round (100*dollars) in
      if n < 0 || n > max then Err ("must be between $0 and " ++ Utils.formatCents max) else Ok n
