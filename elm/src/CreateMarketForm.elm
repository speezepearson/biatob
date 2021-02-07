module CreateMarketForm exposing
  ( State
  , Config
  , view
  , init
  , main
  , toCreateRequest
  )

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Utils

import Field exposing (Field)
import Biatob.Proto.Mvp as Pb
import Field

howToWriteGoodBetsUrl = "http://example.com/TODO"
maxLegalStakeCents = 500000

type alias Config msg =
  { setState : State -> msg
  , disabled : Bool
  }

type OpenForUnit = Days | Weeks
unitToSeconds : OpenForUnit -> Int
unitToSeconds u =
  case u of
    Days -> 60 * 60 * 24
    Weeks -> unitToSeconds Days * 7

type alias State =
  { questionField : Field () String
  , stakeField : Field () Int
  , lowPField : Field () Float
  , highPField : Field {lowP:Float} Float
  , openForUnitField : Field () OpenForUnit
  , openForSecondsField : Field {unit:OpenForUnit} Int
  , specialRulesField : Field () String
  }

toCreateRequest : State -> Maybe Pb.CreateMarketRequest
toCreateRequest state =
  Field.parse () state.questionField |> Result.andThen (\question ->
  Field.parse () state.stakeField |> Result.andThen (\stake ->
  Field.parse () state.lowPField |> Result.andThen (\lowP ->
  Field.parse {lowP=lowP} state.highPField |> Result.andThen (\highP ->
  Field.parse () state.openForUnitField |> Result.andThen (\unit ->
  Field.parse {unit=unit} state.openForSecondsField |> Result.andThen (\openForSeconds ->
  Field.parse () state.specialRulesField |> Result.andThen (\specialRules ->
    Ok
      { question = question
      , privacy = Nothing  -- TODO: delete this field
      , certainty = Just { low=lowP, high=highP }
      , maximumStakeCents = stake
      , openSeconds = openForSeconds
      , specialRules = specialRules
      }
  )))))))
  |> Result.toMaybe

view : Config msg -> State -> Html msg
view config state =
  let
    outlineIfInvalid b = Utils.outlineIfInvalid (b && not config.disabled)
    highPCtx = {lowP = Field.parse () state.lowPField |> Result.withDefault 0}
    openForSecondsCtx = {unit = Field.parse () state.openForUnitField |> Result.withDefault Days}
    placeholders =
      { question = "By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?"
      , stake = "100"
      , specialRules = "If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable."
      }
  in
  H.div []
    [ H.ul []
        [ H.li []
            [ H.text "What prediction are you willing to stake money on? ("
            , H.a [HA.href howToWriteGoodBetsUrl] [H.text "how to write good bets"]
            , H.text ") "
            , H.br [] []
            , Field.inputFor (\s -> config.setState {state | questionField = state.questionField |> Field.setStr s}) () state.questionField
                H.input
                [ HA.style "width" "100%"
                , HA.placeholder placeholders.question
                , HA.disabled config.disabled
                ] []
            ]
        , H.li []
            [ H.text "How much are you willing to stake? $"
            , Field.inputFor (\s -> config.setState {state | stakeField = state.stakeField |> Field.setStr s}) () state.stakeField
                H.input
                [ HA.type_ "number", HA.min "0", HA.max (String.fromInt maxLegalStakeCents)
                , HA.placeholder placeholders.stake
                , HA.disabled config.disabled
                ] []
            ]
        , H.li []
            [ H.text "How much would you be willing to pay if your most well-informed friend offered you an IOU that paid out..."
            , H.ul []
                [ H.li []
                  [ H.text "...$100 if this "
                  , H.strong [] [H.text "happens?"]
                  , H.text " $"

                  , Field.inputFor (\s -> config.setState {state | lowPField = state.lowPField |> Field.setStr s}) () state.lowPField
                      H.input
                      [ HA.type_ "number", HA.min "0", HA.max "100"
                      , HA.style "width" "5em"
                      , HA.disabled config.disabled
                      ] []
                  ]
                , H.li []
                  [ H.text "...$100 if this "
                  , H.strong [] [H.text "doesn't happen?"]
                  , H.text " $"
                  , Field.inputFor (\s -> config.setState {state | highPField = state.highPField |> Field.setStr s}) highPCtx state.highPField
                      H.input
                      [ HA.type_ "number", HA.min "0", HA.max (String.fromFloat <| Result.withDefault 100 <| Result.map (\n -> 99.999 - n) <| Field.parse highPCtx state.highPField)
                      , HA.style "width" "5em"
                      , HA.disabled config.disabled
                      ] []
                  ]
                ]
            , H.text "In other words, you think that this is "
            , H.strong []
                [ case Field.parse () state.lowPField of
                    Err _ -> H.text "???"
                    Ok p -> H.text <| String.fromInt <| round (100*p)
                , H.text "-"
                , case Field.parse highPCtx state.highPField of
                    Err _ -> H.text "???"
                    Ok p -> H.text <| String.fromInt <| round (100*p)
                , H.text "%"
                ]
            , H.text " likely."
            ]
        , H.li []
            [ H.text "How long is this offer open for?"
            , Field.inputFor (\s -> config.setState {state | openForSecondsField = state.openForSecondsField |> Field.setStr s}) {unit=Field.parse () state.openForUnitField |> Result.withDefault Weeks} state.openForSecondsField
                H.input
                [ HA.type_ "number", HA.min "1"
                , HA.style "width" "5em"
                , HA.disabled config.disabled
                ] []
            , Field.inputFor (\s -> config.setState {state | openForUnitField = state.openForUnitField |> Field.setStr s}) () state.openForUnitField
                H.select
                [ HA.disabled config.disabled
                ]
                [ H.option [] [H.text "weeks"]
                , H.option [] [H.text "days"]
                ]
            ]
        , H.li []
            [ H.text "Any special rules? (For instance: what might make you consider the market unresolvable/invalid? What would you count as \"insider trading\"/cheating?)"
            , Field.inputFor (\s -> config.setState {state | specialRulesField = state.specialRulesField |> Field.setStr s}) () state.specialRulesField
                H.textarea
                [ HA.style "width" "100%"
                , HA.placeholder placeholders.specialRules
                , HA.disabled config.disabled
                ]
                []
            ]
        ]
    ]

init : State
init =
  { questionField = Field.init "" <| \() s -> if String.isEmpty s then Err "must not be empty" else Ok s
  , stakeField = Field.init "20" <| \() s ->
      case String.toFloat s of
        Nothing -> Err "must be a positive number"
        Just dollars -> if dollars <= 0 then Err "must be a positive number" else Ok <| round (100*dollars)
  , lowPField = Field.init "0" <| \() s ->
      case String.toFloat s of
         Nothing -> Err "must be a number 0-100"
         Just pct -> if pct < 0 || pct > 100 then Err "must be a number 0-100" else Ok (pct/100)
  , highPField = Field.init "0" <| \{lowP} s ->
      case String.toFloat s of
         Nothing -> Err "must be a number 0-100"
         Just pNoPct -> if pNoPct < 0 || pNoPct > 100 then Err "must be a number 0-100" else let highP = 1 - pNoPct/100 in if lowP > highP then Err "your prices must sum to under 100" else Ok highP
  , openForUnitField = Field.init "weeks" <| \() s ->
      case s of
        "days" -> Ok Days
        "weeks" -> Ok Weeks
        _ -> Err "unrecognized time unit"
  , openForSecondsField = Field.init "2" <| \{unit} s ->
      case String.toInt s of
        Nothing -> Err "must be a positive integer"
        Just n -> if n <= 0 then Err "must be a positive integer" else Ok (n * unitToSeconds unit)
  , specialRulesField = Field.init "" <| \() s -> Ok s
  }

type MsgForDemo = SetState State
main : Program () State MsgForDemo
main =
  Browser.sandbox
    { init = init
    , view = view {setState = SetState, disabled = False}
    , update = \(SetState newState) _ -> newState
    }
