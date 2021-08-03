port module Elements.ViewUser exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import API
import Utils exposing (RequestStatus(..), Username)

import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Globals
import Time
import Dict exposing (Dict)
import Biatob.Proto.Mvp exposing (Relationship)

port copy : String -> Cmd msg
port navigate : Maybe String -> Cmd msg
port authWidgetExternallyChanged : (AuthWidget.DomModification -> msg) -> Sub msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , who : Username
  , sendInvitationRequestStatus : RequestStatus
  , setTrustedRequestStatus : RequestStatus
  , predictionFilter : Filter
  , predictionSortOrder : SortOrder
  }


type alias Filter =
  { phase : Maybe LifecyclePhase
  }
type LifecyclePhase
  = Open
  | Closed
  | NeedsResolution
  | Resolved

type Msg
  = SetAuthWidget AuthWidget.State
  | SendInvitation
  | SendInvitationFinished Pb.SendInvitationRequest (Result Http.Error Pb.SendInvitationResponse)
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | SetTrusted Bool
  | SetTrustedFinished Pb.SetTrustedRequest (Result Http.Error Pb.SetTrustedResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | SetPredictionFilterPhase (Maybe LifecyclePhase)
  | SetPredictionSortOrder SortOrder
  | Copy String
  | Tick Time.Posix
  | AuthWidgetExternallyModified AuthWidget.DomModification
  | Ignore

init : JD.Value -> ( Model, Cmd Msg )
init flags =
  ( { globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
    , navbarAuth = AuthWidget.init
    , who = Utils.mustDecodeFromFlags JD.string "who" flags
    , sendInvitationRequestStatus = Unstarted
    , setTrustedRequestStatus = Unstarted
    , predictionFilter = { phase = Nothing }
    , predictionSortOrder = CreatedDate Desc
    }
  , Cmd.none
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetAuthWidget widgetState ->
      ( { model | navbarAuth = widgetState } , Cmd.none )
    SendInvitation ->
      ( { model | sendInvitationRequestStatus = AwaitingResponse }
      , let req = {recipient=model.who} in API.postSendInvitation (SendInvitationFinished req) req
      )
    SendInvitationFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSendInvitationResponse req res
                , sendInvitationRequestStatus = case API.simplifySendInvitationResponse res of
                    Ok _ -> Succeeded
                    Err e -> Failed e
        }
      , Cmd.none
      )
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
    SetTrusted trusted ->
      let req = {who=model.who, trusted=trusted} in
      ( { model | setTrustedRequestStatus = AwaitingResponse }
      , API.postSetTrusted (SetTrustedFinished req) req
      )
    SetTrustedFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSetTrustedResponse req res
                , setTrustedRequestStatus = case API.simplifySetTrustedResponse res of
                    Ok _ -> Unstarted
                    Err e -> Failed e
        }
      , Cmd.none
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
          Ok _ -> navigate <| Nothing
          Err _ -> Cmd.none
      )
    SetPredictionFilterPhase phase ->
      ( { model | predictionFilter = model.predictionFilter |> setPhase phase }
      , Cmd.none
      )
    SetPredictionSortOrder order ->
      ( { model | predictionSortOrder = order }
      , Cmd.none
      )
    Copy s ->
      ( model
      , copy s
      )
    Tick now ->
      ( { model | globals = model.globals |> Globals.tick now }
      , Cmd.none
      )
    AuthWidgetExternallyModified mod ->
      ( { model | navbarAuth = model.navbarAuth |> AuthWidget.handleDomModification mod }
      , Cmd.none
      )
    Ignore ->
      ( model , Cmd.none )

phaseDropdown : Utils.DropdownBuilder (Maybe LifecyclePhase) Msg
phaseDropdown =
  Utils.dropdown SetPredictionFilterPhase Ignore
    [ (Nothing, "all phases")
    , (Just Open, "open for betting")
    , (Just Closed, "betting closed, pre-resolution")
    , (Just NeedsResolution, "needs resolution")
    , (Just Resolved, "resolved")
    ]
orderDropdown : Utils.DropdownBuilder SortOrder Msg
orderDropdown =
  Utils.dropdown SetPredictionSortOrder Ignore
    [ (CreatedDate Desc, "date created, most recent first")
    , (CreatedDate Asc, "date created, oldest first")
    , (ResolutionDate Asc, "resolution deadline, most recent first")
    , (ResolutionDate Asc, "resolution deadline, oldest first")
    ]
viewControls : Filter -> SortOrder -> Html Msg
viewControls filter order =
  H.div []
  [ H.div [HA.class "d-inline-block mx-2 text-nowrap"]
    [ H.text " Phase: "
    , phaseDropdown filter.phase [HA.class "form-select d-inline-block w-auto"]
    ]
  , H.div [HA.class "d-inline-block mx-2 text-nowrap"]
    [ H.text " Order: "
    , orderDropdown order [HA.class "form-select d-inline-block w-auto"]
    ]
  ]

phaseMatches : Time.Posix -> LifecyclePhase -> Pb.UserPredictionView -> Bool
phaseMatches now phase prediction =
  if Utils.currentResolution prediction /= Pb.ResolutionNoneYet then
    phase == Resolved
  else if Utils.timeToUnixtime now < prediction.closesUnixtime then
    phase == Open
  else if Utils.timeToUnixtime now < prediction.resolvesAtUnixtime then
    phase == Closed
  else
    phase == NeedsResolution

setPhase : Maybe LifecyclePhase -> Filter -> Filter
setPhase phase filter = { filter | phase = phase }
filterMatches : Time.Posix -> Filter -> Pb.UserPredictionView -> Bool
filterMatches now filter prediction =
  case filter.phase of
    Nothing -> True
    Just phase -> phaseMatches now phase prediction

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
  [ cell [HA.class "col-2"] [info.predictedOn]
  , cell [HA.class "col-6"] [info.prediction]
  , cell [HA.class "col-2"] [info.resolution]
  ]

view : Model -> Browser.Document Msg
view model =
  {title=model.who, body=
    [ Navbar.view
        { setState = SetAuthWidget
        , logInUsername = LogInUsername
        , signOut = SignOut
        , ignore = Ignore
        , username = Globals.getOwnUsername model.globals
        , id = "navbar-auth"
        }
        model.navbarAuth
    , H.main_ [HA.class "container"]
    [ H.h2 [HA.class "text-center"] [H.text <| "User @" ++ model.who]
    , H.hr [] []
    , case Globals.getUserInfo model.globals of
        Nothing ->
          H.text "Log in to see your relationship with this user."
        Just settings ->
          if Globals.isSelf model.globals model.who then
            H.p []
            [ H.text "This is you! You might have meant to visit "
            , H.a [HA.href "/settings"] [H.text "your settings"]
            , H.text "?"
            ]
          else
            let
              (trustsYou, trustedByYou) = case Dict.get model.who (Utils.mustMapValues settings.relationships) of
                Nothing -> (False, False)
                Just rel -> (rel.trustsYou, rel.trustedByYou)
              haveSentInvitation = Dict.member model.who settings.invitations
              toggleTrustButton text =
                H.span []
                [ H.button
                  [ HA.disabled (model.setTrustedRequestStatus==AwaitingResponse)
                  , HE.onClick (SetTrusted (not trustedByYou))
                  , HA.class "btn btn-sm py-0 btn-outline-primary mx-1"
                  ]
                  [ H.text text ]
                , case model.setTrustedRequestStatus of
                    Unstarted -> H.text ""
                    AwaitingResponse -> H.text ""
                    Succeeded -> Utils.greenText "✓"
                    Failed e -> Utils.redText e
                ]
              sendInvitationButton text =
                H.span []
                [ H.button
                  [ HA.disabled (model.sendInvitationRequestStatus==AwaitingResponse)
                  , HE.onClick SendInvitation
                  , HA.class "btn btn-sm py-0 btn-outline-primary mx-1"
                  ]
                  [ H.text text ]
                , case model.sendInvitationRequestStatus of
                    Unstarted -> H.text ""
                    AwaitingResponse -> H.text ""
                    Succeeded -> Utils.greenText "✓"
                    Failed e -> Utils.redText e
                ]
            in
            H.div []
            [ H.ul []
              [ H.li []
                [ H.text "Trusts you: "
                , if trustsYou then
                    Utils.greenText "yes!"
                  else
                    Utils.redText "no."
                , if trustedByYou && not haveSentInvitation then
                    H.span []
                    [ sendInvitationButton "I think this person really does know and trust me!"
                    , H.span [HA.class "text-secondary"]
                      [ H.text "(I'll have to share your email address ("
                      , H.code [HA.style "color" "inherit"] [ H.text settings.emailAddress ]
                      , H.text ") with them to make sure.)"
                      ]
                    ]
                  else if haveSentInvitation then
                    H.div [] [H.text "I've sent this user an email asking them if they trust you. Just sit tight and wait for them to tell me they do!"]
                  else
                    H.text ""
                ]
              , H.li []
                [ H.text "Trusted by you: "
                , if trustedByYou then
                    H.span [] [Utils.greenText "yes!", H.text " (Mistake? Click ", toggleTrustButton "I don't trust this person!", H.text ")"]
                  else
                    H.span [] [Utils.redText "no.", H.text " ", toggleTrustButton "No, I actually do trust this person to uncomplainingly pay their debts when they lose a bet!"]
                ]
              ]
            ]
  , H.hr [] []
  , H.h3 [HA.class "text-center"] [H.text "Predictions made"]
  , H.div []
    [ viewControls model.predictionFilter model.predictionSortOrder
    , H.table [HA.class "table mt-1"]
        [ H.thead []
          [ viewRow
            { isHeader = True
            , predictedOn = H.text "Predicted on"
            , prediction = H.text "Prediction"
            , resolution = H.text "Resolution"
            }
          ]
        , model.globals.serverState.predictions
          |> Dict.toList
          |> List.filter (\(_, prediction) -> prediction.creator == model.who)
          |> sortPredictions (\(_, prediction) -> prediction) model.predictionSortOrder
          |> List.filter (\(_, prediction) -> filterMatches model.globals.now model.predictionFilter prediction)
          |> List.map (\(id, prediction) ->
              viewRow
              { isHeader = False
              , predictedOn = H.text <| Utils.yearMonthDayStr model.globals.timeZone (Utils.unixtimeToTime prediction.createdUnixtime)
              , prediction = H.a [HA.href <| Utils.pathToPrediction id] [H.text <| "By " ++ Utils.yearMonthDayStr model.globals.timeZone (Utils.unixtimeToTime prediction.resolvesAtUnixtime) ++ ", " ++ prediction.prediction]
              , resolution = case prediction.resolution |> Maybe.map .resolution of
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
  ]}

subscriptions : Model -> Sub Msg
subscriptions _ = authWidgetExternallyChanged AuthWidgetExternallyModified

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
