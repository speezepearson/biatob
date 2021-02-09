module StakeForm exposing
  ( Config
  , State
  , view
  , init
  , main
  )

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Time
import Html exposing (s)

import Biatob.Proto.Mvp as Pb
import Utils
import Html exposing (a)

import Field exposing (Field)

epsilon = 0.0000001 -- 🎵 I hate floating-point arithmetic 🎶

type alias Config msg =
  { setState : State -> msg
  , onStake : {bettorIsASkeptic:Bool, bettorStakeCents:Int} -> msg
  , nevermind : msg
  , disableCommit : Bool
  , market : Pb.UserMarketView
  }

type alias State =
  { believerStakeField : Field {max : Int} Int
  , skepticStakeField : Field {max : Int} Int
  , now : Time.Posix
  }
-- believerStakeCents : State -> Maybe Int
-- believerStakeCents {believerStakeField} = String.toFloat believerStakeField |> Maybe.map ((*) 100 >> round)
-- skepticStakeCents : State -> Maybe Int
-- skepticStakeCents {skepticStakeField} = String.toFloat skepticStakeField |> Maybe.map ((*) 100 >> round)

view : Config msg -> State -> Html msg
view config state =
  let
    creator = Utils.mustMarketCreator config.market
    certainty = Utils.mustMarketCertainty config.market

    isClosed = Time.posixToMillis state.now > 1000*config.market.closesUnixtime
    disableInputs = isClosed || Utils.resolutionIsTerminal (Utils.currentResolution config.market)
    disableCommit = disableInputs || config.disableCommit
    winCentsIfYes = config.market.yourTrades |> List.map (\t -> if t.bettorIsASkeptic then -t.bettorStakeCents else t.creatorStakeCents) |> List.sum
    winCentsIfNo = config.market.yourTrades |> List.map (\t -> if t.bettorIsASkeptic then t.creatorStakeCents else -t.bettorStakeCents) |> List.sum
    creatorStakeFactorVsBelievers = (1 - certainty.high) / certainty.high
    creatorStakeFactorVsSkeptics = certainty.low / (1 - certainty.low)
    maxBelieverStakeCents = if creatorStakeFactorVsBelievers == 0 then 0 else toFloat config.market.remainingStakeCentsVsBelievers / creatorStakeFactorVsBelievers + 0.001 |> floor
    maxSkepticStakeCents = if creatorStakeFactorVsSkeptics == 0 then 0 else toFloat config.market.remainingStakeCentsVsSkeptics / creatorStakeFactorVsSkeptics + 0.001 |> floor
  in
  H.div []
    [ H.text <| "Do you think " ++ creator.displayName ++ " is..."
    , H.ul []
        [ H.li [] <|
            let
              ctx = {max=maxSkepticStakeCents}
            in
              [ H.strong [] [H.text "...too skeptical?"]
              , H.text " Then stake $"
              , Field.inputFor (\s -> config.setState {state | skepticStakeField = state.skepticStakeField |> Field.setStr s}) ctx state.skepticStakeField
                  H.input
                  [ HA.style "width" "5em"
                  , HA.type_"number", HA.min "0", HA.max (toFloat maxSkepticStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
                  , HA.disabled disableInputs
                  ]
                  []
              , H.text <| " (against their "
              , H.strong [] [Field.parse ctx state.skepticStakeField |> Result.map (toFloat >> (*) creatorStakeFactorVsSkeptics >> round >> Utils.formatCents) |> Result.withDefault "???" |> H.text]
              , H.text ") that they're wrong. "
              , H.button
                  (case Field.parse ctx state.skepticStakeField of
                    Ok stake ->
                      [ HE.onClick <| config.onStake {bettorIsASkeptic=True, bettorStakeCents=stake} ]
                    Err _ ->
                      [ HA.disabled True ]
                  )
                  [H.text "Commit"]
              ]
        , H.li [] <|
            let
              ctx = {max=maxSkepticStakeCents}
            in
              [ H.strong [] [H.text "...too credulous?"]
              , H.text " Then stake $"
              , Field.inputFor (\s -> config.setState {state | believerStakeField = state.believerStakeField |> Field.setStr s}) ctx state.believerStakeField
                  H.input
                  [ HA.style "width" "5em"
                  , HA.type_"number", HA.min "0", HA.max (toFloat maxBelieverStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
                  , HA.disabled disableInputs
                  ]
                  []
              , H.text <| " (against their " ++ creator.displayName ++ " "
              , H.strong [] [Field.parse ctx state.believerStakeField |> Result.map (toFloat >> (*) creatorStakeFactorVsBelievers >> round >> Utils.formatCents) |> Result.withDefault "???" |> H.text]
              , H.text ") that this will happen. "
              , H.button
                  (case Field.parse ctx state.believerStakeField of
                    Ok stake ->
                      [ HE.onClick <| config.onStake {bettorIsASkeptic=False, bettorStakeCents=stake} ]
                    Err _ ->
                      [ HA.disabled True ]
                  )
                  [H.text "Commit"]
              ]
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
  { believerStakeField = { string = "0" , parse = parseCents }
  , skepticStakeField = { string = "0" , parse = parseCents }
  , now = Time.millisToPosix 0
  }

type MsgForDemo = SetState State | Ignore
main : Program () State MsgForDemo
main =
  let
    market : Pb.UserMarketView
    market =
      { prediction = "at least 50% of U.S. COVID-19 cases will be B117 or a derivative strain, as reported by the CDC"
      , certainty = Just {low = 0.8, high = 0.9}
      , maximumStakeCents = 10000
      , remainingStakeCentsVsBelievers = 10000
      , remainingStakeCentsVsSkeptics = 5000
      , createdUnixtime = 0 -- TODO
      , closesUnixtime = 86400
      , specialRules = "If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable."
      , creator = Just {displayName = "Spencer", isSelf=False, trustsYou=True, isTrusted=True}
      , resolutions = []
      , yourTrades = []
      , resolvesAtUnixtime = 0
      }
  in
  Browser.sandbox
    { init = init
    , view = view {market=market, onStake = (\_ -> Ignore), nevermind=Ignore, setState=SetState, disableCommit=True}
    , update = \msg model -> case msg of
        Ignore -> model
        SetState newState -> newState
    }
