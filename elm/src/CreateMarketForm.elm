module CreateMarketForm exposing (..)

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

type OpenForUnit = Days | Weeks
unitToSeconds : OpenForUnit -> Int
unitToSeconds u =
  case u of
    Days -> 60 * 60 * 24
    Weeks -> unitToSeconds Days * 7

type Msg
  = SetQuestion String
  | SetStake String
  | SetLowP String
  | SetHighP String
  | SetOpenForUnit String
  | SetOpenForN String
  | SetSpecialRules String

type alias Model =
  { questionField : Field () String
  , stakeField : Field () Int
  , lowPField : Field () Float
  , highPField : Field {lowP:Float} Float
  , openForUnitField : Field () OpenForUnit
  , openForSecondsField : Field {unit:OpenForUnit} Int
  , specialRulesField : Field () String
  , disabled : Bool
  }

toCreateRequest : Model -> Maybe Pb.CreateMarketRequest
toCreateRequest model =
  Field.parse () model.questionField |> Result.andThen (\question ->
  Field.parse () model.stakeField |> Result.andThen (\stake ->
  Field.parse () model.lowPField |> Result.andThen (\lowP ->
  Field.parse {lowP=lowP} model.highPField |> Result.andThen (\highP ->
  Field.parse () model.openForUnitField |> Result.andThen (\unit ->
  Field.parse {unit=unit} model.openForSecondsField |> Result.andThen (\openForSeconds ->
  Field.parse () model.specialRulesField |> Result.andThen (\specialRules ->
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

update : Msg -> Model -> Model
update msg model =
  case msg of
    SetQuestion s -> { model | questionField = model.questionField |> Field.setStr s}
    SetStake s -> { model | stakeField = model.stakeField |> Field.setStr s}
    SetLowP s -> { model | lowPField = model.lowPField |> Field.setStr s}
    SetHighP s -> { model | highPField = model.highPField |> Field.setStr s}
    SetOpenForUnit s -> { model | openForUnitField = model.openForUnitField |> Field.setStr s}
    SetOpenForN s -> { model | openForSecondsField = model.openForSecondsField |> Field.setStr s}
    SetSpecialRules s -> { model | specialRulesField = model.specialRulesField |> Field.setStr s}

view : Model -> Html Msg
view model =
  let
    outlineIfInvalid b = Utils.outlineIfInvalid (b && not model.disabled)
    highPCtx = {lowP = Field.parse () model.lowPField |> Result.withDefault 0}
    openForSecondsCtx = {unit = Field.parse () model.openForUnitField |> Result.withDefault Days}
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
            , Field.inputFor SetQuestion () model.questionField
                H.textarea
                [ HA.style "width" "100%"
                , HA.placeholder placeholders.question
                , HA.disabled model.disabled
                , HA.class "question-field"
                ] []
            ]
        , H.li []
            [ H.text "How much are you willing to stake? $"
            , Field.inputFor SetStake () model.stakeField
                H.input
                [ HA.type_ "number", HA.min "0", HA.max (String.fromInt maxLegalStakeCents)
                , HA.placeholder placeholders.stake
                , HA.disabled model.disabled
                ] []
            ]
        , H.li []
            [ H.text "How much would you be willing to pay if your most well-informed friend offered you an IOU that paid out..."
            , H.ul []
                [ H.li []
                  [ H.text "...$100 if this "
                  , H.strong [] [H.text "happens?"]
                  , H.text " $"

                  , Field.inputFor SetLowP () model.lowPField
                      H.input
                      [ HA.type_ "number", HA.min "0", HA.max "100"
                      , HA.style "width" "5em"
                      , HA.disabled model.disabled
                      ] []
                  ]
                , H.li []
                  [ H.text "...$100 if this "
                  , H.strong [] [H.text "doesn't happen?"]
                  , H.text " $"
                  , Field.inputFor SetHighP highPCtx model.highPField
                      H.input
                      [ HA.type_ "number", HA.min "0", HA.max (String.fromFloat <| Result.withDefault 100 <| Result.map (\n -> 99.999 - n) <| Field.parse highPCtx model.highPField)
                      , HA.style "width" "5em"
                      , HA.disabled model.disabled
                      ] []
                  ]
                ]
            , H.text "In other words, you think that this is "
            , H.strong []
                [ case Field.parse () model.lowPField of
                    Err _ -> H.text "???"
                    Ok p -> H.text <| String.fromInt <| round (100*p)
                , H.text "-"
                , case Field.parse highPCtx model.highPField of
                    Err _ -> H.text "???"
                    Ok p -> H.text <| String.fromInt <| round (100*p)
                , H.text "%"
                ]
            , H.text " likely."
            ]
        , H.li []
            [ H.text "How long is this offer open for?"
            , Field.inputFor SetOpenForN {unit=Field.parse () model.openForUnitField |> Result.withDefault Weeks} model.openForSecondsField
                H.input
                [ HA.type_ "number", HA.min "1"
                , HA.style "width" "5em"
                , HA.disabled model.disabled
                ] []
            , Field.inputFor SetOpenForUnit () model.openForUnitField
                H.select
                [ HA.disabled model.disabled
                ]
                [ H.option [] [H.text "weeks"]
                , H.option [] [H.text "days"]
                ]
            ]
        , H.li []
            [ H.text "Any special rules? (For instance: what might make you consider the market unresolvable/invalid? What would you count as \"insider trading\"/cheating?)"
            , Field.inputFor SetSpecialRules () model.specialRulesField
                H.textarea
                [ HA.style "width" "100%"
                , HA.placeholder placeholders.specialRules
                , HA.disabled model.disabled
                ]
                []
            ]
        ]
    ]

init : Model
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
  , disabled = False
  }

disable : Model -> Model
disable model = { model | disabled = True }
enable : Model -> Model
enable model = { model | disabled = False }

main : Program () Model Msg
main =
  Browser.sandbox
    { init = init
    , view = view
    , update = update
    }
