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
import Utils exposing (must)

epsilon = 0.0000001 -- 🎵 I hate floating-point arithmetic 🎶

type alias Config msg =
  { setState : State -> msg
  , onStake : {bettorIsASkeptic:Bool, bettorStakeCents:Int} -> msg
  , nevermind : msg
  , disableCommit : Bool
  , market : Pb.UserMarketView
  }

type alias State =
  { believerStakeField : String
  , skepticStakeField : String
  , now : Time.Posix
  }

believerStakeCents : State -> Maybe Int
believerStakeCents {believerStakeField} = String.toFloat believerStakeField |> Maybe.map ((*) 100 >> round)
skepticStakeCents : State -> Maybe Int
skepticStakeCents {skepticStakeField} = String.toFloat skepticStakeField |> Maybe.map ((*) 100 >> round)

view : Config msg -> State -> Html msg
view config state =
  let
    creator = config.market.creator |> must "no creator given"
    certainty = config.market.certainty |> must "no certainty given"

    isClosed = Time.posixToMillis state.now > 1000*config.market.closesUnixtime
    disableInputs = isClosed || (config.market.resolution /= Pb.ResolutionNoneYet)
    disableCommit = disableInputs || config.disableCommit
    winCentsIfYes = config.market.yourTrades |> List.map (\t -> if t.bettorIsASkeptic then -t.bettorStakeCents else t.creatorStakeCents) |> List.sum
    winCentsIfNo = config.market.yourTrades |> List.map (\t -> if t.bettorIsASkeptic then t.creatorStakeCents else -t.bettorStakeCents) |> List.sum
    creatorStakeFactorVsBelievers = (1 - certainty.high) / certainty.high
    creatorStakeFactorVsSkeptics = certainty.low / (1 - certainty.low)
    maxBelieverStakeCents = toFloat config.market.remainingStakeCentsVsBelievers / creatorStakeFactorVsBelievers + 0.001 |> floor
    maxSkepticStakeCents = toFloat config.market.remainingStakeCentsVsSkeptics / creatorStakeFactorVsSkeptics + 0.001 |> floor
    (invalidBelieverStake, emphasizeRemainingStakeVsBelievers) = case believerStakeCents state of
      Nothing -> (True, False)
      Just n -> (n < 0 || n > maxBelieverStakeCents, n > maxBelieverStakeCents)
    (invalidSkepticStake, emphasizeRemainingStakeVsSkeptics) = case skepticStakeCents state of
      Nothing -> (True, False)
      Just n -> (n < 0 || n > maxSkepticStakeCents, n > maxSkepticStakeCents)

    _ = Debug.log ""
          { certainty = certainty
          , creatorStakeFactorVsSkeptics = creatorStakeFactorVsSkeptics
          , skepticStakeField = state.skepticStakeField
          , skepticStakeCents = skepticStakeCents state
          , remainingStakeCentsVsSkeptics = config.market.remainingStakeCentsVsSkeptics
          , maxSkepticStakeCents = maxSkepticStakeCents
          }
  in
  H.div []
    [ H.h2 [] [H.text config.market.question]
    , case config.market.resolution of
        Pb.ResolutionYes ->
          if winCentsIfYes == 0 then H.text "" else
          H.div []
            -- TODO: what should we display to the _owner_ of the market, when they view it?
            [ H.text "This market has resolved YES. "
            , H.text <| if winCentsIfYes > 0 then creator.displayName ++ " owes you " else ("you owe " ++ creator.displayName ++ " ")
            , H.text <| Utils.formatCents <| abs winCentsIfYes
            , H.text <| "."
            ]
        Pb.ResolutionNo ->
          if winCentsIfNo == 0 then H.text "" else
          H.div []
            [ H.text "This market has resolved NO. "
            , H.text <| if winCentsIfNo > 0 then creator.displayName ++ " owes you " else ("you owe " ++ creator.displayName ++ " ")
            , H.text <| Utils.formatCents <| abs winCentsIfNo
            , H.text <| "."
            ]
        Pb.ResolutionNoneYet ->
          H.div []
            [ H.text <| "This market " ++ (if isClosed then "has closed, but " else "") ++ "hasn't resolved yet. If it resolves Yes, "
            , H.text <| if winCentsIfYes > 0 then creator.displayName ++ " will owe you " else ("you will owe " ++ creator.displayName ++ " ")
            , H.text <| Utils.formatCents <| abs winCentsIfYes
            , H.text <| "; if No, "
            , H.text <| if winCentsIfNo > 0 then creator.displayName ++ " will owe you " else ("you will owe " ++ creator.displayName ++ " ")
            , H.text <| Utils.formatCents <| abs winCentsIfNo
            , H.text <| "."
            ]
        Pb.ResolutionUnrecognized_ _ ->
          H.span [HA.style "color" "red"]
            [H.text "Oh dear, something has gone very strange with this market. Please email TODO with this URL to report it!"]
    , H.hr [] []
    , H.p []
        [ H.text creator.displayName
        , H.text " assigned this a "
        , certainty.low |> (*) 100 |> round |> String.fromInt |> H.text
        , H.text "-"
        , certainty.high |> (*) 100 |> round |> String.fromInt |> H.text
        , H.text "% chance, and staked "
        , config.market.maximumStakeCents |> Utils.formatCents |> H.text
        , H.text "."
        , H.br [] []
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeVsSkeptics] [config.market.remainingStakeCentsVsSkeptics |> Utils.formatCents |> H.text]
        , H.text " remain staked against skeptics, "
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeVsBelievers] [config.market.remainingStakeCentsVsBelievers |> Utils.formatCents |> H.text]
        , H.text " remain staked against believers."
        , H.br [] []
        , H.text "Market opened "
        , config.market.createdUnixtime |> (*) 1000 |> Time.millisToPosix
            |> (\t -> "[TODO: " ++ Debug.toString t ++ "]")
            |> H.text
        , H.text ", closes "
        , config.market.closesUnixtime |> (*) 1000 |> Time.millisToPosix
            |> (\t -> "[TODO: " ++ Debug.toString t ++ "]")
            |> H.text
        ]
    , H.p []
        [ H.text "Bet $"
        , H.input
            [ HA.style "width" "5em"
            , HA.type_"number", HA.min "0", HA.max (toFloat maxSkepticStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
            , HA.value state.skepticStakeField
            , HE.onInput (\s -> config.setState {state | skepticStakeField = s})
            , HA.disabled disableInputs
            , Utils.outlineIfInvalid invalidSkepticStake
            ] []
        , H.text " that this will resolve No, against Spencer's "
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeVsSkeptics] [skepticStakeCents state |>  Maybe.map (toFloat >> (*) creatorStakeFactorVsSkeptics >> round >> Utils.formatCents) |> Maybe.withDefault "???" |> H.text]
        , H.text "? "
        , H.button
          [ HA.disabled (invalidSkepticStake || disableCommit)
          , HE.onClick <|
              case skepticStakeCents state of
                Just stake -> config.onStake {bettorIsASkeptic=True, bettorStakeCents=stake}
                Nothing -> config.nevermind
          ]
          [H.text "Commit"]
        , H.br [] []
        , H.text "Bet $"
                , H.input
            [ HA.style "width" "5em"
            , HA.type_"number", HA.min "0", HA.max (toFloat maxBelieverStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
            , HA.value state.believerStakeField
            , HE.onInput (\s -> config.setState {state | believerStakeField = s})
            , HA.disabled disableInputs
            , Utils.outlineIfInvalid invalidBelieverStake
            ] []
        , H.text " that this will resolve Yes, against Spencer's "
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeVsBelievers] [believerStakeCents state |>  Maybe.map (toFloat >> (*) creatorStakeFactorVsBelievers >> round >> Utils.formatCents) |> Maybe.withDefault "???" |> H.text]
        , H.text "? "
        , H.button
          [ HA.disabled (invalidBelieverStake || disableCommit)
          , HE.onClick <|
              case believerStakeCents state of
                Just stake -> config.onStake {bettorIsASkeptic=False, bettorStakeCents=stake}
                Nothing -> config.nevermind
          ]
          [H.text "Commit"]
        ]
    ]

init : State
init =
  { believerStakeField = "0"
  , skepticStakeField = "0"
  , now = Time.millisToPosix 0
  }

type MsgForDemo = SetState State | Ignore
main : Program () State MsgForDemo
main =
  let
    market : Pb.UserMarketView
    market =
      { question = "By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?"
      , certainty = Just {low = 0.8, high = 0.9}
      , maximumStakeCents = 10000
      , remainingStakeCentsVsBelievers = 10000
      , remainingStakeCentsVsSkeptics = 5000
      , createdUnixtime = 0 -- TODO
      , closesUnixtime = 86400
      , specialRules = "If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable."
      , creator = Just {displayName = "Spencer", isSelf=False}
      , resolution = Pb.ResolutionNoneYet
      , yourTrades = []
      }
  in
  Browser.sandbox
    { init = init
    , view = view {market=market, onStake = (\_ -> Ignore), nevermind=Ignore, setState=SetState, disableCommit=True}
    , update = \msg model -> case msg of
        Ignore -> model
        SetState newState -> newState
    }