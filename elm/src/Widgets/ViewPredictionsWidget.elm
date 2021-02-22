module Widgets.ViewPredictionsWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Dict exposing (Dict)
import Time
import Http

import Biatob.Proto.Mvp as Pb
import Utils

import Widgets.PredictionWidget as PredictionWidget
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Widgets.StakeWidget as StakeWidget
import Widgets.CopyWidget as CopyWidget
import Task
import API

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
filterMatches : Time.Posix -> Filter -> Pb.UserPredictionView -> Bool
filterMatches now filter prediction =
  List.all identity
    [ filter.own
      |> Maybe.map ((==) (Utils.mustPredictionCreator prediction).isSelf)
      |> Maybe.withDefault True
    , filter.phase
      |> Maybe.map (\phase -> phaseMatches now phase prediction)
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
  { predictions : Dict Int (Pb.UserPredictionView, PredictionWidget.State)
  , filter : Filter
  , order : SortOrder
  , auth : Maybe Pb.AuthToken
  , now : Time.Posix
  , allowFilterByOwner : Bool
  , httpOrigin : String
  }

type Msg
  = PredictionEvent Int (Maybe PredictionWidget.Event) PredictionWidget.State
  | Tick Time.Posix
  | SetSortOrder SortOrder
  | SetFilter Filter
  | StakeFinished Int (Result Http.Error Pb.StakeResponse)
  | ResolveFinished Int (Result Http.Error Pb.ResolveResponse)
  | CreateInvitationFinished Int (Result Http.Error Pb.CreateInvitationResponse)
  | Ignore

viewPrediction : Int -> Model -> Maybe (Html Msg)
viewPrediction predictionId model =
  case Dict.get predictionId model.predictions of
    Nothing -> Nothing
    Just (prediction, widget) -> Just <|
      PredictionWidget.view
        { auth = model.auth
        , prediction = prediction
        , predictionId = predictionId
        , now = model.now
        , httpOrigin = model.httpOrigin
        , shouldLinkTitle = True
        , handle = PredictionEvent predictionId
        }
        widget

init : {auth: Maybe Pb.AuthToken, predictions:Dict Int Pb.UserPredictionView, httpOrigin:String} -> (Model, Cmd Msg)
init flags =
  ( { predictions = flags.predictions |> Dict.map (\_ p -> (p, PredictionWidget.init))
    , httpOrigin = flags.httpOrigin
    , filter = { own = Nothing , phase = Nothing }
    , order = CreatedDate Desc
    , auth = flags.auth
    , now = Utils.unixtimeToTime 0
    , allowFilterByOwner = True
    }
  , Task.perform Tick Time.now
  )

noFilterByOwner : Model -> Model
noFilterByOwner model = { model | allowFilterByOwner = False }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    PredictionEvent id event newWidget ->
      case Dict.get id model.predictions of
        Nothing -> Debug.todo "got message for unknown prediction"
        Just (prediction, _) ->
          ( { model | predictions = model.predictions |> Dict.insert id (prediction, newWidget) }
          , case event of
            Nothing -> Cmd.none
            Just (PredictionWidget.Copy s) -> CopyWidget.copy s
            Just (PredictionWidget.InvitationEvent (SmallInvitationWidget.Copy s)) -> CopyWidget.copy s
            Just (PredictionWidget.InvitationEvent SmallInvitationWidget.CreateInvitation) -> API.postCreateInvitation (CreateInvitationFinished id) {notes=""}
            Just (PredictionWidget.StakeEvent (StakeWidget.Staked {bettorIsASkeptic, bettorStakeCents})) -> API.postStake (StakeFinished id) {predictionId=id, bettorIsASkeptic=bettorIsASkeptic, bettorStakeCents=bettorStakeCents}
            Just (PredictionWidget.Resolve resolution) -> API.postResolve (ResolveFinished id) {predictionId=id, resolution=resolution, notes = ""}
          )
    Tick t ->
      ( { model | now = t }
      , Cmd.none
      )

    SetSortOrder order ->
      ( { model | order = order }
      , Cmd.none
      )

    SetFilter filter ->
      ( { model | filter = filter }
      , Cmd.none
      )
    CreateInvitationFinished id res ->
      ( { model | predictions = model.predictions |> Dict.update id (Maybe.map <| Tuple.mapSecond <| PredictionWidget.handleCreateInvitationResponse res) }
      , Cmd.none
      )
    StakeFinished id res ->
      ( { model | predictions = model.predictions |> Dict.update id (Maybe.map <| \(pred, widget) ->
                    ( case res |> Result.toMaybe |> Maybe.andThen .stakeResult of
                        Just (Pb.StakeResultOk newPred) -> newPred
                        _ -> pred
                    , widget |> PredictionWidget.handleStakeResponse res)
                    )
        }
      , Cmd.none
      )
    ResolveFinished id res ->
      ( { model | predictions = model.predictions |> Dict.update id (Maybe.map <| \(pred, widget) ->
                    ( case res |> Result.toMaybe |> Maybe.andThen .resolveResult of
                        Just (Pb.ResolveResultOk newPred) -> newPred
                        _ -> pred
                    , widget |> PredictionWidget.handleResolveResponse res)
                    )
        }
      , Cmd.none
      )

    Ignore -> ( model , Cmd.none )

view : Model -> Html Msg
view model =
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
        |> sortPredictions (\(_, (pred, _)) -> pred) model.order
        |> List.filter (\(_, (pred, _)) -> filterMatches model.now model.filter pred)
        |> List.map (\(id, _) -> H.div [HA.style "margin" "1em", HA.style "padding" "1em", HA.style "border" "1px solid black"] [viewPrediction id model |> Utils.must "id just came out of dict"])
        |> List.intersperse (H.hr [] [])
        |> H.div []
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Time.every 1000 Tick
