module Widgets.ViewPredictionsWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Dict exposing (Dict)
import Time

import Biatob.Proto.Mvp as Pb
import Utils exposing (PredictionId, Username)

type alias Config msg =
  { setState : State -> msg
  , predictions : Dict PredictionId Pb.UserPredictionView
  , allowFilterByOwner : Bool
  , self : Username
  , now : Time.Posix
  , timeZone : Time.Zone
  }
type alias State =
  { filter : Filter
  , order : SortOrder
  }

type LifecyclePhase
  = Open
  | NeedsResolution
  | Resolved
phaseMatches : Time.Posix -> LifecyclePhase -> Pb.UserPredictionView -> Bool
phaseMatches now phase prediction =
  case phase of
    Open ->
      Utils.currentResolution prediction == Pb.ResolutionNoneYet
      && prediction.closesUnixtime > Utils.timeToUnixtime now
      && prediction.resolvesAtUnixtime > Utils.timeToUnixtime now
    NeedsResolution ->
      Utils.currentResolution prediction == Pb.ResolutionNoneYet
      && prediction.resolvesAtUnixtime < Utils.timeToUnixtime now
    Resolved ->
      Utils.currentResolution prediction /= Pb.ResolutionNoneYet

type alias Filter =
  { own : Maybe Bool
  , phase : Maybe LifecyclePhase
  }
setOwn : Maybe Bool -> Filter -> Filter
setOwn own filter = { filter | own = own }
setPhase : Maybe LifecyclePhase -> Filter -> Filter
setPhase phase filter = { filter | phase = phase }
filterMatches : Config msg -> Filter -> Pb.UserPredictionView -> Bool
filterMatches config filter prediction =
  ( case filter.own of
      Nothing -> True
      Just True -> prediction.creator == config.self
      Just False -> prediction.creator /= config.self
  ) && (
    case filter.phase of
      Nothing -> True
      Just phase -> phaseMatches config.now phase prediction
  )
viewFilterInput : Config msg -> State -> Html msg
viewFilterInput config state =
  H.span []
    [ H.select
        [ HE.onInput <| \s -> config.setState {state | filter = state.filter |> setOwn (case s of
            "all owners" -> Nothing
            "my own" -> Just True
            "not mine" -> Just False
            _ -> Debug.todo <| "unrecognized value: " ++ s
            )}
        , HA.value <| case state.filter.own of
            Nothing -> "all owners"
            Just True -> "my own"
            Just False -> "not mine"
        , HA.class "form-select d-inline-block w-auto"
        ]
        [ H.option [HA.value "all owners"] [H.text "all owners"]
        , H.option [HA.value "my own"] [H.text "my own"]
        , H.option [HA.value "not mine"] [H.text "not mine"]
        ]
    , H.select
        [ HE.onInput <| \s -> config.setState {state | filter = state.filter |> setPhase (case s of
            "all phases" -> Nothing
            "open" -> Just Open
            "needs resolution" -> Just NeedsResolution
            "resolved" -> Just Resolved
            _ -> Debug.todo <| "unrecognized value: " ++ s
          )}
        , HA.value <| case state.filter.phase of
            Nothing -> "all phases"
            Just Open -> "open"
            Just NeedsResolution -> "needs resolution"
            Just Resolved -> "resolved"
        , HA.class "form-select d-inline-block w-auto"
        ]
        [ H.option [HA.value "all phases"] [H.text "all phases"]
        , H.option [HA.value "open"] [H.text "open"]
        , H.option [HA.value "needs resolution"] [H.text "needs resolution"]
        , H.option [HA.value "resolved"] [H.text "resolved"]
        ]
    ]

type Ordering = Asc | Desc
sortKeySign : Ordering -> number
sortKeySign dir =
  case dir of
    Asc -> 1
    Desc -> -1
type SortOrder
  = ResolutionDate Ordering
  | CreatedDate Ordering
viewSortOrderInput : Config msg -> State -> Html msg
viewSortOrderInput config state =
  H.select
    [ HE.onInput <| \s -> config.setState {state | order = case s of
        "created, desc" -> CreatedDate Desc
        "created, asc" -> CreatedDate Asc
        "resolves, desc" -> ResolutionDate Asc
        "resolves, asc" -> ResolutionDate Asc
        _ -> Debug.todo <| "unrecognized value: " ++ s
      }
    , HA.value <| case state.order of
        CreatedDate Desc -> "created, desc"
        CreatedDate Asc -> "created, asc"
        ResolutionDate Desc -> "resolves, desc"
        ResolutionDate Asc -> "resolves, asc"
    , HA.class "form-select d-inline-block w-auto"
    ]
    [ H.option [HA.value "created, desc"] [H.text "created, desc"]
    , H.option [HA.value "created, asc"] [H.text "created, asc"]
    , H.option [HA.value "resolves, desc"] [H.text "resolves, desc"]
    , H.option [HA.value "resolves, asc"] [H.text "resolves, asc"]
    ]

sortPredictions : (a -> Pb.UserPredictionView) -> SortOrder -> List a -> List a
sortPredictions toPrediction order predictions =
  case order of
    ResolutionDate dir ->
      List.sortBy (toPrediction >> \p -> p.resolvesAtUnixtime * sortKeySign dir) predictions
    CreatedDate dir ->
      List.sortBy (toPrediction >> \p -> p.createdUnixtime * sortKeySign dir) predictions

init : State
init =
  { filter = { own = Nothing , phase = Nothing }
  , order = CreatedDate Desc
  }

view : Config msg -> State -> Html msg
view config state =
  H.div []
    [ if config.allowFilterByOwner then
        H.span [] [H.text "Filter: ", viewFilterInput config state]
      else
        H.text ""
    , H.text " Sort: "
    , viewSortOrderInput config state
    , if Dict.isEmpty config.predictions then
        H.text "<none>"
      else
        H.table [HA.class "table mt-1"]
        [ H.thead []
          [ viewRow
            { cell = H.th
            , created = H.text "Predicted"
            , creator = if config.allowFilterByOwner then Just (H.text "Creator") else Nothing
            , resolves = H.text "Resolves"
            , prediction = H.text "Prediction"
            , resolution = H.text "Resolution"
            }
          ]
        , config.predictions
          |> Dict.toList
          |> sortPredictions (\(_, prediction) -> prediction) state.order
          |> List.filter (\(_, prediction) -> filterMatches config state.filter prediction)
          |> List.map (\(id, prediction) ->
              viewRow
                { cell = H.td
                , created = H.text <| Utils.dateStr config.timeZone (Utils.unixtimeToTime prediction.createdUnixtime)
                , creator = if config.allowFilterByOwner then Just (Utils.renderUser prediction.creator) else Nothing
                , resolves = H.text <| Utils.dateStr config.timeZone (Utils.unixtimeToTime prediction.resolvesAtUnixtime)
                , prediction = H.a [HA.href <| Utils.pathToPrediction id] [H.text prediction.prediction]
                , resolution = case List.head (List.reverse prediction.resolutions) |> Maybe.map .resolution of
                    Nothing -> H.text ""
                    Just Pb.ResolutionNoneYet -> H.text ""
                    Just Pb.ResolutionYes -> H.text "Yes"
                    Just Pb.ResolutionNo -> H.text "No"
                    Just Pb.ResolutionInvalid -> H.text "Invalid!"
                    Just (Pb.ResolutionUnrecognized_ _) -> Debug.todo "unrecognized resolution"
                })
          |> H.tbody []
        ]
    ]

viewRow :
  { cell : List (H.Attribute msg) -> List (Html msg) -> Html msg
  , created : Html msg
  , creator : Maybe (Html msg)
  , resolves : Html msg
  , prediction : Html msg
  , resolution : Html msg
  } -> Html msg
viewRow info =
  H.tr []
  [ info.cell [HA.class "col-1"] [info.created]
  , case info.creator of
      Nothing -> H.text ""
      Just creator -> info.cell [HA.class "col-1"] [creator]
  , info.cell [HA.class "col-1"] [info.resolves]
  , info.cell [HA.class "col-1"] [info.resolution]
  , info.cell [HA.class "col-6"] [info.prediction]
  ]
