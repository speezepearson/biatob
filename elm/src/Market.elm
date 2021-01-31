module Market exposing
  ( Config
  , State
  , view
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
  , onStake : Bool -> Int -> msg
  , nevermind : msg
  }

type alias State =
  { market : Pb.GetMarketResponseMarket
  , believerStakeField : String
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
    creator = state.market.creator |> must "no creator given"
    certainty = state.market.certainty |> must "no certainty given"

    winCentsIfYes = state.market.yourTrades |> List.map (\t -> if t.bettorIsASkeptic then -t.bettorStakeCents else t.creatorStakeCents) |> List.sum
    winCentsIfNo = state.market.yourTrades |> List.map (\t -> if t.bettorIsASkeptic then t.creatorStakeCents else -t.bettorStakeCents) |> List.sum
    creatorStakeFactorVsBelievers = (1 - certainty.high) / certainty.high
    creatorStakeFactorVsSkeptics = certainty.low / (1 - certainty.low)
    maxBelieverStakeCents = toFloat state.market.remainingStakeCentsVsBelievers / creatorStakeFactorVsBelievers |> floor
    maxSkepticStakeCents = toFloat state.market.remainingStakeCentsVsSkeptics / creatorStakeFactorVsSkeptics |> floor
    (invalidBelieverStake, emphasizeRemainingStakeVsBelievers) = case believerStakeCents state of
      Nothing -> (True, False)
      Just n -> (n < 0 || n > maxBelieverStakeCents, n > maxBelieverStakeCents)
    (invalidSkepticStake, emphasizeRemainingStakeVsSkeptics) = case skepticStakeCents state of
      Nothing -> (True, False)
      Just n -> (n < 0 || n > maxSkepticStakeCents, n > maxSkepticStakeCents)

    _ = Debug.log ""
          { skepticStakeField = state.skepticStakeField
          , skepticStakeCents = skepticStakeCents state
          , remainingStakeCentsVsSkeptics = state.market.remainingStakeCentsVsSkeptics
          , maxSkepticStakeCents = maxSkepticStakeCents
          }
  in
  H.div []
    [ H.h2 [] [H.text state.market.question]
    , case state.market.resolution of
        Pb.ResolutionYes ->
          if winCentsIfYes == 0 then H.text "" else
          H.div []
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
            [ H.text "This market hasn't resolved yet. If it resolves Yes, "
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
        , state.market.maximumStakeCents |> Utils.formatCents |> H.text
        , H.text "."
        , H.br [] []
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeVsSkeptics] [state.market.remainingStakeCentsVsSkeptics |> Utils.formatCents |> H.text]
        , H.text " remain staked against skeptics, "
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeVsBelievers] [state.market.remainingStakeCentsVsBelievers |> Utils.formatCents |> H.text]
        , H.text " remain staked against believers."
        , H.br [] []
        , H.text "Market opened "
        , state.market.createdUnixtime |> (*) 1000 |> Time.millisToPosix
            |> (\t -> "[TODO: " ++ Debug.toString t ++ "]")
            |> H.text
        , H.text ", closes "
        , state.market.closesUnixtime |> (*) 1000 |> Time.millisToPosix
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
            , Utils.outlineIfInvalid invalidSkepticStake
            ] []
        , H.text " that this will resolve No, against Spencer's "
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeVsSkeptics] [skepticStakeCents state |>  Maybe.map (toFloat >> (*) creatorStakeFactorVsSkeptics >> round >> Utils.formatCents) |> Maybe.withDefault "???" |> H.text]
        , H.text "? "
        , H.button
          [ HE.onClick <|
              case believerStakeCents state of
                Just stake -> config.onStake False stake
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
            , Utils.outlineIfInvalid invalidBelieverStake
            ] []
        , H.text " that this will resolve Yes, against Spencer's "
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeVsBelievers] [believerStakeCents state |>  Maybe.map (toFloat >> (*) creatorStakeFactorVsBelievers >> round >> Utils.formatCents) |> Maybe.withDefault "???" |> H.text]
        , H.text "? "
        , H.button
          [ HE.onClick <|
              case believerStakeCents state of
                Just stake -> config.onStake True stake
                Nothing -> config.nevermind
          ]
          [H.text "Commit"]
        ]
    ]

initStateForDemo : State
initStateForDemo =
  let
      market : Pb.GetMarketResponseMarket
      market = 
        { question = "By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?"
        , certainty = Just {low = 0.8, high = 0.9}
        , maximumStakeCents = 10000
        , remainingStakeCentsVsBelievers = 10000
        , remainingStakeCentsVsSkeptics = 5000
        , createdUnixtime = 0 -- TODO
        , closesUnixtime = 86400
        , specialRules = "If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable."
        , creator = Just {displayName = "Spencer"}
        , resolution = Pb.ResolutionNoneYet
        , yourTrades = []
        }
  in
    { market = market
    , believerStakeField = "0"
    , skepticStakeField = "0"
    , now = Time.millisToPosix 0
    }
type MsgForDemo = SetState State | Ignore
main : Program () State MsgForDemo
main =
  Browser.sandbox
    { init = initStateForDemo
    , view = view {onStake = (\_ _ -> Ignore), nevermind=Ignore, setState = SetState}
    , update = \msg model -> case msg of
        Ignore -> model
        SetState newState -> newState
    }
