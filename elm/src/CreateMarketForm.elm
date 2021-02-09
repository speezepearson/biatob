module CreateMarketForm exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Utils
import Time
import Task

import Field exposing (Field)
import Biatob.Proto.Mvp as Pb
import Iso8601
import Field

howToWriteGoodBetsUrl = "http://example.com/TODO"
maxLegalStakeCents = 500000
epsilon = 0.000001

type OpenForUnit = Days | Weeks
unitToSeconds : OpenForUnit -> Int
unitToSeconds u =
  case u of
    Days -> 60 * 60 * 24
    Weeks -> unitToSeconds Days * 7

type Msg
  = SetPrediction String
  | SetResolvesTime String
  | SetStake String
  | SetLowP String
  | SetHighP String
  | SetOpenForUnit String
  | SetOpenForN String
  | SetSpecialRules String
  | Tick Time.Posix

type alias Model =
  { predictionField : Field () String
  , resolvesAtField : Field {now:Time.Posix} Time.Posix
  , stakeField : Field () Int
  , lowPField : Field () Float
  , highPField : Field {lowP:Float} Float
  , openForUnitField : Field () OpenForUnit
  , openForSecondsField : Field {unit:OpenForUnit, resolvesAt:Maybe Time.Posix} Int
  , specialRulesField : Field () String
  , disabled : Bool
  , now : Time.Posix
  }

toCreateRequest : Model -> Maybe Pb.CreateMarketRequest
toCreateRequest model =
  Field.parse () model.predictionField |> Result.andThen (\prediction ->
  Field.parse {now=model.now} model.resolvesAtField |> Result.andThen (\resolvesAt ->
  Field.parse () model.stakeField |> Result.andThen (\stake ->
  Field.parse () model.lowPField |> Result.andThen (\lowP ->
  Field.parse {lowP=lowP} model.highPField |> Result.andThen (\highP ->
  Field.parse () model.openForUnitField |> Result.andThen (\unit ->
  Field.parse {unit=unit,resolvesAt=Just resolvesAt} model.openForSecondsField |> Result.andThen (\openForSeconds ->
  Field.parse () model.specialRulesField |> Result.andThen (\specialRules ->
    Ok
      { prediction = prediction
      , privacy = Nothing  -- TODO: delete this field
      , certainty = Just { low=lowP, high=highP }
      , maximumStakeCents = stake
      , openSeconds = openForSeconds
      , specialRules = specialRules
      , resolvesAtUnixtime = Time.posixToMillis resolvesAt // 1000
      }
  ))))))))
  |> Result.toMaybe

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    SetPrediction s -> ({ model | predictionField = model.predictionField |> Field.setStr s}, Cmd.none)
    SetResolvesTime s -> ({ model | resolvesAtField = model.resolvesAtField |> Field.setStr s}, Cmd.none)
    SetStake s -> ({ model | stakeField = model.stakeField |> Field.setStr s}, Cmd.none)
    SetLowP s -> ({ model | lowPField = model.lowPField |> Field.setStr s}, Cmd.none)
    SetHighP s -> ({ model | highPField = model.highPField |> Field.setStr s}, Cmd.none)
    SetOpenForUnit s -> ({ model | openForUnitField = model.openForUnitField |> Field.setStr s}, Cmd.none)
    SetOpenForN s -> ({ model | openForSecondsField = model.openForSecondsField |> Field.setStr s}, Cmd.none)
    SetSpecialRules s -> ({ model | specialRulesField = model.specialRulesField |> Field.setStr s}, Cmd.none)
    Tick t ->
      ( { model | now = t , resolvesAtField = model.resolvesAtField |> if Time.posixToMillis model.now == 0 then Field.setStr (String.left 10 <| Iso8601.fromTime <| Utils.addMillis (1000*60*60*24*7*4) t) else identity }
      , Cmd.none
      )

view : Model -> Html Msg
view model =
  let
    outlineIfInvalid b = Utils.outlineIfInvalid (b && not model.disabled)
    highPCtx = {lowP = Field.parse () model.lowPField |> Result.withDefault 0}
    openForSecondsCtx = {unit = Field.parse () model.openForUnitField |> Result.withDefault Days}
    placeholders =
      { prediction = "at least 50% of U.S. COVID-19 cases will be B117 or a derivative strain, as reported by the CDC"
      , stake = "100"
      , specialRules = "If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable."
      }
  in
  H.div []
    [ H.ul [HA.class "create-market-form"]
        [ H.li []
            [ H.text "I predict that..."
            , H.br [] []
            , Field.inputFor SetPrediction () model.predictionField
                H.textarea
                [ HA.style "width" "100%"
                , HA.placeholder placeholders.prediction
                , HA.disabled model.disabled
                , HA.class "prediction-field"
                ] []
            , H.br [] []
            , H.div [HA.style "margin-left" "5em"]
                [ H.text " ...by "
                , Field.inputFor SetResolvesTime {now=model.now} model.resolvesAtField
                    H.input
                    [ HA.type_ "date"
                    , HA.disabled model.disabled
                    ] []
                , H.text "."
                -- TODO: , H.a [HA.href howToWriteGoodBetsUrl] [H.text "how to write good bets"]
                ]
          ]
        , H.li []
            [ H.text "I'm at least "
            , Field.inputFor SetLowP () model.lowPField
                H.input
                [ HA.type_ "number", HA.min "0", HA.max "100"
                , HA.style "width" "5em"
                , HA.disabled model.disabled
                ] []
            , H.text "% sure that this will happen,"
            , H.br [] []
            , H.text "though I admit there's at least a "
            , Field.inputFor SetHighP highPCtx model.highPField
                H.input
                [ HA.type_ "number", HA.min "0", HA.max (String.fromFloat <| Result.withDefault 100 <| Result.map (\n -> 99.999 - n) <| Field.parse highPCtx model.highPField)
                , HA.style "width" "5em"
                , HA.disabled model.disabled
                ] []
            , H.text "% chance I'm wrong."
            ]
        , H.li []
            [ H.text "I'm willing to stake up to $"
            , Field.inputFor SetStake () model.stakeField
                H.input
                [ HA.type_ "number", HA.min "0", HA.max (String.fromInt maxLegalStakeCents)
                , HA.style "width" "5em"
                , HA.placeholder placeholders.stake
                , HA.disabled model.disabled
                ] []
            , H.text " at these odds."
            , case Field.parse () model.stakeField of
                  Err _ -> H.text ""
                  Ok stakeCents ->
                    let
                      betVsSkeptics : Maybe String
                      betVsSkeptics =
                        Field.parse () model.lowPField
                        |> Result.toMaybe
                        |> Maybe.andThen (\lowP -> if lowP == 0 then Nothing else Just <| Utils.formatCents stakeCents ++ " against " ++ Utils.formatCents (round <| toFloat stakeCents * (1-lowP)/lowP))
                      betVsBelievers : Maybe String
                      betVsBelievers =
                        Field.parse highPCtx model.highPField
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
            [ H.text "This offer is only open for "
            , Field.inputFor SetOpenForN {unit=Field.parse () model.openForUnitField |> Result.withDefault Weeks, resolvesAt=Field.parse {now=model.now} model.resolvesAtField |> Result.toMaybe} model.openForSecondsField
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
            , H.text "."
            ]
        , H.li []
            [ H.text "Special rules (events that might invalidate the market, or what counts as cheating):"
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

init : () -> ( Model , Cmd Msg )
init () =
  ( { predictionField = Field.init "" <| \() s -> if String.isEmpty s then Err "must not be empty" else Ok s
    , resolvesAtField = Field.init "" <| \{now} s ->
        case Iso8601.toTime s of
          Err _ -> Err ""
          Ok t -> if Time.posixToMillis t < Time.posixToMillis now then Err "must be in the future" else Ok t
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
          Just pNoPct -> if pNoPct < 0 || pNoPct > 100 then Err "must be a number 0-100" else let highP = 1 - pNoPct/100 in
            if highP < lowP - epsilon then
              Err "prob wrong + prob right can't be >100"
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
    , disabled = False
    , now = Time.millisToPosix 0
    }
  , Task.perform Tick Time.now
  )

disable : Model -> Model
disable model = { model | disabled = True }
enable : Model -> Model
enable model = { model | disabled = False }

subscriptions : Model -> Sub Msg
subscriptions model =
  Time.every 1000 Tick

main : Program () Model Msg
main =
  Browser.element
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }
