port module Elements.MyStakes exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as JD
import Http
import Dict

import Biatob.Proto.Mvp as Pb
import Utils

import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Globals
import Browser
import API
import Time
import Utils exposing (Username)

port navigate : Maybe String -> Cmd msg
port authWidgetExternallyChanged : (AuthWidget.DomModification -> msg) -> Sub msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , filter : Filter
  , order : SortOrder
  }

type alias Filter =
  { own : Maybe Bool
  , phase : Maybe LifecyclePhase
  }
type LifecyclePhase
  = Open
  | NeedsResolution
  | Resolved


type Msg
  = SetAuthWidget AuthWidget.State
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | AuthWidgetExternallyModified AuthWidget.DomModification
  | SetFilterOwn (Maybe Bool)
  | SetFilterPhase (Maybe LifecyclePhase)
  | SetSortOrder SortOrder
  | Ignore

init : JD.Value -> ( Model, Cmd Msg )
init flags =
  ( { globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
    , navbarAuth = AuthWidget.init
    , filter = { own = Nothing , phase = Nothing }
    , order = CreatedDate Desc
    }
  , Cmd.none
  )

view : Model -> Browser.Document Msg
view model =
  { title = "My stakes"
  , body =
    [ Navbar.view
        { setState = SetAuthWidget
        , logInUsername = LogInUsername
        , register = RegisterUsername
        , signOut = SignOut
        , ignore = Ignore
        , username = Globals.getOwnUsername model.globals
        , id = "navbar-auth"
        }
        model.navbarAuth
    , H.main_ [HA.class "container"]
      [ H.h2 [] [H.text "My Stakes"]
      , case Globals.getOwnUsername model.globals of
          Nothing -> H.text "You're not logged in!"
          Just self ->
            H.div []
            [ viewControls model
            , H.table [HA.class "table mt-1"]
                [ H.thead []
                  [ viewRow
                    { isHeader = True
                    , creator = H.text "Creator"
                    , predictedOn = H.text "Predicted on"
                    , prediction = H.text "Prediction"
                    , resolution = H.text "Resolution"
                    }
                  ]
                , model.globals.serverState.predictions
                  |> Dict.toList
                  |> sortPredictions (\(_, prediction) -> prediction) model.order
                  |> List.filter (\(_, prediction) -> filterMatches model.globals.now self model.filter prediction)
                  |> List.map (\(id, prediction) ->
                      viewRow
                      { isHeader = False
                      , creator = Utils.renderUser prediction.creator
                      , predictedOn = H.text <| Utils.dateStr model.globals.timeZone (Utils.unixtimeToTime prediction.createdUnixtime)
                      , prediction = H.a [HA.href <| Utils.pathToPrediction id] [H.text <| "By " ++ Utils.dateStr model.globals.timeZone (Utils.unixtimeToTime prediction.resolvesAtUnixtime) ++ ", " ++ prediction.prediction]
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
      ]
    ]
  }

viewControls : Model -> Html Msg
viewControls model =
  H.div [HA.class "row"]
  [ H.div [HA.class "col-md-3"]
    [ H.text "Creator: "
    , H.select
        [ HE.onInput <| \s -> SetFilterOwn (case s of
            "all owners" -> Nothing
            "my own" -> Just True
            "not mine" -> Just False
            _ -> Debug.todo <| "unrecognized value: " ++ s
            )
        , HA.value <| case model.filter.own of
            Nothing -> "all owners"
            Just True -> "my own"
            Just False -> "not mine"
        , HA.class "form-select d-inline-block w-auto"
        ]
        [ H.option [HA.value "all owners"] [H.text "all owners"]
        , H.option [HA.value "my own"] [H.text "my own"]
        , H.option [HA.value "not mine"] [H.text "not mine"]
        ]
    ]
  , H.div [HA.class "col-md-3"]
    [ H.text " Phase: "
    , H.select
        [ HE.onInput <| \s -> SetFilterPhase (case s of
            "all phases" -> Nothing
            "open" -> Just Open
            "needs resolution" -> Just NeedsResolution
            "resolved" -> Just Resolved
            _ -> Debug.todo <| "unrecognized value: " ++ s
            )
        , HA.value <| case model.filter.phase of
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
  , H.div [HA.class "col-md-3"]
    [ H.text " Order: "
    , H.select
      [ HE.onInput <| \s -> SetSortOrder (case s of
          "created, desc" -> CreatedDate Desc
          "created, asc" -> CreatedDate Asc
          "resolves, desc" -> ResolutionDate Asc
          "resolves, asc" -> ResolutionDate Asc
          _ -> Debug.todo <| "unrecognized value: " ++ s
        )
      , HA.value <| case model.order of
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
    ]
  ]

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

setOwn : Maybe Bool -> Filter -> Filter
setOwn own filter = { filter | own = own }
setPhase : Maybe LifecyclePhase -> Filter -> Filter
setPhase phase filter = { filter | phase = phase }
filterMatches : Time.Posix -> Username -> Filter -> Pb.UserPredictionView -> Bool
filterMatches now self filter prediction =
  ( case filter.own of
      Nothing -> True
      Just True -> prediction.creator == self
      Just False -> prediction.creator /= self
  ) && (
    case filter.phase of
      Nothing -> True
      Just phase -> phaseMatches now phase prediction
  )

type Ordering = Asc | Desc
sortKeySign : Ordering -> number
sortKeySign dir =
  case dir of
    Asc -> 1
    Desc -> -1
type SortOrder
  = ResolutionDate Ordering
  | CreatedDate Ordering

sortPredictions : (a -> Pb.UserPredictionView) -> SortOrder -> List a -> List a
sortPredictions toPrediction order predictions =
  case order of
    ResolutionDate dir ->
      List.sortBy (toPrediction >> \p -> p.resolvesAtUnixtime * sortKeySign dir) predictions
    CreatedDate dir ->
      List.sortBy (toPrediction >> \p -> p.createdUnixtime * sortKeySign dir) predictions

viewRow :
  { isHeader : Bool
  , creator : Html msg
  , predictedOn : Html msg
  , prediction : Html msg
  , resolution : Html msg
  } -> Html msg
viewRow info =
  let
    cell attrs content =
      if info.isHeader then
        H.th (HA.scope "col" :: attrs) content
      else
        H.td attrs content
  in
  H.tr []
  [ cell [HA.class "col-2"] [info.creator]
  , cell [HA.class "col-2"] [info.predictedOn]
  , cell [HA.class "col-6"] [info.prediction]
  , cell [HA.class "col-2"] [info.resolution]
  ]


update : Msg -> Model -> ( Model , Cmd Msg )
update msg model =
  case msg of
    SetAuthWidget widgetState ->
      ( { model | navbarAuth = widgetState } , Cmd.none )
    LogInUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postLogInUsername (LogInUsernameFinished req) req
      )
    LogInUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleLogInUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleLogInUsernameResponse res
        }
      , case API.simplifyLogInUsernameResponse res of
          Ok _ -> navigate <| Nothing
          Err _ -> Cmd.none
      )
    RegisterUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postRegisterUsername (RegisterUsernameFinished req) req
      )
    RegisterUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleRegisterUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleRegisterUsernameResponse res
        }
      , case API.simplifyRegisterUsernameResponse res of
          Ok _ -> navigate <| Nothing
          Err _ -> Cmd.none
      )
    SignOut widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postSignOut (SignOutFinished req) req
      )
    SignOutFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSignOutResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleSignOutResponse res
        }
      , case API.simplifySignOutResponse res of
          Ok _ -> navigate <| Just "/"
          Err _ -> Cmd.none
      )
    AuthWidgetExternallyModified mod ->
      ( { model | navbarAuth = model.navbarAuth |> AuthWidget.handleDomModification mod }
      , Cmd.none
      )
    SetFilterOwn own ->
      ( { model | filter = model.filter |> setOwn own }
      , Cmd.none
      )
    SetFilterPhase phase ->
      ( { model | filter = model.filter |> setPhase phase }
      , Cmd.none
      )
    SetSortOrder order ->
      ( { model | order = order }
      , Cmd.none
      )

    Ignore ->
      ( model , Cmd.none )

subscriptions : Model -> Sub Msg
subscriptions _ = authWidgetExternallyChanged AuthWidgetExternallyModified

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
