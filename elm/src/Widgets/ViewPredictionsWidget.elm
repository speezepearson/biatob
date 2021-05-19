module Widgets.ViewPredictionsWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Dict exposing (Dict)
import Time

import Biatob.Proto.Mvp as Pb
import Utils

import Widgets.PredictionWidget as PredictionWidget
import Page

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
filterMatches : Page.Globals -> Filter -> Pb.UserPredictionView -> Bool
filterMatches globals filter prediction =
  List.all identity
    [ filter.own
      |> Maybe.map ((==) (Page.isSelf globals prediction.creator))
      |> Maybe.withDefault True
    , filter.phase
      |> Maybe.map (\phase -> phaseMatches globals.now phase prediction)
      |> Maybe.withDefault True
    ]
viewFilterInput : Filter -> Html Msg
viewFilterInput filter =
  H.span []
    [ H.select
        [ HE.onInput <| \s -> case s of
            "all owners" -> SetFilter {filter | own = Nothing}
            "my own" -> SetFilter {filter | own = Just True}
            "not mine" -> SetFilter {filter | own = Just False}
            _ -> Debug.todo <| "unrecognized value: " ++ s
        , HA.value <| case filter.own of
            Nothing -> "all owners"
            Just True -> "my own"
            Just False -> "not mine"
        ]
        [ H.option [HA.value "all owners"] [H.text "all owners"]
        , H.option [HA.value "my own"] [H.text "my own"]
        , H.option [HA.value "not mine"] [H.text "not mine"]
        ]
    , H.select
        [ HE.onInput <| \s -> case s of
            "all phases" -> SetFilter {filter | phase = Nothing}
            "open" -> SetFilter {filter | phase = Just Open}
            "needs resolution" -> SetFilter {filter | phase = Just NeedsResolution}
            "resolved" -> SetFilter {filter | phase = Just Resolved}
            _ -> Debug.todo <| "unrecognized value: " ++ s
        , HA.value <| case filter.phase of
            Nothing -> "all phases"
            Just Open -> "open"
            Just NeedsResolution -> "needs resolution"
            Just Resolved -> "resolved"
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
viewSortOrderInput : SortOrder -> Html Msg
viewSortOrderInput order =
  H.select
    [ HE.onInput <| \s -> case s of
        "created, desc" -> SetSortOrder (CreatedDate Desc)
        "created, asc" -> SetSortOrder (CreatedDate Asc)
        "resolves, desc" -> SetSortOrder (ResolutionDate Asc)
        "resolves, asc" -> SetSortOrder (ResolutionDate Asc)
        _ -> Debug.todo <| "unrecognized value: " ++ s
    , HA.value <| case order of
        CreatedDate Desc -> "created, desc"
        CreatedDate Asc -> "created, asc"
        ResolutionDate Desc -> "resolves, desc"
        ResolutionDate Asc -> "resolves, asc"
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

type alias Model =
  { predictions : Dict Int PredictionWidget.Model
  , filter : Filter
  , order : SortOrder
  , allowFilterByOwner : Bool
  }

type Msg
  = PredictionMsg Int PredictionWidget.Msg
  | SetSortOrder SortOrder
  | SetFilter Filter
  | Ignore

init : Dict Int Pb.UserPredictionView -> Model
init predictions =
  { predictions = predictions |> Dict.map (\id p -> PredictionWidget.init id |> PredictionWidget.setLinkTitle True)
  , filter = { own = Nothing , phase = Nothing }
  , order = CreatedDate Desc
  , allowFilterByOwner = True
  }

noFilterByOwner : Model -> Model
noFilterByOwner model = { model | allowFilterByOwner = False }

update : Msg -> Model -> (Model, Page.Command Msg)
update msg model =
  case msg of
    PredictionMsg id widgetMsg ->
      case Dict.get id model.predictions of
        Nothing -> Debug.todo "got message for unknown prediction"
        Just widget ->
          let
            (newWidget, widgetCmd) = PredictionWidget.update widgetMsg widget
          in
          ( { model | predictions = model.predictions |> Dict.insert id newWidget }
          , Page.mapCmd (PredictionMsg id) widgetCmd
          )

    SetSortOrder order ->
      ( { model | order = order }
      , Page.NoCmd
      )

    SetFilter filter ->
      ( { model | filter = filter }
      , Page.NoCmd
      )

    Ignore -> ( model , Page.NoCmd )

view : Page.Globals -> Model -> Html Msg
view globals model =
  H.div []
    [ if model.allowFilterByOwner then
        H.span [] [H.text "Filter: ", viewFilterInput model.filter]
      else
        H.text ""
    , H.text " Sort: "
    , viewSortOrderInput model.order
    , H.hr [] []
    , if Dict.isEmpty model.predictions then
        H.text "<none>"
      else
        model.predictions
        |> Dict.toList
        |> sortPredictions (\(id, _) -> Utils.must "TODO" (Dict.get id globals.serverState.predictions)) model.order
        |> List.filter (\(id, _) -> filterMatches globals model.filter (Utils.must "TODO" (Dict.get id globals.serverState.predictions)))
        |> List.map (\(id, widget) ->
            H.div [HA.style "margin" "1em", HA.style "padding" "1em", HA.style "border" "1px solid black"]
              [PredictionWidget.view globals widget |> H.map (PredictionMsg id)])
        |> List.intersperse (H.hr [] [])
        |> H.div []
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
