module CreateMarketForm exposing (State, Config, view, initStateForDemo, question, stake, lowPYes, lowPNo, openForSeconds, specialRules)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
howToWriteGoodBetsUrl = "http://example.com/TODO"
maxStake = 5000

type alias Config msg =
  { setState : State -> msg
  }

type OpenForUnit = Days | Weeks
unitToSeconds : OpenForUnit -> Int
unitToSeconds u =
  case u of
    Days -> 60 * 60 * 24
    Weeks -> unitToSeconds Days * 7

type alias State =
  { questionField : String
  , stakeField : String
  , lowPYesField : String
  , lowPNoField : String
  , openForNField : String
  , openForUnitField : OpenForUnit
  , specialRulesField : String
  }

question : State -> String
question {questionField} = questionField
stake : State -> Maybe Float
stake {stakeField} = String.toFloat stakeField
lowPYes : State -> Maybe Float
lowPYes {lowPYesField} = String.toFloat lowPYesField
lowPNo : State -> Maybe Float
lowPNo {lowPNoField} = String.toFloat lowPNoField
openForSeconds : State -> Maybe Int
openForSeconds {openForNField, openForUnitField} =
  String.toInt openForNField
  |> Maybe.map ((*) (unitToSeconds openForUnitField))
specialRules : State -> String
specialRules {specialRulesField} = specialRulesField


isValidPercentProbabilityStr : String -> Bool
isValidPercentProbabilityStr s =
  case String.toFloat s of
    Just n -> 0 <= n && n <= 100
    Nothing -> False

isValidStakeStr : String -> Bool
isValidStakeStr s =
  case String.toFloat s of
    Just n -> 0 <= n && n <= maxStake
    Nothing -> False

isValidOpenForNField : String -> Bool
isValidOpenForNField s =
  case String.toInt s of
    Just n -> 0 <= n
    Nothing -> False

outlineIfInvalid : Bool -> H.Attribute msg
outlineIfInvalid isValid =
  HA.style "outline" (if isValid then "none" else "2px solid red")

view : Config msg -> State -> Html msg
view config state =
  H.div []
    [ H.ul []
        [ H.li [] 
            [ H.text "What prediction are you willing to stake money on? ("
            , H.a [HA.href howToWriteGoodBetsUrl] [H.text "how to write good bets"]
            , H.text ") "
            , H.br [] []
            , H.textarea
                [ HA.style "width" "100%"
                , HA.value state.questionField
                , HE.onInput (\s -> config.setState {state | questionField = s})
                ] []
            ]
        , H.li []
            [ H.text "How much are you willing to stake? $"
            , H.input
                [ HA.type_ "number", HA.min "0", HA.max (String.fromInt maxStake)
                , HA.value state.stakeField
                , HE.onInput (\s -> config.setState {state | stakeField = s})
                , outlineIfInvalid (isValidStakeStr state.stakeField)
                ] []
            ]
        , H.li []
            [ H.text "How much would you be willing to pay if your most well-informed friend offered you an IOU that paid out..."
            , H.ul []
                [ H.li []
                  [ H.text "...$100 if this "
                  , H.strong [] [H.text "happens?"]
                  , H.text " $"

                  , H.input
                      [ HA.type_ "number", HA.min "0", HA.max "100"
                      , HA.style "width" "5em"
                      , HA.value state.lowPYesField
                      , HE.onInput (\s -> config.setState {state | lowPYesField = s})
                      , outlineIfInvalid (isValidPercentProbabilityStr state.lowPYesField)
                      ] []                  
                  ]
                , H.li []
                  [ H.text "...$100 if this "
                  , H.strong [] [H.text "doesn't happen?"]
                  , H.text " $"
                  , H.input
                      [ HA.type_ "number", HA.min "0", HA.max (String.fromFloat <| Maybe.withDefault 100 <| Maybe.map (\n -> 99.99 - n) <| String.toFloat state.lowPYesField)
                      , HA.style "width" "5em"
                      , HA.value state.lowPNoField
                      , HE.onInput (\s -> config.setState {state | lowPNoField = s})
                      , outlineIfInvalid (isValidPercentProbabilityStr state.lowPNoField)
                      ] []
                  ]
                ]
            , H.text "In other words, you think that this is "
            , case (String.toFloat state.lowPYesField, String.toFloat state.lowPNoField) of
                (Just lpy, Just lpn) ->
                  H.strong
                    [ outlineIfInvalid (lpy + lpn < 100)
                    ]
                    [ lpy                  |> round |> String.fromInt |> H.text
                    , H.text "-"
                    , lpn |> (\n -> 100 - n) |> round |> String.fromInt |> H.text
                    , H.text "%"
                    ]
                _ ->
                  H.strong [outlineIfInvalid False] [H.text "???%"]
            , H.text " likely."
            ]
        , H.li []
            [ H.text "How long is this offer open for?"
            , H.input
                [ HA.type_ "number", HA.min "1"
                , HA.style "width" "5em"
                , HA.value state.openForNField
                , HE.onInput (\s -> config.setState {state | openForNField = s})
                , outlineIfInvalid (isValidOpenForNField state.openForNField)
                ] []
            , H.select
                [ HE.onInput (\s -> config.setState {state | openForUnitField = if s=="days" then Days else Weeks})
                ]
                [ H.option [] [H.text "weeks"]
                , H.option [] [H.text "days"]
                ]
            ]
        , H.li []
            [ H.text "Any special rules? (For instance: what might make you consider the market unresolvable/invalid? What would you count as \"insider trading\"/cheating?)"
            , H.textarea
                [ HA.style "width" "100%"
                , HE.onInput (\s -> config.setState {state | specialRulesField = s})
                ]
                [ H.text state.specialRulesField ]
            ]
        ]
    ]


initStateForDemo : State
initStateForDemo =
  { questionField = "By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?"
  , stakeField = "100"
  , lowPYesField = "80"
  , lowPNoField = "10"
  , openForNField = "2"
  , openForUnitField = Weeks
  , specialRulesField = "If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable."
  }

type MsgForDemo = SetState State
main : Program () State MsgForDemo
main =
  Browser.sandbox
    { init = initStateForDemo
    , view = view {setState = SetState}
    , update = \(SetState newState) _ -> newState
    }
