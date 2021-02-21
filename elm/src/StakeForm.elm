module StakeForm exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Time
import Http

import Biatob.Proto.Mvp as Pb
import Utils exposing (b)

import Field exposing (Field)

epsilon = 0.0000001 -- 🎵 I hate floating-point arithmetic 🎶

type Event = Nevermind | Staked {bettorIsASkeptic:Bool, bettorStakeCents:Int}
type alias Config msg =
  { handle : Event -> State -> msg
  , disableCommit : Bool
  , prediction : Pb.UserPredictionView
  }

type alias State =
  { believerStakeField : Field {max : Int} Int
  , skepticStakeField : Field {max : Int} Int
  , now : Time.Posix
  , working : Bool
  , notification : Html ()
  }

handleStakeResponse : Result Http.Error Pb.StakeResponse -> State -> State
handleStakeResponse res state =
  case res of
    Err e ->
      { state | working = False , notification = Utils.redText (Debug.toString e) }
    Ok resp ->
      case resp.stakeResult of
        Just (Pb.StakeResultOk _) ->
          { state | working = False , notification = H.text "" }
        Just (Pb.StakeResultError e) ->
          { state | working = False , notification = Utils.redText (Debug.toString e) }
        Nothing ->
          { state | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }


view : Config msg -> State -> Html msg
view config state =
  let
    creator = Utils.mustPredictionCreator config.prediction
    certainty = Utils.mustPredictionCertainty config.prediction

    isClosed = Time.posixToMillis state.now > 1000*config.prediction.closesUnixtime
    disableInputs = isClosed || Utils.resolutionIsTerminal (Utils.currentResolution config.prediction)
    creatorStakeFactorVsBelievers = (1 - certainty.high) / certainty.high
    creatorStakeFactorVsSkeptics = certainty.low / (1 - certainty.low)
    maxBelieverStakeCents = if creatorStakeFactorVsBelievers == 0 then 0 else toFloat config.prediction.remainingStakeCentsVsBelievers / creatorStakeFactorVsBelievers + 0.001 |> floor
    maxSkepticStakeCents = if creatorStakeFactorVsSkeptics == 0 then 0 else toFloat config.prediction.remainingStakeCentsVsSkeptics / creatorStakeFactorVsSkeptics + 0.001 |> floor
  in
  H.div []
    [ if certainty.low == 0 then H.text "" else
      let
        ctx = {max=maxSkepticStakeCents}
      in
      H.p []
      [ H.text "Do you ", b "strongly doubt", H.text " that this will happen? Then stake $"
      , Field.inputFor (\s -> config.handle Nevermind {state | skepticStakeField = state.skepticStakeField |> Field.setStr s}) ctx state.skepticStakeField
          H.input
          [ HA.style "width" "5em"
          , HA.type_"number", HA.min "0", HA.max (toFloat maxSkepticStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
          , HA.disabled disableInputs
          ]
          []
      , H.text <| " that it won't, against " ++ creator.displayName ++ "'s "
      , H.strong [] [Field.parse ctx state.skepticStakeField |> Result.map (toFloat >> (*) creatorStakeFactorVsSkeptics >> round >> Utils.formatCents) |> Result.withDefault "???" |> H.text]
      , H.text ". "
      , H.button
          (case Field.parse ctx state.skepticStakeField of
            Ok stake ->
              [ HE.onClick <| config.handle (Staked {bettorIsASkeptic=True, bettorStakeCents=stake}) { state | working = True , notification = H.text ""} ]
            Err _ ->
              [ HA.disabled True ]
          )
          [H.text "Commit"]
      ]
    , if certainty.high == 1 then H.text "" else
      let
        ctx = {max=maxSkepticStakeCents}
      in
      H.p []
      [ H.text "Do you ", b "strongly believe", H.text " that this will happen? Then stake $"
      , Field.inputFor (\s -> config.handle Nevermind {state | believerStakeField = state.believerStakeField |> Field.setStr s}) ctx state.believerStakeField
          H.input
          [ HA.style "width" "5em"
          , HA.type_"number", HA.min "0", HA.max (toFloat maxBelieverStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
          , HA.disabled disableInputs
          ]
          []
      , H.text <| " that it will, against " ++ creator.displayName ++ "'s "
      , H.strong [] [Field.parse ctx state.believerStakeField |> Result.map (toFloat >> (*) creatorStakeFactorVsBelievers >> round >> Utils.formatCents) |> Result.withDefault "???" |> H.text]
      , H.text ". "
      , H.button
          (case Field.parse ctx state.believerStakeField of
            Ok stake ->
              [ HE.onClick <| config.handle (Staked {bettorIsASkeptic=False, bettorStakeCents=stake}) { state | working = True , notification = H.text ""} ]
            Err _ ->
              [ HA.disabled True ]
          )
          [H.text "Commit"]
      ]
    ]

init : State
init =
  let
    parseCents : {max:Int} -> String -> Result String Int
    parseCents {max} s =
      case String.toFloat s of
        Nothing -> Err "must be a number"
        Just dollars ->
          let n = round (100*dollars) in
          if n < 0 || n > max then Err ("must be between $0 and " ++ Utils.formatCents max) else Ok n
  in
  { believerStakeField = Field.init "0" parseCents
  , skepticStakeField = Field.init "0" parseCents
  , now = Time.millisToPosix 0
  , working = False
  , notification = H.text ""
  }

type ReactorMsg = ReactorMsg Event State
main =
  let
    prediction : Pb.UserPredictionView
    prediction =
      { prediction = "at least 50% of U.S. COVID-19 cases will be B117 or a derivative strain, as reported by the CDC"
      , certainty = Just {low = 0.8, high = 0.9}
      , maximumStakeCents = 10000
      , remainingStakeCentsVsBelievers = 10000
      , remainingStakeCentsVsSkeptics = 5000
      , createdUnixtime = 0 -- TODO
      , closesUnixtime = 86400
      , specialRules = "If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the prediction is unresolvable."
      , creator = Just {displayName = "Spencer", isSelf=False, trustsYou=True, isTrusted=True}
      , resolutions = []
      , yourTrades = []
      , resolvesAtUnixtime = 0
      }

  in
  Browser.sandbox
    { init = init
    , view = view {prediction=prediction, handle=ReactorMsg, disableCommit=True}
    , update = \(ReactorMsg event newState) _ -> Debug.log (Debug.toString event) newState
    }
