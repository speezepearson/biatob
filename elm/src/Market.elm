module Market exposing  (Config, State, view)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Time
import Html exposing (s)

import Biatob.Proto.Mvp as Pb
import Utils exposing (they, them, their, pluralize, capitalize, must)
import Utils

epsilon = 0.0000001 -- 🎵 I hate floating-point arithmetic 🎶

type alias Config msg =
  { setState : State -> msg
  , onStake : Bool -> Float -> msg
  , nevermind : msg
  }

type alias State =
  { market : Pb.GetMarketResponseMarket
  , userPosition : Pb.Position
  , stakeYesField : String
  , stakeNoField : String
  , now : Time.Posix
  }

view : Config msg -> State -> Html msg
view config state =
  let
    creator = state.market.creator |> must "no creator given"
    certainty = state.market.certainty |> must "no certainty given"

    yesStakeMultiplier = Debug.log (Debug.toString certainty) (1 - certainty.high) / certainty.high
    noStakeMultiplier = certainty.low / (1 - certainty.low)
    maxYesStake = state.market.remainingYesStake / yesStakeMultiplier
    maxNoStake = state.market.remainingNoStake / noStakeMultiplier
    (invalidStakeYes, emphasizeRemainingStakeYes) = case String.toFloat state.stakeYesField of
      Nothing -> (True, False)
      Just n -> (n < 0 || n > maxYesStake + epsilon, n > maxYesStake + epsilon)
    (invalidStakeNo, emphasizeRemainingStakeNo) = case String.toFloat state.stakeNoField of
      Nothing -> (True, False)
      Just n -> (n < 0 || n > maxNoStake + epsilon, n > maxNoStake + epsilon)
  in
  H.div []
    [ H.h2 [] [H.text state.market.question]
    , case state.market.resolution of
        Pb.ResolutionYes ->
          let winnings = state.userPosition.winningsIfYes in
          if winnings == 0 then H.text "" else
          H.div []
            [ H.text "This market has resolved YES. You "
            , H.text <| if winnings > 0 then "are owed " else "owe "
            , H.text <| Utils.formatDollars <| abs winnings
            , H.text <| "."
            ]
        Pb.ResolutionNo ->
          let winnings = state.userPosition.winningsIfNo in
          if winnings == 0 then H.text "" else
          H.div []
            [ H.text "This market has resolved NO. You "
            , H.text <| if winnings > 0 then "are owed " else "owe "
            , H.text <| Utils.formatDollars <| abs winnings
            , H.text <| "."
            ]
        Pb.ResolutionNoneYet ->
          H.div []
            [ H.text "This market hasn't resolved yet. If it resolves Yes, you will "
            , H.text <| if state.userPosition.winningsIfYes > 0 then "be owed " else "owe "
            , H.text <| Utils.formatDollars <| abs state.userPosition.winningsIfYes
            , H.text <| "; if No, you will "
            , H.text <| if state.userPosition.winningsIfNo > 0 then "be owed " else "owe "
            , H.text <| Utils.formatDollars <| abs state.userPosition.winningsIfNo
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
        , state.market.maximumStake |> Utils.formatDollars |> H.text
        , H.text "."
        , H.br [] []
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeYes] [state.market.remainingYesStake |> Utils.formatDollars |> H.text]
        , H.text " remain staked on Yes, "
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeNo] [state.market.remainingNoStake |> Utils.formatDollars |> H.text]
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
            , HA.type_"number", HA.min "0", HA.max (maxYesStake |> (+) epsilon |> String.fromFloat), HA.step "any"
            , HA.value state.stakeYesField
            , HE.onInput (\s -> config.setState {state | stakeYesField = s})
            , Utils.outlineIfInvalid invalidStakeYes
            ] []
        , H.text " against Spencer's "
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeYes] [state.stakeYesField |> String.toFloat |>  Maybe.map ((*) yesStakeMultiplier >> Utils.formatDollars) |> Maybe.withDefault "???" |> H.text]
        , H.text " that this will resolve Yes? "
        , H.button
          [ HE.onClick <|
              case String.toFloat state.stakeYesField of
                Just stake -> config.onStake True stake
                Nothing -> config.nevermind
          ]
          [H.text "Commit"]
        , H.br [] []
        , H.text "Stake $"
        , H.input
            [ HA.style "width" "5em"
            , HA.type_"number", HA.min "0", HA.max (maxNoStake |> (+) epsilon |> String.fromFloat), HA.step "any"
            , HA.value state.stakeNoField
            , HE.onInput (\s -> config.setState {state | stakeNoField = s})
            , Utils.outlineIfInvalid invalidStakeNo
            ] []
        , H.text " against Spencer's "
        , H.strong [Utils.outlineIfInvalid emphasizeRemainingStakeNo] [state.stakeNoField |> String.toFloat |>  Maybe.map ((*) noStakeMultiplier >> Utils.formatDollars) |> Maybe.withDefault "???" |> H.text]
        , H.text " that this will resolve No? "
        , H.button
          [ HE.onClick <|
              case String.toFloat state.stakeNoField of
                Just stake -> config.onStake False stake
                Nothing -> config.nevermind
          ]
          [H.text "Commit"]
        ]
    ]

initStateForDemo : State
initStateForDemo =
  { market =
      { question = "By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?"
      , certainty = Just {low = 0.8, high = 0.9}
      , maximumStake = 100
      , remainingYesStake = 100
      , remainingNoStake = 50
      , createdUnixtime = 0 -- TODO
      , closesUnixtime = 86400
      , specialRules = "If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable."
      , creator = Just {displayName = "Spencer" , pronouns = Pb.HeHim} -- TODO
      , resolution = Pb.ResolutionNoneYet
      }
  , userPosition = { winningsIfYes = -5 , winningsIfNo = 8 }
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
