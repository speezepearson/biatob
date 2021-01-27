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
  , userPosition : Pb.Position
  , stakeYesField : String
  , stakeNoField : String
  , now : Time.Posix
  }

stakeYesCents : State -> Maybe Int
stakeYesCents {stakeYesField} = String.toFloat stakeYesField |> Maybe.map ((*) 100 >> round)
stakeNoCents : State -> Maybe Int
stakeNoCents {stakeNoField} = String.toFloat stakeNoField |> Maybe.map ((*) 100 >> round)

view : Config msg -> State -> Html msg
view config state =
  let
    creator = state.market.creator |> must "no creator given"
    certainty = state.market.certainty |> must "no certainty given"

    yesStakeMultiplier = (1 - certainty.high) / certainty.high
    noStakeMultiplier = certainty.low / (1 - certainty.low)
    maxYesStakeCents = toFloat state.market.remainingYesStakeCents / yesStakeMultiplier |> round
    maxNoStakeCents = toFloat state.market.remainingNoStakeCents / noStakeMultiplier |> round
    (invalidStakeYes, emphasizeRemainingStakeYes) = case stakeYesCents state of
      Nothing -> (True, False)
      Just n -> (n < 0 || n > maxYesStakeCents, n > maxYesStakeCents)
    (invalidStakeNo, emphasizeRemainingStakeNo) = case stakeNoCents state of
      Nothing -> (True, False)
      Just n -> (n < 0 || n > maxNoStakeCents, n > maxNoStakeCents)
  in
  H.div []
    [ H.h2 [] [H.text state.market.question]
    , case state.market.resolution of
        Pb.ResolutionYes ->
          let winnings = state.userPosition.winCentsIfYes in
          if winnings == 0 then H.text "" else
          H.div []
            [ H.text "This market has resolved YES. "
            , H.text <| if winnings > 0 then creator.displayName ++ " owes you " else ("you owe " ++ creator.displayName ++ " ")
            , H.text <| Utils.formatCents <| abs winnings
            , H.text <| "."
            ]
        Pb.ResolutionNo ->
          let winnings = state.userPosition.winCentsIfNo in
          if winnings == 0 then H.text "" else
          H.div []
            [ H.text "This market has resolved NO. "
            , H.text <| if winnings > 0 then creator.displayName ++ " owes you " else ("you owe " ++ creator.displayName ++ " ")
            , H.text <| Utils.formatCents <| abs winnings
            , H.text <| "."
            ]
        Pb.ResolutionNoneYet ->
          H.div []
            [ H.text "This market hasn't resolved yet. If it resolves Yes, "
            , H.text <| if state.userPosition.winCentsIfYes > 0 then creator.displayName ++ " will owe you " else ("you will owe " ++ creator.displayName ++ " ")
            , H.text <| Utils.formatCents <| abs state.userPosition.winCentsIfYes
            , H.text <| "; if No, "
            , H.text <| if state.userPosition.winCentsIfNo > 0 then creator.displayName ++ " will owe you " else ("you will owe " ++ creator.displayName ++ " ")
            , H.text <| Utils.formatCents <| abs state.userPosition.winCentsIfNo
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
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeYes] [state.market.remainingYesStakeCents |> Utils.formatCents |> H.text]
        , H.text " remain staked on Yes, "
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeNo] [state.market.remainingNoStakeCents |> Utils.formatCents |> H.text]
        , H.text " remain staked on No."
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
        [ H.text "Stake $"
        , H.input
            [ HA.style "width" "5em"
            , HA.type_"number", HA.min "0", HA.max (toFloat maxYesStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
            , HA.value state.stakeYesField
            , HE.onInput (\s -> config.setState {state | stakeYesField = s})
            , Utils.outlineIfInvalid invalidStakeYes
            ] []
        , H.text " against Spencer's "
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeYes] [stakeYesCents state |>  Maybe.map (toFloat >> (*) yesStakeMultiplier >> round >> Utils.formatCents) |> Maybe.withDefault "???" |> H.text]
        , H.text " that this will resolve Yes? "
        , H.button
          [ HE.onClick <|
              case stakeYesCents state of
                Just stake -> config.onStake True stake
                Nothing -> config.nevermind
          ]
          [H.text "Commit"]
        , H.br [] []
        , H.text "Stake $"
        , H.input
            [ HA.style "width" "5em"
            , HA.type_"number", HA.min "0", HA.max (toFloat maxNoStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
            , HA.value state.stakeNoField
            , HE.onInput (\s -> config.setState {state | stakeNoField = s})
            , Utils.outlineIfInvalid invalidStakeNo
            ] []
        , H.text " against Spencer's "
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeNo] [stakeNoCents state |>  Maybe.map (toFloat >> (*) noStakeMultiplier >> round >> Utils.formatCents) |> Maybe.withDefault "???" |> H.text]
        , H.text " that this will resolve No? "
        , H.button
          [ HE.onClick <|
              case stakeYesCents state of
                Just stake -> config.onStake False stake
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
        , remainingYesStakeCents = 10000
        , remainingNoStakeCents = 5000
        , createdUnixtime = 0 -- TODO
        , closesUnixtime = 86400
        , specialRules = "If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable."
        , creator = Just {displayName = "Spencer", pronouns = Pb.HeHim}
        , resolution = Pb.ResolutionNoneYet
        }
  in
    { market = market
    , userPosition = { winCentsIfYes = -500 , winCentsIfNo = 800 }
    , stakeYesField = "0"
    , stakeNoField = "0"
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
