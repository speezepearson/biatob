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
import Utils exposing (i, isOk, maxLegalStakeCents, viewError, Cents, RequestStatus(..))
import Elements.Prediction as Prediction

import Widgets.AuthWidget as AuthWidget
import Widgets.EmailSettingsWidget as EmailSettingsWidget
import Widgets.Navbar as Navbar
import Globals
import API

port navigate : Maybe String -> Cmd msg
port authWidgetExternallyChanged : (AuthWidget.DomModification -> msg) -> Sub msg

epsilon = 0.000001

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , emailSettingsWidget : EmailSettingsWidget.State
  , predictionField : String
  , resolvesAtField : String
  , stakeField : String
  , lowPField : String
  , highPField : String
  , openForUnitField : String
  , openForSecondsField : String
  , specialRulesField : String
  , createRequestStatus : RequestStatus
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
  | SetEmailWidget EmailSettingsWidget.State
  | Create
  | CreateFinished Pb.CreatePredictionRequest (Result Http.Error Pb.CreatePredictionResponse)
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | SetEmail EmailSettingsWidget.State Pb.SetEmailRequest
  | SetEmailFinished Pb.SetEmailRequest (Result Http.Error Pb.SetEmailResponse)
  | UpdateSettings EmailSettingsWidget.State Pb.UpdateSettingsRequest
  | UpdateSettingsFinished Pb.UpdateSettingsRequest (Result Http.Error Pb.UpdateSettingsResponse)
  | VerifyEmail EmailSettingsWidget.State Pb.VerifyEmailRequest
  | VerifyEmailFinished Pb.VerifyEmailRequest (Result Http.Error Pb.VerifyEmailResponse)
  | Tick Time.Posix
  | AuthWidgetExternallyModified AuthWidget.DomModification
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
  parseResolvesAt model |> Result.toMaybe |> Maybe.andThen (\resolvesAt ->
  parseStake model |> Result.toMaybe |> Maybe.andThen (\stake ->
  parseLowProbability model |> Result.toMaybe |> Maybe.andThen (\lowP ->
  parseHighProbability model |> Result.toMaybe |> Maybe.andThen (\highP -> if highP < lowP then Nothing else
  parseOpenForSeconds model |> Result.toMaybe |> Maybe.andThen (\openForSeconds ->
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

parseResolvesAt : Model -> Result String Time.Posix
parseResolvesAt model =
    case Iso8601.toTime model.resolvesAtField of
      Err _ -> Err ""
      Ok t -> if Utils.timeToUnixtime t < Utils.timeToUnixtime model.globals.now then Err "must be in the future" else Ok t

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
          else if lowP == 0 then
            Err "must be positive (else your \"prediction\" is bland and meaningless)"
          else if lowP == 1 then
            Err "assigning something a probability of \"at least 100%\" is insanely overconfident! Please, settle for 99.999%!"
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
          else if highP < minAllowed - epsilon then
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

parseOpenForSeconds : Model -> Result String Int
parseOpenForSeconds model =
    case String.toInt model.openForSecondsField of
      Nothing -> Err "must be a positive integer"
      Just n ->
        if n <= 0 then
          Err "must be a positive integer"
        else
          let nSec = n * unitToSeconds (parseOpenForUnit model) in
          case parseResolvesAt model of
            Err _ -> Ok nSec
            Ok t ->
              if Time.posixToMillis model.globals.now + 1000 * nSec > Time.posixToMillis t then
                Err "must close before prediction resolves"
              else
                Ok nSec

init : JD.Value -> ( Model , Cmd Msg )
init flags =
  ( { globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
    , navbarAuth = AuthWidget.init
    , emailSettingsWidget = EmailSettingsWidget.init
    , predictionField = ""
    , resolvesAtField = ""
    , stakeField = "20"
    , lowPField = "50"
    , highPField = "100"
    , openForUnitField = "weeks"
    , openForSecondsField = "2"
    , specialRulesField = ""
    , createRequestStatus = Unstarted
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
    SetEmailWidget widgetState ->
      ( { model | emailSettingsWidget = widgetState } , Cmd.none )
    Create ->
      case buildCreateRequest model of
        Just req ->
          ( { model | createRequestStatus = AwaitingResponse }
          , API.postCreatePrediction (CreateFinished req) req
          )
        Nothing ->
          ( { model | createRequestStatus = Failed "invalid form; how did you even click that button?" }
          , Cmd.none
          )
    CreateFinished req res ->
      ( { model | globals = model.globals |> Globals.handleCreatePredictionResponse req res
                , createRequestStatus = case API.simplifyCreatePredictionResponse res of
                    Ok _ -> Succeeded
                    Err e -> Failed e
        }
      , case API.simplifyCreatePredictionResponse res of
          Ok predictionId -> navigate <| Just <| Utils.pathToPrediction predictionId
          Err _ -> Cmd.none
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
          Ok _ -> navigate Nothing
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
          Ok _ -> navigate Nothing
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
          Ok _ -> navigate Nothing
          Err _ -> Cmd.none
      )
    SetEmail widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , API.postSetEmail (SetEmailFinished req) req
      )
    SetEmailFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSetEmailResponse req res
                , emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleSetEmailResponse res
        }
      , Cmd.none
      )
    UpdateSettings widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , API.postUpdateSettings (UpdateSettingsFinished req) req
      )
    UpdateSettingsFinished req res ->
      ( { model | globals = model.globals |> Globals.handleUpdateSettingsResponse req res
                , emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleUpdateSettingsResponse res
        }
      , Cmd.none
      )
    VerifyEmail widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , API.postVerifyEmail (VerifyEmailFinished req) req
      )
    VerifyEmailFinished req res ->
      ( { model | globals = model.globals |> Globals.handleVerifyEmailResponse req res
                , emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleVerifyEmailResponse res
        }
      , Cmd.none
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
      (model, Cmd.none)

rationalApprox : {x: Float, tolerance: Float} -> Maybe (Int, Int)
rationalApprox {x, tolerance} =
  let
    denominators = [2, 3, 4, 5, 6, 10, 15, 20]

    bestNumerator : Int -> Int
    bestNumerator denominator = round (x * toFloat denominator)

    error : Int -> Float
    error denominator =
      abs <| x - toFloat (bestNumerator denominator) / toFloat denominator

  in
    denominators
    |> List.map (\d -> (error d, bestNumerator d, d))
    |> List.filter (\(err, _, _) -> err <= tolerance)
    |> List.minimum
    |> Maybe.map (\(_, n, d) -> (n, d))

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
  H.form
    [ HA.class "g-3 needs-validation"
    , HA.attribute "novalidate" ""
    , HE.onSubmit Ignore
    ]
    [ H.div [HA.class ""]
      [ let
          isValid = isOk (parseResolvesAt model)
        in
        H.div []
        [ H.label [HA.for "resolves-at"] [H.text "I predict that, by "]
        , H.input
          [ HA.type_ "date"
          , HA.id "resolves-at"
          , HA.style "width" "auto"
          , HA.style "display" "inline-block"
          , HA.disabled disabled
          , HE.onInput SetResolvesAtField
          , HA.value model.resolvesAtField
          , HA.class (if isValid then "" else "is-invalid")
          , HA.class "form-control form-control-sm ms-1"
          ] []
        , H.text ","
        , H.div [HA.class "invalid-feedback"] [viewError (parseResolvesAt model)]
        ]
      , let
          isValid = isOk (parsePrediction model)
        in
        H.div [HA.class "m-1"]
        [ H.textarea
          [ HA.style "width" "100%"
          , HA.placeholder placeholders.prediction
          , HA.disabled disabled
          , HA.class "prediction-field"
          , HE.onInput SetPredictionField
          , HA.value model.predictionField
          , HA.class (if isValid then "" else "is-invalid")
          , HA.class "form-control"
          ] []
        , H.div [HA.class "mx-5 mt-1 text-secondary"]
          [ H.small []
            [ H.text "A good prediction is ", i "objective", H.text " and ", i "verifiable,"
            , H.text " ideally about ", i "experiences you anticipate having."
            , H.text " \"Gun violence will increase in the U.S. in 2022\" is extremely ill-defined;"
            , H.text " \"The CDC will report at least 40,000 gun deaths for 2022, as stated on https://www.cdc.gov/nchs/fastats/injury.htm\" is much better."
            ]
          ]
        ]
      ]
    , H.hr [] []
    , H.div []
      [ let
          isValid = isOk (parseLowProbability model)
        in
        H.div []
        [ H.text "I think that this has at least a "
        , H.input
            [ HA.type_ "number", HA.min "0", HA.max "100", HA.step "any"
            , HA.style "width" "7em"
            , HA.style "display" "inline-block"
            , HA.disabled disabled
            , HE.onInput SetLowPField
            , HA.value model.lowPField
            , HA.class (if isValid then "" else "is-invalid")
            , HA.class "form-control form-control-sm"
            ] []
        , H.text "% chance of happening."
        , H.div [HA.class "invalid-feedback"] [viewError (parseLowProbability model)]
        , case parseLowProbability model of
            Err e -> H.text ""
            Ok lowP ->
              case rationalApprox {x=lowP, tolerance=0.13 * min lowP (1-lowP)} of
                Just (n, d) -> H.div [] [H.small [HA.class "text-secondary"] [H.text <| "(i.e. about " ++ String.fromInt n ++ " out of " ++ String.fromInt d ++ ")"]]
                Nothing -> H.text ""
        ]
      , let
          isValid = isOk (parseHighProbability model)
        in
        H.small [] [H.details [HA.class "px-4"]
        [ H.summary [HA.style "text-align" "right"] [H.text "Set upper bound too?"]
        , H.text "...but I think that it would be overconfident to assign it more than a "
        , H.input
            [ HA.type_ "number", HA.min (String.toFloat model.lowPField |> Maybe.withDefault 0 |> String.fromFloat), HA.max "100", HA.step "any"
            , HA.style "width" "7em"
            , HA.style "display" "inline-block"
            , HA.disabled disabled
            , HE.onInput SetHighPField
            , HA.value model.highPField
            , HA.class (if isValid then "" else "is-invalid")
            , HA.class "form-control form-control-sm"
            ] []
        , H.text "% chance. "
        , H.span [HA.class "invalid-feedback"] [viewError (parseHighProbability model)]
        , H.details [HA.class "px-4"]
          [ H.summary [HA.style "text-align" "right"] [H.text "Confusing?"]
          , H.p [] [H.text "Yeah, this is startlingly difficult to think about! Here are some roughly equivalent statements:"]
          , H.ul []
            [ H.li []
              [ H.text "\"I think a significant number of my friends assign this a probability below "
              , Utils.b <| model.lowPField ++ "%"
              , H.text ", and I'm pretty sure that they're being too hasty to dismiss this."
              , case parseHighProbability model of
                  Ok highP ->
                    if highP == 1 then H.text "" else
                    H.span []
                    [ H.text " And other friends assign this a probability higher than "
                    , Utils.b <| model.highPField ++ "%"
                    , H.text " -- I think they're overconfident that this will happen."
                    ]
                  Err _ -> H.text ""
              , H.text "\""
              ]
            , H.li []
              [ H.text "\"I'm pretty sure that, if I researched this question pretty carefully, and at the end of the day I had to put a single number on it,"
              , H.text " I would end up assigning it a probability between "
              , Utils.b <| model.lowPField ++ "%"
              , case parseHighProbability model of
                  Ok highP ->
                    if highP == 1 then H.text "" else
                    H.span []
                    [ H.text " and "
                    , Utils.b <| model.highPField ++ "%"
                    ]
                  Err _ -> H.text ""
              , H.text ". If I assigned a number outside that range, I must have learned something really surprising, something that changed my mind significantly!\""
              ]
            , H.li []
              [ H.text "\"I would pay one of my friends about "
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
              , H.text ".\""
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
      ]]
    , H.hr [] []
    , let
        isValid = isOk (parseStake model)
      in
      H.div [HA.class ""]
      [ H.text "I'm willing to lose up to $"
      , H.input
          [ HA.type_ "number", HA.min "0", HA.max (String.fromInt <| maxLegalStakeCents//100)
          , HA.style "width" "7em"
          , HA.style "display" "inline-block"
          , HA.placeholder placeholders.stake
          , HA.disabled disabled
          , HE.onInput SetStakeField
          , HA.value model.stakeField
          , HA.class (if isValid then "" else "is-invalid")
          , HA.class "form-control form-control-sm"
          ] []
      , H.text " if I'm wrong."
      , H.div [HA.class "invalid-feedback"] [viewError (parseStake model)]
      , case parseStake model of
            Err _ -> H.text ""
            Ok stakeCents ->
              let
                betVsSkeptics : Maybe String
                betVsSkeptics =
                  parseLowProbability model
                  |> Result.toMaybe
                  |> Maybe.andThen (\lowP -> if lowP == 0 then Nothing else Just <| Utils.formatCents stakeCents ++ " against " ++ Utils.formatCents (round <| toFloat stakeCents * (1-lowP)/lowP))
                betVsBelievers : Maybe String
                betVsBelievers =
                  parseHighProbability model
                  |> Result.toMaybe
                  |> Maybe.andThen (\highP -> if highP == 1 then Nothing else Just <| Utils.formatCents stakeCents ++ " against " ++ Utils.formatCents (round <| toFloat stakeCents * highP/(1-highP)))
              in
                case (betVsSkeptics, betVsBelievers) of
                  (Nothing, Nothing) -> H.text ""
                  (Just s, Nothing) -> H.div [] [H.small [HA.class "text-secondary"] [H.text "(In other words, I'd happily bet ", Utils.b s, H.text " that this will happen.)"]]
                  (Nothing, Just s) -> H.div [] [H.small [HA.class "text-secondary"] [H.text "(In other words, I'd happily bet ", Utils.b s, H.text " that this won't happen.)"]]
                  (Just skep, Just bel)  -> H.div [] [H.small [HA.class "text-secondary"] [H.text "(In other words, I'd happily bet ", Utils.b skep, H.text " that this will happen, or ", Utils.b bel, H.text " that it won't.)"]]
      ]
    , H.hr [] []
    , let
        isValid = isOk (parseOpenForSeconds model)
      in
      H.div [HA.class ""]
      [ H.text "This offer is open for "
      , H.input
          [ HA.type_ "number", HA.min "1"
          , HA.style "width" "7em"
          , HA.style "display" "inline-block"
          , HA.disabled disabled
          , HE.onInput SetOpenForSecondsField
          , HA.value model.openForSecondsField
          , HA.class (if isValid then "" else "is-invalid")
          , HA.class "form-control form-control-sm"
          ] []
      , H.select
          [ HA.disabled disabled
          , HE.onInput SetOpenForUnitField
          , HA.value model.openForUnitField
          , HA.class "form-select d-inline-block w-auto"
          ]
          [ H.option [] [H.text "weeks"]
          , H.option [] [H.text "days"]
          ]
      , H.text "."
      , H.div [HA.class "invalid-feedback"] [viewError (parseOpenForSeconds model)]
      , H.small [] [H.details [HA.class "px-4"]
          [ H.summary [HA.style "text-align" "right"] [H.text "Confusing?"]
          , H.text <| "If it's Jan 1, and you're betting about how many book reviews Scott Alexander will have published by Dec 31,"
              ++ " you don't want people to be able to wait until Dec 30 before betting against you --"
              ++ " the question is essentially already answered at that point!"
              ++ " So, you might only accept bets for a week or two, to give your friends time to bet against you,"
              ++ " without letting them get ", Utils.i "too much", H.text " extra information."
          ]]
      ]
  , H.hr [] []
  , H.div [HA.class ""]
      [ H.text "Special rules (e.g. implicit assumptions, what counts as cheating):"
      , H.textarea
          [ HA.style "width" "100%"
          , HA.placeholder placeholders.specialRules
          , HA.disabled disabled
          , HA.class "special-rules-field"
          , HE.onInput SetSpecialRulesField
          , HA.value model.specialRulesField
          , HA.class "form-control"
          ]
          []
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
        , id = "navbar-auth"
        }
        model.navbarAuth
    , H.main_ [HA.class "container"]
    [ H.h2 [HA.class "text-center"] [H.text "New Prediction"]
    , case Globals.getAuth model.globals of
       Just _ -> H.text ""
       Nothing ->
        H.div []
          [ H.span [HA.style "color" "red"] [H.text "You need to log in to create a new prediction!"]
          , H.hr [] []
          ]
    , viewForm model
    , let
        allowsEmailInvitation = Globals.hasEmailAddress model.globals && (model.globals.serverState.settings |> Maybe.map .allowEmailInvitations |> Maybe.withDefault False)
      in
      if allowsEmailInvitation || not (Globals.isLoggedIn model.globals) then
        H.text ""
      else
        H.div [HA.class "pre-creation-plea-for-email"]
        [ H.text "Hey! It'll be annoying and awkward for new people to bet against you unless I can ask you if you trust them. This requires emailing you. I won't force you to sign up for this, but I strongly recommend it!"
        , H.details []
          [ H.ul []
            [ H.li [] [H.text "Since bets are all honor-system, people can only bet against each other if they trust each other to pay up."]
            , H.li [] [H.text "If you register an email address, I'll be able to email you to ask you whether you trust potential bettors."]
            , H.li [] [H.text "Otherwise, potential bettors will have to text/email/... you themselves to ask you to click buttons to tell me you trust them."]
            , H.li [] [H.text "(Don't worry, I won't share your email address with anyone unless you ask me to.)"]
            ]
          ]
        , H.hr [] []
        , EmailSettingsWidget.view
            { setState = SetEmailWidget
            , ignore = Ignore
            , setEmail = SetEmail
            , verifyEmail = VerifyEmail
            , updateSettings = UpdateSettings
            , userInfo = Utils.must "checked that user is logged in" model.globals.serverState.settings
            }
            model.emailSettingsWidget
        ]

    , H.div [HA.style "text-align" "center", HA.style "margin-bottom" "2em"]
        [ H.button
            [ HE.onClick Create
            , HA.class "btn btn-primary mt-2"
            , HA.disabled (not (Globals.isLoggedIn model.globals) || buildCreateRequest model == Nothing || model.createRequestStatus == AwaitingResponse)
            ]
            [ H.text <| if Globals.isLoggedIn model.globals then "Post prediction" else "Log in to post prediction" ]
        , case model.createRequestStatus of
            Unstarted -> H.text ""
            AwaitingResponse -> H.text ""
            Succeeded -> Utils.greenText "Success!"
            Failed e -> H.div [HA.style "color" "red"] [H.text e]
        ]
    , H.hr [] []
    , H.text "Preview:"
    , H.div [HA.style "border" "1px solid black", HA.style "padding" "1em", HA.style "margin" "1em"]
        [ case buildCreateRequest model of
            Just req ->
              previewPrediction {request=req, creatorName=Globals.getOwnUsername model.globals |> Maybe.withDefault "you", createdAt=model.globals.now}
              |> (\prediction -> Prediction.viewBodyMockup model.globals prediction |> H.map (always Ignore))
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
  , allowEmailInvitations = False
  }

subscriptions : Model -> Sub Msg
subscriptions _ = authWidgetExternallyChanged AuthWidgetExternallyModified

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
