module Market exposing  (Config, State, view )

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Time
import Html exposing (s)

import Biatob.Proto.Mvp as Pb
import Utils exposing (they, them, their, pluralize, must, logoddsToProb)

type alias Config msg =
  { setState : State -> msg
  , onStake : Bool -> Float -> msg
  , nevermind : msg
  }

type alias State =
  { market : Pb.GetMarketResponseMarket
  , stakeFields : { yes : String , no : String }
  , now : Time.Posix
  }

view : Config msg -> State -> Html msg
view config state =

  H.div []
    [ H.h2 [] [H.text state.market.question]
    , H.p []
        [ H.text (must "no creator given" state.market.creator).displayName
        , H.text " assigned this a "
        , state.market.certainty |> must "no certainty given" |> .lowLogodds  |> logoddsToProb |> (*) 100 |> round |> String.fromInt |> H.text
        , H.text "-"
        , state.market.certainty |> must "no certainty given" |> .highLogodds |> logoddsToProb |> (*) 100 |> round |> String.fromInt |> H.text
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
            , HA.type_"number", HA.min "0"
            , HA.value state.stakeFields.yes
            ] []
        , H.text " against Spencer's "
        , H.strong [] [H.text "TODO"]
        , H.text " that this will resolve Yes? "
        , H.button
          [ HE.onClick <|
              case String.toFloat state.stakeFields.yes of
                Just stake -> config.onStake True stake
                Nothing -> config.nevermind
          ]
          [H.text "Commit"]
        , H.br [] []
        , H.text "Stake $"
        , H.input
            [ HA.style "width" "5em"
            , HA.type_"number", HA.min "0"
            , HA.value state.stakeFields.no
            ] []
        , H.text " against Spencer's "
        , H.strong [] [H.text "TODO"]
        , H.text " that this will resolve No? "
        , H.button
          [ HE.onClick <|
              case String.toFloat state.stakeFields.no of
                Just stake -> config.onStake False stake
                Nothing -> config.nevermind
          ]
          [H.text "Commit"]
        ]
    ]
