module MyStakesPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as JD
import Dict exposing (Dict)
import Time

import Biatob.Proto.Mvp as Pb
import Utils

import Biatob.Proto.Mvp exposing (StakeResult(..))
import ViewPredictionPage
import Task

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
  { predictions : Dict Int ViewPredictionPage.Model
  , filter : Filter
  , order : SortOrder
  , auth : Pb.AuthToken
  , now : Time.Posix
  }

type Msg
  = PredictionPageMsg Int ViewPredictionPage.Msg
  | Tick Time.Posix
  | SetSortOrder SortOrder
  | SetFilter Filter

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    auth : Pb.AuthToken
    auth =  Utils.mustDecodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    predictions : Dict Int Pb.UserPredictionView
    predictions = Utils.mustDecodePbFromFlags Pb.predictionsByIdDecoder "predictionsPbB64" flags |> Utils.mustPredictionsById

    linkToAuthority = Utils.mustDecodeFromFlags JD.string "linkToAuthority" flags

    subinits : Dict Int (ViewPredictionPage.Model, Cmd ViewPredictionPage.Msg)
    subinits =
      Dict.map
        (\id m ->
          let (submodel, subcmd) = ViewPredictionPage.initBase {predictionId=id, prediction=m, auth=Just auth, now=Time.millisToPosix 0, linkToAuthority=linkToAuthority} in
          (submodel, subcmd)
        )
        predictions
  in
  ( { predictions = Dict.map (\_ (submodel, _) -> submodel) subinits
    , filter = { own = Nothing , phase = Nothing }
    , order = CreatedDate Desc
    , auth = auth
    , now = Time.millisToPosix 0
    }
  , Cmd.batch
    <| (::) (Task.perform Tick Time.now)
    <| List.map (\(id, (_, subcmd)) -> Cmd.map (PredictionPageMsg id) subcmd) <| Dict.toList subinits
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    PredictionPageMsg predictionId predictionPageMsg ->
      case Dict.get predictionId model.predictions of
        Nothing -> Debug.todo "got message for unknown prediction"
        Just predictionPage ->
          let (newPredictionPage, predictionPageCmd) = ViewPredictionPage.update predictionPageMsg predictionPage in
          ( { model | predictions = model.predictions |> Dict.insert predictionId newPredictionPage }
          , Cmd.map (PredictionPageMsg predictionId) predictionPageCmd
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


view : Model -> Html Msg
view model =
  H.div []
    [ H.h2 [] [H.text "My Stakes"]
    , H.text "Filter: "
    , viewFilterInput model.filter
    , H.text " Sort: "
    , viewSortOrderInput model.order
    , H.hr [] []
    , if Dict.isEmpty model.predictions then
        H.div []
          [ H.text "You haven't participated in any predictions yet!"
          , H.br [] []
          , H.text "Maybe you want to "
          , H.a [HA.href "/new"] [H.text "create one"]
          , H.text "?"
          ]
      else
        model.predictions
        |> Dict.toList
        |> sortPredictions (\(_, m) -> m.prediction) model.order
        |> List.filter (\(_, m) -> filterMatches model.now model.filter m.prediction)
        |> List.map (\(id, m) -> H.div [HA.style "margin" "1em", HA.style "padding" "1em", HA.style "border" "1px solid black"] [ViewPredictionPage.view m |> H.map (PredictionPageMsg id)])
        |> List.intersperse (H.hr [] [])
        |> H.div []
    ]

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
  <| List.map (\(id, m) -> ViewPredictionPage.subscriptions m |> Sub.map (PredictionPageMsg id))
  <| Dict.toList model.predictions

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
