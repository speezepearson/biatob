module Widgets.CreatePredictionWidget exposing (..)

import Html as H exposing (Html)
import Html.Events as HE
import Html.Attributes as HA
import Utils exposing (i, Cents)
import Time

import Biatob.Proto.Mvp as Pb
import Iso8601
import Utils
import Page

maxLegalStakeCents = 500000
epsilon = 0.000001

type OpenForUnit = Days | Weeks
unitToSeconds : OpenForUnit -> Int
unitToSeconds u =
  case u of
    Days -> 60 * 60 * 24
    Weeks -> unitToSeconds Days * 7

type alias Model =
  { predictionField : String
  , resolvesAtField : String
  , stakeField : String
  , lowPField : String
  , highPField : String
  , openForUnitField : String
  , openForSecondsField : String
  , specialRulesField : String
  }
type Msg
  = SetPredictionField String
  | SetResolvesAtField String
  | SetStakeField String
  | SetLowPField String
  | SetHighPField String
  | SetOpenForUnitField String
  | SetOpenForSecondsField String
  | SetSpecialRulesField String

toCreateRequest : Time.Posix -> Time.Zone -> Model -> Maybe Pb.CreatePredictionRequest
toCreateRequest now zone model =
  parsePrediction model |> Result.toMaybe |> Maybe.andThen (\prediction ->
  parseResolvesAt now model |> Result.toMaybe |> Maybe.andThen (\resolvesAt ->
  parseStake model |> Result.toMaybe |> Maybe.andThen (\stake ->
  parseLowProbability model |> Result.toMaybe |> Maybe.andThen (\lowP ->
  parseHighProbability model |> Result.toMaybe |> Maybe.andThen (\highP -> if highP < lowP then Nothing else 
  parseOpenForSeconds now model |> Result.toMaybe |> Maybe.andThen (\openForSeconds ->
    Just
      { prediction = prediction
      , certainty = Just { low=lowP, high=highP }
      , maximumStakeCents = stake
      , openSeconds = openForSeconds
      , specialRules = model.specialRulesField
      , resolvesAtUnixtime = Utils.timeToUnixtime resolvesAt
      }
  ))))))

view : Page.Globals -> Model -> Html Msg
view globals model =
  let
    disabled = not <| Page.isLoggedIn globals
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
            , H.input
                [ HA.type_ "date"
                , HA.class "resolves-at-field"
                , HA.disabled disabled
                , HE.onInput SetResolvesAtField
                , HA.value model.resolvesAtField
                ] []
              |> Utils.appendValidationError (Utils.resultToErr (parseResolvesAt globals.now model))
            , H.text ", "
            , H.br [] []
            , H.textarea
                [ HA.style "width" "100%"
                , HA.placeholder placeholders.prediction
                , HA.disabled disabled
                , HA.class "prediction-field"
                , HE.onInput SetPredictionField
                , HA.value model.predictionField
                ] []
              |> Utils.appendValidationError (if model.predictionField == "" then Just "must not be empty" else Nothing)
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
            , H.input
                [ HA.type_ "number", HA.min "0", HA.max "100", HA.step "any"
                , HA.style "width" "5em"
                , HA.disabled disabled
                , HE.onInput SetLowPField
                , HA.value model.lowPField
                ] []
            , H.text "% chance of happening,"
            , H.br [] []
            , H.text "but not more than a "
            , H.input
                [ HA.type_ "number", HA.min (String.toFloat model.lowPField |> Maybe.withDefault 0 |> String.fromFloat), HA.max "100", HA.step "any"
                , HA.style "width" "5em"
                , HA.disabled disabled
                , HE.onInput SetHighPField
                , HA.value model.highPField
                ] []
              |> Utils.appendValidationError (case parseLowProbability model of
                  Err _ -> Nothing
                  Ok lowP -> case parseHighProbability model of
                    Ok highP -> if highP < lowP then Just "can't be less than your low prob" else Nothing
                    Err e -> Just e)
            , H.text "% chance."
            , case parseLowProbability model of
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
            , H.input
                [ HA.type_ "number", HA.min "0", HA.max (String.fromInt <| maxLegalStakeCents//100)
                , HA.style "width" "5em"
                , HA.placeholder placeholders.stake
                , HA.disabled disabled
                , HE.onInput SetStakeField
                , HA.value model.stakeField
                ] []
              |> Utils.appendValidationError (Utils.resultToErr (parseStake model))
            , H.text " at these odds."
            , case parseStake model of
                  Err _ -> H.text ""
                  Ok stakeCents ->
                    let
                      betVsSkeptics : Maybe String
                      betVsSkeptics =
                        parseLowProbability model
                        |> Debug.log "low p is"
                        |> Result.toMaybe
                        |> Maybe.andThen (\lowP -> if lowP == 0 then Nothing else Just <| Utils.formatCents stakeCents ++ " against " ++ Utils.formatCents (round <| toFloat stakeCents * (1-lowP)/lowP))
                      betVsBelievers : Maybe String
                      betVsBelievers =
                        parseHighProbability model
                        |> Debug.log "high prob is"
                        |> Result.toMaybe
                        |> Maybe.andThen (\highP -> if highP == 1 then Nothing else Just <| Utils.formatCents stakeCents ++ " against " ++ Utils.formatCents (round <| toFloat stakeCents * highP/(1-highP)))
                    in
                      case (betVsSkeptics, betVsBelievers) of
                        (Nothing, Nothing) -> H.text ""
                        (Just s, Nothing) -> H.div [] [H.text "(In other words, I'd happily bet ", Utils.b s, H.text " that this will happen.)"]
                        (Nothing, Just s) -> H.div [] [H.text "(In other words, I'd happily bet ", Utils.b s, H.text " that this won't happen.)"]
                        (Just skep, Just bel)  -> H.div [] [H.text "(In other words, I'd happily bet ", Utils.b skep, H.text " that this will happen, or ", Utils.b bel, H.text " that it won't.)"]
            ]
        , H.li []
            [ H.text "This offer is open for "
            , H.input
                [ HA.type_ "number", HA.min "1"
                , HA.style "width" "5em"
                , HA.disabled disabled
                , HE.onInput SetOpenForSecondsField
                , HA.value model.openForSecondsField
                ] []
              |> Utils.appendValidationError (Utils.resultToErr (parseOpenForSeconds globals.now model))
            , H.select
                [ HA.disabled disabled
                , HE.onInput SetOpenForUnitField
                , HA.value model.openForUnitField
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
                    ++ " without letting them get ", Utils.i "too much", H.text " extra information."
                ]
            ]
        , H.li []
            [ H.text "Special rules (e.g. implicit assumptions, what counts as cheating):"
            , H.textarea
                [ HA.style "width" "100%"
                , HA.placeholder placeholders.specialRules
                , HA.disabled disabled
                , HA.class "special-rules-field"
                , HE.onInput SetSpecialRulesField
                , HA.value model.specialRulesField
                ]
                []
            ]
        ]
    ]

update : Msg -> Model -> ( Model , Page.Command Msg )
update msg model =
  case msg of
    SetPredictionField s -> ( { model | predictionField = s } , Page.NoCmd )
    SetResolvesAtField s -> ( { model | resolvesAtField = s } , Page.NoCmd )
    SetStakeField s -> ( { model | stakeField = s } , Page.NoCmd )
    SetLowPField s -> ( { model | lowPField = s } , Page.NoCmd )
    SetHighPField s -> ( { model | highPField = s } , Page.NoCmd )
    SetOpenForUnitField s -> ( { model | openForUnitField = s } , Page.NoCmd )
    SetOpenForSecondsField s -> ( { model | openForSecondsField = s } , Page.NoCmd )
    SetSpecialRulesField s -> ( { model | specialRulesField = s } , Page.NoCmd )

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

init : Model
init =
  { predictionField = ""
  , resolvesAtField = ""
  , stakeField = "20"
  , lowPField = "50"
  , highPField = "100"
  , openForUnitField = "weeks"
  , openForSecondsField = "2"
  , specialRulesField = ""
  }

parsePrediction : Model -> Result String String
parsePrediction model =
  if String.isEmpty model.predictionField then
    Err "must not be empty"
  else
    Ok model.predictionField

parseResolvesAt : Time.Posix -> Model -> Result String Time.Posix
parseResolvesAt now model =
    case Iso8601.toTime model.resolvesAtField of
      Err _ -> Err ""
      Ok t -> if Utils.timeToUnixtime t < Utils.timeToUnixtime now then Err "must be in the future" else Ok t

parseStake : Model -> Result String Cents
parseStake model =
    case String.toFloat model.stakeField of
      Nothing -> Err "must be a positive number"
      Just dollars ->
        if dollars <= 0 then Err "must be a positive number" else
        if dollars > toFloat maxLegalStakeCents / 100 then Err "Sorry, I hate to be paternalistic, but I don't want to let people bet more than they can afford to lose, so I put in a semi-arbitrary $5000-per-prediction limit. I *do* plan to lift this restriction someday, there are just some site design issues I need to work out first, and they're not on top of my priority queue. Thanks for your patience! [dated 2021-02]" else
        Ok <| round (100*dollars)

parseLowProbability : Model -> Result String Float
parseLowProbability model =
    case String.toFloat model.lowPField of
      Nothing -> Err "must be a number 0-100"
      Just pct ->
        let
          lowP = pct / 100
        in
          if lowP < 0 || lowP > 1 then
            Err "must be a number 0-100"
          else
            Ok lowP

parseHighProbability : Model -> Result String Float
parseHighProbability model =
    case String.toFloat model.highPField of
      Nothing -> Err "must be a number 0-100"
      Just pct ->
        let
          highP = pct / 100
          minAllowed = parseLowProbability model |> Result.withDefault 0
        in
          if highP > 1 then
            Err "must be a number 0-100"
          else
          if highP < minAllowed - epsilon then
            Err "can't be less than your low prob"
          else if highP < minAllowed then
            Ok minAllowed
          else
            Ok highP

parseOpenForUnit : Model -> OpenForUnit
parseOpenForUnit model =
    case model.openForUnitField of
      "days" -> Days
      "weeks" -> Weeks
      _ -> Debug.todo "unrecognized time unit"

parseOpenForSeconds : Time.Posix -> Model -> Result String Int
parseOpenForSeconds now model =
    case String.toInt model.openForSecondsField of
      Nothing -> Err "must be a positive integer"
      Just n ->
        if n <= 0 then
          Err "must be a positive integer"
        else
          let nSec = n * unitToSeconds (parseOpenForUnit model) in
          case parseResolvesAt now model of
            Err _ -> Ok nSec
            Ok t ->
              if Time.posixToMillis now + 1000 * nSec > Time.posixToMillis t then
                Err "must close before prediction resolves"
              else
                Ok nSec
