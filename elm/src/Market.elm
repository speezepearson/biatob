module Market exposing  (Config, State, view)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Time
import Html exposing (s)

import Biatob.Proto.Mvp as Pb
import Utils exposing (they, them, their, pluralize, must)

type alias Config msg =
  { setState : State -> msg
  , onStake : Bool -> Float -> msg
  , nevermind : msg
  }

type alias State =
  { market : Pb.GetMarketResponseMarket
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
    maxYesStake = state.market.maximumStake / yesStakeMultiplier |> floor
    maxNoStake = state.market.maximumStake / noStakeMultiplier |> floor
    invalidStakeYes = state.stakeYesField |> String.toInt |> Maybe.map (\n -> n < 0 || n > maxYesStake) |> Maybe.withDefault True
    invalidStakeNo = state.stakeNoField |> String.toInt |> Maybe.map (\n -> n < 0 || n > maxNoStake) |> Maybe.withDefault True
  in
  H.div []
    [ H.h2 [] [H.text state.market.question]
    , H.p []
        [ H.text creator.displayName
        , H.text " assigned this a "
        , certainty.low |> (*) 100 |> round |> String.fromInt |> H.text
        , H.text "-"
        , certainty.high |> (*) 100 |> round |> String.fromInt |> H.text
        , H.text "% chance, and staked $"
        , state.market.maximumStake |> round |> String.fromInt |> H.text
        , H.text "."
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
            , HA.type_"number", HA.min "0", HA.max (maxYesStake |> String.fromInt)
            , HA.value state.stakeYesField
            , HE.onInput (\s -> config.setState {state | stakeYesField = s})
            , Utils.outlineIfInvalid invalidStakeYes
            ] []
        , H.text " against Spencer's "
        , H.strong [] [H.text "$", state.stakeYesField |> String.toFloat |> Maybe.map ((*) yesStakeMultiplier >> min state.market.maximumStake >> floor >> String.fromInt) |> Maybe.withDefault "???" |> H.text]
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
            , HA.type_"number", HA.min "0", HA.max (maxNoStake |> String.fromInt)
            , HA.value state.stakeNoField
            , HE.onInput (\s -> config.setState {state | stakeNoField = s})
            , Utils.outlineIfInvalid invalidStakeNo
            ] []
        , H.text " against Spencer's "
        , H.strong [] [H.text "$", state.stakeNoField |> String.toFloat |> Maybe.map ((*) noStakeMultiplier >> min state.market.maximumStake >> floor >> String.fromInt) |> Maybe.withDefault "???" |> H.text]
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
      , remainingNoStake = 100
      , createdUnixtime = 0 -- TODO
      , closesUnixtime = 86400
      , specialRules = "If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable."
      , creator = Just {displayName = "Spencer" , pronouns = Pb.HeHim} -- TODO
      }
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
