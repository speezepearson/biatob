module Widgets.CreatePredictionWidget exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Utils exposing (i)
import Time
import Task

import Field exposing (Field)
import Biatob.Proto.Mvp as Pb
import Iso8601
import Utils

maxLegalStakeCents = 500000
epsilon = 0.000001

type OpenForUnit = Days | Weeks
unitToSeconds : OpenForUnit -> Int
unitToSeconds u =
  case u of
    Days -> 60 * 60 * 24
    Weeks -> unitToSeconds Days * 7

type Event = Ignore
type alias Context msg =
  { handle : Maybe Event -> State -> msg
  , disabled : Bool
  , now : Time.Posix
  }
type alias State =
  { predictionField : Field () String
  , resolvesAtField : Field {now:Time.Posix} Time.Posix
  , stakeField : Field () Int
  , lowPField : Field () Float
  , highPField : Field {lowP:Float} Float
  , openForUnitField : Field () OpenForUnit
  , openForSecondsField : Field {unit:OpenForUnit, resolvesAt:Maybe Time.Posix} Int
  , specialRulesField : Field () String
  }

toCreateRequest : Context msg -> State -> Maybe Pb.CreatePredictionRequest
toCreateRequest ctx state =
  Field.parse () state.predictionField |> Result.andThen (\prediction ->
  Field.parse {now=ctx.now} state.resolvesAtField |> Result.andThen (\resolvesAt ->
  Field.parse () state.stakeField |> Result.andThen (\stake ->
  Field.parse () state.lowPField |> Result.andThen (\lowP ->
  Field.parse {lowP=lowP} state.highPField |> Result.andThen (\highP ->
  Field.parse () state.openForUnitField |> Result.andThen (\unit ->
  Field.parse {unit=unit,resolvesAt=Just resolvesAt} state.openForSecondsField |> Result.andThen (\openForSeconds ->
  Field.parse () state.specialRulesField |> Result.andThen (\specialRules ->
    Ok
      { prediction = prediction
      , certainty = Just { low=lowP, high=highP }
      , maximumStakeCents = stake
      , openSeconds = openForSeconds
      , specialRules = specialRules
      , resolvesAtUnixtime = Utils.timeToUnixtime resolvesAt
      }
  ))))))))
  |> Result.toMaybe

view : Context msg -> State -> Html msg
view ctx state =
  let
    highPCtx = {lowP = Field.parse () state.lowPField |> Result.withDefault 0}
    placeholders =
      { prediction = "at least 50% of U.S. COVID-19 cases will be B117 or a derivative strain, as reported by the CDC"
      , stake = "100"
      , specialRules = "If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the prediction is unresolvable."
      }
  in
  H.div []
    [ H.ul [HA.class "new-prediction-form"]
        [ H.li []
            [ H.text "I predict that, by "
            , Field.inputFor (\s -> ctx.handle Nothing { state | resolvesAtField = state.resolvesAtField |> Field.setStr s}) {now=ctx.now} state.resolvesAtField
                H.input
                [ HA.type_ "date"
                , HA.class "resolves-at-field"
                , HA.disabled ctx.disabled
                ] []
            , H.text ", "
            , H.br [] []
            , Field.inputFor (\s -> ctx.handle Nothing { state | predictionField = state.predictionField |> Field.setStr s}) () state.predictionField
                H.textarea
                [ HA.style "width" "100%"
                , HA.placeholder placeholders.prediction
                , HA.disabled ctx.disabled
                , HA.class "prediction-field"
                ] []
            , H.details []
                [ H.summary [HA.style "text-align" "right"] [H.text "Advice"]
                , H.text "A good prediction is ", i "objective", H.text " and ", i "verifiable,"
                , H.text " ideally about ", i "experiences you anticipate having."
                , H.ul []
                  [ H.li [] [H.text " \"Gun violence will increase in the U.S. in 2022\" is extremely ill-defined."]
                  , H.li [] [H.text " \"There will be at least 40,000 gun deaths in the U.S. in 2022\" is better, but it's still not ", i "verifiable", H.text " (by you)."]
                  , H.li [] [H.text " \"The CDC will report at least 40,000 gun deaths for 2022, as stated on https://www.cdc.gov/nchs/fastats/injury.htm\" is very good!"]
                  ]
                ]
          ]
        , H.li []
            [ H.text "I think this has at least a"
            , Field.inputFor (\s -> ctx.handle Nothing { state | lowPField = state.lowPField |> Field.setStr s}) () state.lowPField
                H.input
                [ HA.type_ "number", HA.min "0", HA.max "100", HA.step "any"
                , HA.style "width" "5em"
                , HA.disabled ctx.disabled
                ] []
            , H.text "% chance of happening,"
            , H.br [] []
            , H.text "but not more than a "
            , Field.inputFor (\s -> ctx.handle Nothing { state | highPField = state.highPField |> Field.setStr s}) highPCtx state.highPField
                H.input
                [ HA.type_ "number", HA.min (String.fromFloat <| Result.withDefault 100 <| Field.parse () state.lowPField), HA.max "100", HA.step "any"
                , HA.style "width" "5em"
                , HA.disabled ctx.disabled
                ] []
            , H.text "% chance."
            , case Field.parse () state.lowPField of
                Ok lowP ->
                  if lowP == 0 then
                    H.div [HA.style "opacity" "50%"]
                      [ H.text "A low probability of 0 means you're actually only willing to bet "
                      , i "against"
                      , H.text <| " your prediction, which might be confusing to your friends."
                        ++ " Consider negating your prediction (\"I predict X\" -> \"I predict NOT X\") to make things clearer."
                      ]
                  else
                    H.text ""
                _ -> H.text ""
            , H.details []
                [ H.summary [HA.style "text-align" "right"] [H.text "Confusing?"]
                , H.p [] [H.text "\"Why do I need to enter ", i "two", H.text <| " probabilities?\" It's a way to protect yourself from making bets you'll immediately regret!"]
                , H.p [] [H.text <| "An example: imagine you post a prediction about an election outcome,"
                    ++ " saying that Howell is 70% likely to win."
                    ++ " The next day, your cleverest, best-informed friend, Nate, bets heavily that Howell will lose."
                    ++ " You probably think: \"Aw, drat. Nate knows a lot about politics, he's probably right, I should've posted lower odds.\""
                    ++ " But if Nate had instead bet heavily that Howell would ", i "win,", H.text <| " you would think:"
                    ++ " \"Aw, drat. I should've posted ", i "higher", H.text <| " odds.\" You can't win! No matter what odds you offer,"
                    ++ " as soon as Nate bets against you, you'll regret it."]
                , H.p [] [H.text <| "But maybe you think that ", i "even Nate", H.text <| " would be crazy to assign Howell less than a 40% chance,"
                    ++ " or more than a 90% chance. Then, you could publish \"40-90%\" odds: your $4 against $6 that Howell will win, or your $1 against $9 that Howell will lose."
                    ++ " Then, even Nate betting against you won't shift your probability estimate so much that you regret offering the wager."
                    ]
                , H.p [] [H.text <| "You can think of the spread as being a measurement of how confident you are:"
                    ++ " a small spread, like 70-73%, means you've thought about this ", i "really carefully,", H.text <| " and"
                    ++ " you don't expect your opinion to be budged by any of your friends' bets or any new information that comes out"
                    ++ " before betting closes; a wide spread, like 30-95%, is sort of off-the-cuff, you just want to throw it out there that"
                    ++ " it's ", i "pretty likely", H.text <| " but you haven't thought ", i "that", H.text <| " hard about it."
                    ++ " Predictions don't have to be effortful, painstakingly researched things!"
                    ++ " It's okay to throw out half-formed thoughts with wide spreads!"
                    ]
                , H.p [] [H.text <| "If you still confused, hey, don't worry about it! This is really remarkably counterintuitive stuff."
                    ++ " Just leave the high probability at 100%."
                    ]
                ]
            ]
        , H.li []
            [ H.text "I'm willing to bet up to $"
            , Field.inputFor (\s -> ctx.handle Nothing { state | stakeField = state.stakeField |> Field.setStr s}) () state.stakeField
                H.input
                [ HA.type_ "number", HA.min "0", HA.max (String.fromInt <| maxLegalStakeCents//100)
                , HA.style "width" "5em"
                , HA.placeholder placeholders.stake
                , HA.disabled ctx.disabled
                ] []
            , H.text " at these odds."
            , case Field.parse () state.stakeField of
                  Err _ -> H.text ""
                  Ok stakeCents ->
                    let
                      betVsSkeptics : Maybe String
                      betVsSkeptics =
                        Field.parse () state.lowPField
                        |> Result.toMaybe
                        |> Maybe.andThen (\lowP -> if lowP == 0 then Nothing else Just <| Utils.formatCents stakeCents ++ " against " ++ Utils.formatCents (round <| toFloat stakeCents * (1-lowP)/lowP))
                      betVsBelievers : Maybe String
                      betVsBelievers =
                        Field.parse highPCtx state.highPField
                        |> Result.toMaybe
                        |> Maybe.andThen (\highP -> if highP == 1 then Nothing else Just <| Utils.formatCents stakeCents ++ " against " ++ Utils.formatCents (round <| toFloat stakeCents * highP/(1-highP)))
                    in
                      case (betVsSkeptics, betVsBelievers) of
                        (Nothing, Nothing) -> H.text ""
                        (Just s, Nothing) -> H.div [] [H.text "(In other words, I'd happily bet ", H.strong [] [H.text s], H.text " that this will happen.)"]
                        (Nothing, Just s) -> H.div [] [H.text "(In other words, I'd happily bet ", H.strong [] [H.text s], H.text " that this won't happen.)"]
                        (Just skep, Just bel)  -> H.div [] [H.text "(In other words, I'd happily bet ", H.strong [] [H.text skep], H.text " that this will happen, or ", H.strong [] [H.text bel], H.text " that it won't.)"]
            ]
        , H.li []
            [ H.text "This offer is open for "
            , Field.inputFor (\s -> ctx.handle Nothing { state | openForSecondsField = state.openForSecondsField |> Field.setStr s}) {unit=Field.parse () state.openForUnitField |> Result.withDefault Weeks, resolvesAt=Field.parse {now=ctx.now} state.resolvesAtField |> Result.toMaybe} state.openForSecondsField
                H.input
                [ HA.type_ "number", HA.min "1"
                , HA.style "width" "5em"
                , HA.disabled ctx.disabled
                ] []
            , Field.inputFor (\s -> ctx.handle Nothing { state | openForUnitField = state.openForUnitField |> Field.setStr s}) () state.openForUnitField
                H.select
                [ HA.disabled ctx.disabled
                ]
                [ H.option [] [H.text "weeks"]
                , H.option [] [H.text "days"]
                ]
            , H.text "."
            , H.details []
                [ H.summary [HA.style "text-align" "right"] [H.text "Confusing?"]
                , H.text <| "If it's 2021-01-01, and you're betting on whether [some thing] will happen by 2022-01-01,"
                    ++ " you don't want people to be able to wait until 2021-12-31 before betting against you."
                    ++ " You might say \"This offer is only open for 2 weeks,\" to give your friends time to bet,"
                    ++ " without letting them get ", H.i [] [H.text "too much"], H.text " extra information."
                ]
            ]
        , H.li []
            [ H.text "Special rules (e.g. implicit assumptions, what counts as cheating):"
            , Field.inputFor (\s -> ctx.handle Nothing { state | specialRulesField = state.specialRulesField |> Field.setStr s}) () state.specialRulesField
                H.textarea
                [ HA.style "width" "100%"
                , HA.placeholder placeholders.specialRules
                , HA.disabled ctx.disabled
                , HA.class "special-rules-field"
                ]
                []
            ]
        ]
    ]

init : State
init =
  { predictionField = Field.init "" <| \() s -> if String.isEmpty s then Err "must not be empty" else Ok s
  , resolvesAtField = Field.init "" <| \{now} s ->
      case Iso8601.toTime s of
        Err _ -> Err ""
        Ok t -> if Utils.timeToUnixtime t < Utils.timeToUnixtime now then Err "must be in the future" else Ok t
  , stakeField = Field.init "20" <| \() s ->
      case String.toFloat s of
        Nothing -> Err "must be a positive number"
        Just dollars ->
          if dollars <= 0 then Err "must be a positive number" else
          if dollars > toFloat maxLegalStakeCents / 100 then Err "Sorry, I hate to be paternalistic, but I don't want to let people bet more than they can afford to lose, so I put in a semi-arbitrary $5000-per-prediction limit. I *do* plan to lift this restriction someday, there are just some site design issues I need to work out first, and they're not on top of my priority queue. Thanks for your patience! [dated 2021-02]" else
          Ok <| round (100*dollars)
  , lowPField = Field.init "50" <| \() s ->
      case String.toFloat s of
        Nothing -> Err "must be a number 0-100"
        Just pct -> if pct < 0 || pct > 100 then Err "must be a number 0-100" else Ok (pct/100)
  , highPField = Field.init "100" <| \{lowP} s ->
      case String.toFloat s of
        Nothing -> Err "must be a number 0-100"
        Just pct -> if pct < 0 || pct > 100 then Err "must be a number 0-100" else let highP = pct/100 in
          if highP < lowP - epsilon then
            Err "can't be less than your low prob"
          else if highP < lowP then
            Ok lowP
          else
            Ok highP
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
