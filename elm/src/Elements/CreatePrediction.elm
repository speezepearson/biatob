port module Elements.CreatePrediction exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD
import Time
import Iso8601

import Biatob.Proto.Mvp as Pb
import Utils exposing (i, Cents)

import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Widgets.PredictionWidget as PredictionWidget
import Utils
import Globals
import API

port navigate : Maybe String -> Cmd msg

maxLegalStakeCents = 500000
epsilon = 0.000001

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , predictionField : String
  , resolvesAtField : String
  , stakeField : String
  , lowPField : String
  , highPField : String
  , openForUnitField : String
  , openForSecondsField : String
  , specialRulesField : String
  , previewWidget : PredictionWidget.State
  , working : Bool
  , createError : Maybe String
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
  | SetAuthWidget AuthWidget.State
  | SetPreviewWidget PredictionWidget.State
  | Create
  | CreateFinished Pb.CreatePredictionRequest (Result Http.Error Pb.CreatePredictionResponse)
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | Tick Time.Posix
  | Ignore


type OpenForUnit = Days | Weeks
unitToSeconds : OpenForUnit -> Int
unitToSeconds u =
  case u of
    Days -> 60 * 60 * 24
    Weeks -> unitToSeconds Days * 7

buildCreateRequest : Model -> Maybe Pb.CreatePredictionRequest
buildCreateRequest model =
  parsePrediction model |> Result.toMaybe |> Maybe.andThen (\prediction ->
  parseResolvesAt model.globals.now model |> Result.toMaybe |> Maybe.andThen (\resolvesAt ->
  parseStake model |> Result.toMaybe |> Maybe.andThen (\stake ->
  parseLowProbability model |> Result.toMaybe |> Maybe.andThen (\lowP ->
  parseHighProbability model |> Result.toMaybe |> Maybe.andThen (\highP -> if highP < lowP then Nothing else
  parseOpenForSeconds model.globals.now model |> Result.toMaybe |> Maybe.andThen (\openForSeconds ->
    Just
      { prediction = prediction
      , certainty = Just { low=lowP, high=highP }
      , maximumStakeCents = stake
      , openSeconds = openForSeconds
      , specialRules = model.specialRulesField
      , resolvesAtUnixtime = Utils.timeToUnixtime resolvesAt
      }
  ))))))

parsePrediction : Model -> Result String String
parsePrediction model =
  if String.isEmpty model.predictionField then
    Err "must not be empty"
  else
    Ok model.predictionField

parseResolvesAt : Time.Posix -> Model -> Result String Time.Posix
parseResolvesAt now model =
    case Iso8601.toTime (Debug.log "raw field" model.resolvesAtField) |> Debug.log "parsed" of
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

init : JD.Value -> ( Model , Cmd Msg )
init flags =
  ( { globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
    , navbarAuth = AuthWidget.init
    , predictionField = ""
    , resolvesAtField = ""
    , stakeField = "20"
    , lowPField = "50"
    , highPField = "100"
    , openForUnitField = "weeks"
    , openForSecondsField = "2"
    , specialRulesField = ""
    , previewWidget = PredictionWidget.init
    , working = False
    , createError = Nothing
    }
  , Cmd.none
  )

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    SetPredictionField s -> ( { model | predictionField = s } , Cmd.none )
    SetResolvesAtField s -> ( { model | resolvesAtField = s } , Cmd.none )
    SetStakeField s -> ( { model | stakeField = s } , Cmd.none )
    SetLowPField s -> ( { model | lowPField = s } , Cmd.none )
    SetHighPField s -> ( { model | highPField = s } , Cmd.none )
    SetOpenForUnitField s -> ( { model | openForUnitField = s } , Cmd.none )
    SetOpenForSecondsField s -> ( { model | openForSecondsField = s } , Cmd.none )
    SetSpecialRulesField s -> ( { model | specialRulesField = s } , Cmd.none )
    SetAuthWidget widgetState ->
      ( { model | navbarAuth = widgetState } , Cmd.none )
    SetPreviewWidget widgetState ->
      ( { model | previewWidget = widgetState } , Cmd.none )
    Create ->
      case buildCreateRequest model of
        Just req ->
          ( { model | working = True , createError = Nothing }
          , API.postCreatePrediction (CreateFinished req) req
          )
        Nothing ->
          ( { model | createError = Just "bad form" } -- TODO: improve error message
          , Cmd.none
          )
    CreateFinished req res ->
      ( { model | globals = model.globals |> Globals.handleCreatePredictionResponse req res
                , working = False
                , createError = case API.simplifyCreatePredictionResponse res of
                    Ok _ -> Nothing
                    Err e -> Just e
        }
      , navigate <| case API.simplifyCreatePredictionResponse res of
          Ok predictionId -> Just <| "/p/" ++ String.fromInt predictionId
          Err _ -> Nothing
      )
    LogInUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postLogInUsername (LogInUsernameFinished req) req
      )
    LogInUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleLogInUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleLogInUsernameResponse res
        }
      , navigate Nothing
      )
    RegisterUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postRegisterUsername (RegisterUsernameFinished req) req
      )
    RegisterUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleRegisterUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleRegisterUsernameResponse res
        }
      , navigate Nothing
      )
    SignOut widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postSignOut (SignOutFinished req) req
      )
    SignOutFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSignOutResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleSignOutResponse res
        }
      , navigate <| Just "/"
      )
    Tick now ->
      ( { model | globals = model.globals |> Globals.tick now }
      , Cmd.none
      )
    Ignore ->
      (model, Cmd.none)

rationalApprox : {x: Float, tolerance: Float} -> (Int, Int)
rationalApprox {x, tolerance} =
  let
    help : Int -> Int -> (Int, Int)
    help num denom =
      let ratio = toFloat num / toFloat denom in
      if abs (ratio - x) < tolerance then
        (num, denom)
      else if ratio > x then
        help num (denom+1)
      else
        help (num+1) denom
  in
    help 0 1

viewForm : Model -> Html Msg
viewForm model =
  let
    disabled = not <| Globals.isLoggedIn model.globals
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
              |> Utils.appendValidationError (Utils.resultToErr (parseResolvesAt model.globals.now model))
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
            [ H.text "I think that this has at least a "
            , H.input
                [ HA.type_ "number", HA.min "0", HA.max "100", HA.step "any"
                , HA.style "width" "5em"
                , HA.disabled disabled
                , HE.onInput SetLowPField
                , HA.value model.lowPField
                ] []
            , H.text "% chance of happening (i.e. about "
            , let
                (num, denom) = case parseLowProbability model of
                  Err _ -> ("???", "???")
                  Ok lowP -> let (n,d) = rationalApprox {x=lowP, tolerance=0.1 * min lowP (1-lowP)} in (String.fromInt n, String.fromInt d)
              in
                H.text <| num ++ " out of " ++ denom
            , H.text ")."
            , H.br [] []
            , H.details []
              [ H.summary [HA.style "text-align" "right"] [H.text "Set upper bound too?"]
              , H.text "...but I think that it would be overconfident to assign it more than a "
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
            , H.details []
                [ H.summary [HA.style "text-align" "right"] [H.text "Confusing?"]

                , H.p [] [H.text "Yeah, this is startlingly difficult to think about! Here are some roughly equivalent statements:"]
                , H.ul []
                  [ H.li []
                    [ H.text "I think a significant number of my friends assign this a probability below "
                    , Utils.b <| model.lowPField ++ "%"
                    , H.text ", and I'm pretty sure that they're being too hasty to dismiss this."
                    , case parseHighProbability model of
                        Ok highP ->
                          if highP > 0.9999 then H.text "" else
                          H.span []
                          [ H.text " And other friends assign this a probability higher than "
                          , Utils.b <| model.highPField ++ "%"
                          , H.text " -- I think they're overconfident that this will happen."
                          ]
                        Err _ -> H.text ""
                    ]
                  , H.li []
                    [ H.text "I'm pretty sure that, if I researched this question pretty carefully, and at the end of the day I had to put a single number on it,"
                    , H.text " I would end up assigning it a probability between "
                    , Utils.b <| model.lowPField ++ "%"
                    , case parseHighProbability model of
                        Ok highP ->
                          if highP > 0.9999 then H.text "" else
                          H.span []
                          [ H.text " and "
                          , Utils.b <| model.highPField ++ "%"
                          ]
                        Err _ -> H.text ""
                    , H.text ". If I assigned a number outside that range, I must have learned something really surprising, something that changed my mind significantly!"
                    ]
                  , H.li []
                    [ H.text "I would pay one of my friends about "
                    , Utils.b <| "$" ++ model.lowPField
                    , H.text " for an \"IOU $100 if [this prediction comes true]\" note"
                    , case parseHighProbability model of
                        Ok highP ->
                          if highP > 0.9999 then H.text "" else
                          H.span []
                          [ H.text ", or sell them such an IOU for about "
                          , Utils.b <| "$" ++ model.highPField
                          ]
                        Err _ -> H.text ""
                    , H.text "."
                    ]
                  ]
                , H.p [] [H.text <| "You can think of the spread as being a measurement of how confident you are:"
                    ++ " a small spread, like 70-73%, means you've thought about this ", i "really carefully,", H.text <| " and"
                    ++ " you don't expect your opinion to be budged by any of your friends' bets or any new information that comes out"
                    ++ " before betting closes; a wide spread, like 30-95%, is sort of off-the-cuff, you just want to throw it out there that"
                    ++ " it's ", i "pretty likely", H.text <| " but you haven't thought ", i "that", H.text <| " hard about it."
                    ++ " Predictions don't have to be effortful, painstakingly researched things!"
                    ++ " It's okay to throw out half-formed thoughts with wide spreads."
                    ]
                , H.p [] [H.text <| "If you still confused, hey, don't worry about it! This is really remarkably counterintuitive stuff."
                    ++ " Just leave the high probability at 100%."
                    ]
                ]
              ]
            , case parseLowProbability model of
                Ok lowP ->
                  if lowP == 0 then
                    H.div [HA.style "opacity" "50%"]
                      [ H.text "A low probability of 0 means you're actually only willing to bet "
                      , i "against"
                      , H.text <| " your prediction, which might be confusing to your friends."
                        ++ " Consider negating your prediction (\"there will be at least 40k gun deaths\" -> \"there will be fewer than 40k gun deaths\") to make things clearer."
                      ]
                  else
                    H.text ""
                _ -> H.text ""
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
              |> Utils.appendValidationError (Utils.resultToErr (parseOpenForSeconds model.globals.now model))
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
                , H.text <| "If it's Jan 1, and you're betting about how many book reviews Scott Alexander will have published by Dec 31,"
                    ++ " you don't want people to be able to wait until Dec 30 before betting against you --"
                    ++ " the question is essentially already answered at that point!"
                    ++ " So, you might only accept bets for a week or two, to give your friends time to bet against you,"
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

view : Model -> Browser.Document Msg
view model =
  { title="New prediction"
  , body =
    [ Navbar.view
        { setState = SetAuthWidget
        , logInUsername = LogInUsername
        , register = RegisterUsername
        , signOut = SignOut
        , ignore = Ignore
        , auth = Globals.getAuth model.globals
        }
        model.navbarAuth
    , H.main_ []
    [ H.h2 [] [H.text "New Prediction"]
    , case Globals.getAuth model.globals of
       Just _ -> H.text ""
       Nothing ->
        H.div []
          [ H.span [HA.style "color" "red"] [H.text "You need to log in to create a new prediction!"]
          , H.hr [] []
          ]
    , viewForm model
    , H.div [HA.style "text-align" "center", HA.style "margin-bottom" "2em"]
        [ H.button
            [ HE.onClick Create
            , HA.disabled (not (Globals.isLoggedIn model.globals) || buildCreateRequest model == Nothing || model.working)
            ]
            [ H.text <| if Globals.isLoggedIn model.globals then "Create" else "Log in to create" ]
        ]
    , case model.createError of
        Just e -> H.div [HA.style "color" "red"] [H.text e]
        Nothing -> H.text ""
    , H.hr [] []
    , H.text "Preview:"
    , H.div [HA.style "border" "1px solid black", HA.style "padding" "1em", HA.style "margin" "1em"]
        [ case buildCreateRequest model of
            Just req ->
              previewPrediction {request=req, creatorName=Globals.getAuth model.globals |> Maybe.map .owner |> Maybe.withDefault "you", createdAt=model.globals.now}
              |> (\prediction -> PredictionWidget.view
                    { setState = SetPreviewWidget
                    , copy = \_ -> Ignore
                    , stake = \_ _ -> Ignore
                    , resolve = \_ _ -> Ignore
                    , invitationWidget = H.text "TODO"
                    , linkTitle = False
                    , disableCommit = True
                    , predictionId = 12345
                    , prediction = prediction
                    , httpOrigin = model.globals.httpOrigin
                    , creatorRelationship = Globals.Friends
                    , timeZone = model.globals.timeZone
                    , now = model.globals.now
                    }
                    PredictionWidget.init
                    |> H.map (always Ignore))
            Nothing ->
              H.span [HA.style "color" "red"] [H.text "(invalid prediction)"]
        ]
    ]]}

previewPrediction : {request:Pb.CreatePredictionRequest, creatorName:String, createdAt:Time.Posix} -> Pb.UserPredictionView
previewPrediction {request, creatorName, createdAt} =
  { prediction = request.prediction
  , certainty = request.certainty
  , maximumStakeCents = request.maximumStakeCents
  , remainingStakeCentsVsBelievers = request.maximumStakeCents
  , remainingStakeCentsVsSkeptics = request.maximumStakeCents
  , createdUnixtime = Utils.timeToUnixtime createdAt
  , closesUnixtime = Utils.timeToUnixtime createdAt + toFloat request.openSeconds
  , specialRules = request.specialRules
  , creator = creatorName
  , resolutions = []
  , yourTrades = []
  , resolvesAtUnixtime = request.resolvesAtUnixtime
  }

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
