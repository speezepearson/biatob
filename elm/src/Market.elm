module Market exposing  (Config, State, view )

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
    maxYesStake = state.market.maximumStake / yesStakeMultiplier |> round
    maxNoStake = state.market.maximumStake / noStakeMultiplier |> round
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
        , H.strong [] [H.text "$", state.stakeYesField |> String.toFloat |> Maybe.map ((*) yesStakeMultiplier >> min state.market.maximumStake >> round >> String.fromInt) |> Maybe.withDefault "???" |> H.text]
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
        , H.strong [] [H.text "$", state.stakeNoField |> String.toFloat |> Maybe.map ((*) noStakeMultiplier >> min state.market.maximumStake >> round >> String.fromInt) |> Maybe.withDefault "???" |> H.text]
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
