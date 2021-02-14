port module ViewPredictionPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD
import Protobuf.Encode as PE
import Protobuf.Decode as PD
import Time
import Dict as D exposing (Dict)

import Iso8601
import Biatob.Proto.Mvp as Pb
import Utils

import StakeForm
import Biatob.Proto.Mvp exposing (StakeResult(..))
import Task

port changed : () -> Cmd msg
port copy : String -> Cmd msg

type alias Model =
  { stakeForm : StakeForm.State
  , prediction : Pb.UserPredictionView
  , predictionId : Int
  , auth : Maybe Pb.AuthToken
  , working : Bool
  , stakeError : Maybe String
  , resolveError : Maybe String
  , now : Time.Posix
  , resolutionNotes : String
  }

type Msg
  = SetStakeFormState StakeForm.State
  | Stake {bettorIsASkeptic:Bool, bettorStakeCents:Int}
  | StakeFinished (Result Http.Error Pb.StakeResponse)
  | SetResolutionNotes String
  | Resolve Pb.Resolution
  | ResolveFinished (Result Http.Error Pb.ResolveResponse)
  | Copy String
  | Tick Time.Posix
  | Ignore

setPrediction : Pb.UserPredictionView -> Model -> Model
setPrediction prediction model = { model | prediction = prediction }

initBase : { prediction : Pb.UserPredictionView , predictionId : Int , auth : Maybe Pb.AuthToken, now : Time.Posix } -> ( Model, Cmd Msg )
initBase flags =
  ( { stakeForm = StakeForm.init
    , prediction = flags.prediction
    , predictionId = flags.predictionId
    , auth = flags.auth
    , working = False
    , stakeError = Nothing
    , resolveError = Nothing
    , now = flags.now
    , resolutionNotes = ""
    }
  , Task.perform Tick Time.now
  )

init : JD.Value -> (Model, Cmd Msg)
init flags =
  initBase
    { prediction = Utils.mustDecodePbFromFlags Pb.userPredictionViewDecoder "predictionPbB64" flags
    , predictionId = Utils.mustDecodeFromFlags JD.int "predictionId" flags
    , auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    , now = Time.millisToPosix 0
    }

postStake : Pb.StakeRequest -> Cmd Msg
postStake req =
  Http.post
    { url = "/api/Stake"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toStakeRequestEncoder req
    , expect = PD.expectBytes StakeFinished Pb.stakeResponseDecoder }

postResolve : Pb.ResolveRequest -> Cmd Msg
postResolve req =
  Http.post
    { url = "/api/Resolve"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toResolveRequestEncoder req
    , expect = PD.expectBytes ResolveFinished Pb.resolveResponseDecoder }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetStakeFormState newState ->
      ({ model | stakeForm = newState }, Cmd.none)
    Stake {bettorIsASkeptic, bettorStakeCents} ->
      ( { model | working = True , stakeError = Nothing }
      , postStake {predictionId=model.predictionId, bettorIsASkeptic=bettorIsASkeptic, bettorStakeCents=bettorStakeCents}
      )
    StakeFinished (Err e) ->
      ( { model | working = False , stakeError = Just (Debug.toString e) }
      , Cmd.none
      )
    StakeFinished (Ok resp) ->
      case resp.stakeResult of
        Just (Pb.StakeResultOk _) ->
          ( model
          , changed ()
          )
        Just (Pb.StakeResultError e) ->
          ( { model | working = False , stakeError = Just (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , stakeError = Just "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )
    SetResolutionNotes s ->
      ( { model | resolutionNotes = s } , Cmd.none )
    Resolve resolution ->
      ( { model | working = True , resolveError = Nothing }
      , postResolve {predictionId=model.predictionId, resolution=resolution, notes = ""}
      )
    ResolveFinished (Err e) ->
      ( { model | working = False , resolveError = Just (Debug.toString e) }
      , Cmd.none
      )
    ResolveFinished (Ok resp) ->
      case resp.resolveResult of
        Just (Pb.ResolveResultOk _) ->
          ( model
          , changed ()
          )
        Just (Pb.ResolveResultError e) ->
          ( { model | working = False , resolveError = Just (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , resolveError = Just "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )
    Copy id ->
      ( model , copy id )
    Tick t ->
      ( { model | now = t } , Cmd.none )
    Ignore ->
      ( model , Cmd.none )

viewStakeFormOrExcuse : Model -> Html Msg
viewStakeFormOrExcuse model =
  let creator = Utils.mustPredictionCreator model.prediction in
  if Utils.resolutionIsTerminal (Utils.currentResolution model.prediction) then
    H.text "This prediction has resolved, so cannot be bet in."
  else if Utils.secondsToClose model.now model.prediction <= 0 then
    H.text <| "This prediction closed on " ++ Utils.dateStr Time.utc (Utils.predictionClosesTime model.prediction) ++ " (UTC)."
  else case model.auth of
    Nothing ->
      H.div []
        [ H.text "You must be logged in to participate in this prediction!"
        ]
    Just auth_ ->
      if creator.isSelf then
        H.text ""
      else if not creator.trustsYou then
        H.span []
          [ H.text "This user hasn't marked you as trusted! If you think that, in real life, they "
          , H.i [] [H.text "do"]
          , H.text " trust you to pay your debts, send them a link to "
          , H.a [HA.href <| Utils.pathToUserPage <| Utils.mustTokenOwner auth_] [H.text "your user page"]
          , H.text " and ask them to mark you as trusted."
          ]
      else if not creator.isTrusted then
        H.text <|
          "You don't trust the prediction creator!"
          ++ " If you think that you *do* trust them in real life, ask them for a link to their user page,"
          ++ " and mark them as trusted."
      else
        H.div []
          [ StakeForm.view (stakeFormConfig model) model.stakeForm
          , case model.stakeError of
              Just e -> H.div [HA.style "color" "red"] [H.text e]
              Nothing -> H.text ""
          ]

creatorWinningsByBettor : Bool -> List Pb.Trade -> Dict String Int -- TODO: avoid key serialization collisions
creatorWinningsByBettor resolvedYes trades =
  trades
  |> List.foldl (\t d -> D.update (Utils.renderUserPlain <| Utils.mustTradeBettor t) (Maybe.withDefault 0 >> ((+) (if xor resolvedYes t.bettorIsASkeptic then -t.creatorStakeCents else t.bettorStakeCents)) >> Just) d) D.empty

stateWinnings : String -> Int -> String
stateWinnings counterparty win =
  (if win > 0 then counterparty ++ " owes you" else "You owe " ++ counterparty) ++ " " ++ Utils.formatCents (abs win) ++ "."

enumerateWinnings : Dict String Int -> Html Msg
enumerateWinnings winningsByUser =
  H.ul [] <| (
    winningsByUser
    |> D.toList
    |> List.sortBy (\(b, win) -> b)
    |> List.map (\(b, win) -> H.li [] [H.text <| stateWinnings b win])
    )

viewPredictionState : Model -> Html Msg
viewPredictionState model =
  let
    auditLog : Html Msg
    auditLog =
      if List.isEmpty model.prediction.resolutions then H.text "" else
      H.details [HA.style "opacity" "50%"]
        [ H.summary [] [H.text "Details"]
        , model.prediction.resolutions
          |> List.map (\event -> H.li []
              [ H.text <| "[" ++ Utils.isoStr Time.utc (Utils.unixtimeToTime event.unixtime) ++ " UTC] "
              , H.text <| case event.resolution of
                  Pb.ResolutionYes -> "resolved YES"
                  Pb.ResolutionNo -> "resolved NO"
                  Pb.ResolutionInvalid -> "resolved INVALID"
                  Pb.ResolutionNoneYet -> "UN-RESOLVED"
                  Pb.ResolutionUnrecognized_ _ -> "(??? unrecognized resolution ???)"
              ])
          |> H.ul []
        ]
  in
  H.div []
    [ case Utils.currentResolution model.prediction of
      Pb.ResolutionYes ->
        H.text "This prediction has resolved YES. "
      Pb.ResolutionNo ->
        H.text "This prediction has resolved NO. "
      Pb.ResolutionInvalid ->
        H.text "This prediction has resolved INVALID. "
      Pb.ResolutionNoneYet ->
        let
          nowUnixtime = Time.posixToMillis model.now // 1000
          secondsToClose = model.prediction.closesUnixtime - nowUnixtime
          secondsToResolve = model.prediction.resolvesAtUnixtime - nowUnixtime
        in
          H.text <|
            ( if secondsToClose > 0 then
                "Betting closes in " ++ Utils.renderIntervalSeconds secondsToClose ++ ", and "
              else
                "Betting closed " ++ Utils.renderIntervalSeconds (abs secondsToClose) ++ " ago, and "
            ) ++
            ( if secondsToResolve > 0 then
                "the prediction should resolve in " ++ Utils.renderIntervalSeconds secondsToResolve ++ ". "
              else
                "the prediction should have resolved " ++ Utils.renderIntervalSeconds (abs secondsToResolve) ++ " ago. Consider pinging the creator! "
            )
      Pb.ResolutionUnrecognized_ _ ->
        H.span [HA.style "color" "red"]
          [H.text "Oh dear, something has gone very strange with this prediction. Please email TODO with this URL to report it!"]
    , auditLog
    ]

viewWinnings : Model -> Html Msg
viewWinnings model =
  let
    auditLog : Html Msg
    auditLog =
      if List.isEmpty model.prediction.yourTrades then H.text "" else
      H.details [HA.style "opacity" "50%"]
        [ H.summary [] [H.text "Details"]
        , model.prediction.yourTrades
          |> List.map (\t -> H.li [] [ H.text <| "[" ++ Utils.isoStr Time.utc (Utils.unixtimeToTime t.transactedUnixtime) ++ " UTC] "
                                     , Utils.renderUser (Utils.mustTradeBettor t)
                                     , H.text <| " bet " ++ (if t.bettorIsASkeptic then "NO" else "YES") ++ " staking " ++ Utils.formatCents t.bettorStakeCents ++ " against " ++ Utils.formatCents t.creatorStakeCents])
          |> H.ul []
        ]
    ifRes : Bool -> Html Msg
    ifRes res =
      creatorWinningsByBettor res model.prediction.yourTrades
        |> let creator = Utils.mustPredictionCreator model.prediction in
            if creator.isSelf then
              enumerateWinnings
            else
              (D.values >> List.sum >> (\n -> -n) >> stateWinnings creator.displayName >> H.text)
  in
  if List.isEmpty model.prediction.yourTrades then H.text "" else
  H.div []
    [ case Utils.currentResolution model.prediction of
      Pb.ResolutionYes ->
        ifRes True
      Pb.ResolutionNo ->
        ifRes False
      Pb.ResolutionInvalid ->
        H.text "All bets have been called off. "
      Pb.ResolutionNoneYet ->
        H.div []
          [ H.div [] [H.text "If this comes true: ", ifRes True]
          , H.div [] [H.text "Otherwise: ", ifRes False]
          ]
      Pb.ResolutionUnrecognized_ _ -> Debug.todo ""
    , auditLog
    ]

viewCreationParams : Model -> Html Msg
viewCreationParams model =
  let
    creator = Utils.mustPredictionCreator model.prediction
    openTime = model.prediction.createdUnixtime |> (*) 1000 |> Time.millisToPosix
    certainty = Utils.mustPredictionCertainty model.prediction
  in
  H.p []
    [ H.text <| "On " ++ Utils.dateStr Time.utc openTime ++ " UTC, "
    , H.strong [] [H.text <| if creator.isSelf then "you" else creator.displayName]
    , H.text " assigned this a "
    , certainty.low |> (*) 100 |> round |> String.fromInt |> H.text
    , H.text "-"
    , certainty.high |> (*) 100 |> round |> String.fromInt |> H.text
    , H.text "% chance, and staked "
    , model.prediction.maximumStakeCents |> Utils.formatCents |> H.text
    , case (model.prediction.maximumStakeCents - model.prediction.remainingStakeCentsVsSkeptics, model.prediction.maximumStakeCents - model.prediction.remainingStakeCentsVsBelievers) of
        (0, 0) -> H.text ""
        (promisedToSkeptics, 0) -> H.span [HA.style "opacity" "50%"] [H.text <| " (though they've already promised away " ++ Utils.formatCents promisedToSkeptics ++ " if this doesn't happen)"]
        (0, promisedToBelievers) -> H.span [HA.style "opacity" "50%"] [H.text <| " (though they've already promised away " ++ Utils.formatCents promisedToBelievers ++ " if this happens)"]
        (promisedToSkeptics, promisedToBelievers) -> H.span [HA.style "opacity" "50%"] [H.text <| " (though they've already promised away " ++ Utils.formatCents promisedToSkeptics ++ " if this doesn't happen, and " ++ Utils.formatCents promisedToBelievers ++ " if it does)"]
    , H.text "."
    ]

viewResolveButtons : Model -> Html Msg
viewResolveButtons model =
  if (Utils.mustPredictionCreator model.prediction).isSelf then
    H.div []
      [ let
          mistakeDetails =
            H.details [HA.style "color" "gray"]
              [ H.summary [] [H.text "Mistake?"]
              , H.text "If you resolved this prediction incorrectly, you can "
              , H.button [HE.onClick (Resolve Pb.ResolutionNoneYet)] [H.text "un-resolve it."]
              ]
        in
        case Utils.currentResolution model.prediction of
          Pb.ResolutionYes ->
            mistakeDetails
          Pb.ResolutionNo ->
            mistakeDetails
          Pb.ResolutionInvalid ->
            mistakeDetails
          Pb.ResolutionNoneYet ->
            H.div []
              [ H.button [HE.onClick (Resolve Pb.ResolutionYes)] [H.text "Resolve YES"]
              , H.button [HE.onClick (Resolve Pb.ResolutionNo)] [H.text "Resolve NO"]
              , H.button [HE.onClick (Resolve Pb.ResolutionInvalid)] [H.text "Resolve INVALID"]
              ]
          Pb.ResolutionUnrecognized_ _ -> Debug.todo ""
      , case model.resolveError of
          Just e -> H.span [] [H.text e]
          Nothing -> H.text ""
      ]
  else
    H.text ""

view : Model -> Html Msg
view model =
  let
    creator = Utils.mustPredictionCreator model.prediction
  in
  H.div []
    [ H.h2 [] [H.text <| "Prediction: " ++ model.prediction.prediction ++ ", by " ++ (String.left 10 <| Iso8601.fromTime <| Time.millisToPosix <| model.prediction.resolvesAtUnixtime * 1000)]
    , viewPredictionState model
    , viewResolveButtons model
    , viewWinnings model
    , H.hr [] []
    , viewCreationParams model
    , case model.prediction.specialRules of
        "" ->
          H.text ""
        rules ->
          H.div []
            [ H.strong [] [H.text "Special rules:"]
            , H.text <| " " ++ rules
            ]
    , H.hr [] []
    , viewStakeFormOrExcuse model
    , if creator.isSelf then
        H.div []
          [ H.text "As the creator of this prediction, you might want to link to it in your writing! Here are some snippets of HTML you could copy-paste."
          , viewEmbedInfo model
          ]
      else
        H.text ""
    ]

viewEmbedInfo : Model -> Html Msg
viewEmbedInfo model =
  let
    linkUrl = "/p/" ++ String.fromInt model.predictionId
    imgUrl = "/p/" ++ String.fromInt model.predictionId ++ "/embed.png"
    imgStyles = [("max-height","1.5ex"), ("border-bottom","1px solid #008800")]
    imgCode =
      "<a href=\"" ++ linkUrl ++ "\">"
      ++ "<img style=\"" ++ (imgStyles |> List.map (\(k,v) -> k++":"++v) |> String.join ";") ++ "\" src=\"" ++ imgUrl ++ "\" /></a>"
    linkText =
      "["
      ++ Utils.formatCents (model.prediction.maximumStakeCents // 100 * 100)
      ++ " @ "
      ++ String.fromInt (round <| (Utils.mustPredictionCertainty model.prediction).low * 100)
      ++ "-"
      ++ String.fromInt (round <| (Utils.mustPredictionCertainty model.prediction).high * 100)
      ++ "%]"
    linkCode =
      "<a href=\"" ++ linkUrl ++ "\">" ++ linkText ++ "</a>"
  in
    H.ul []
      [ H.li [] <|
        [ H.text "A linked inline image: "
        , H.input [HA.id "imgCopypasta", HA.style "font" "monospace", HA.value imgCode] []
        , H.button [HE.onClick (Copy "imgCopypasta")] [H.text "Copy"]
        , H.br [] []
        , H.text "This would render as: "
        , H.a [HA.href linkUrl]
          [ H.img (HA.src imgUrl :: (imgStyles |> List.map (\(k,v) -> HA.style k v))) []]
        ]
      , H.li [] <|
        [ H.text "A boring old link: "
        , H.input [HA.id "linkCopypasta", HA.style "font" "monospace", HA.value linkCode] []
        , H.button [HE.onClick (Copy "linkCopypasta")] [H.text "Copy"]
        , H.br [] []
        , H.text "This would render as: "
        , H.a [HA.href linkUrl] [H.text linkText]
        ]
      ]

stakeFormConfig : Model -> StakeForm.Config Msg
stakeFormConfig model =
  { setState = SetStakeFormState
  , onStake = Stake
  , nevermind = Ignore
  , disableCommit = (model.auth == Nothing || (Utils.mustPredictionCreator model.prediction).isSelf)
  , prediction = model.prediction
  }

subscriptions : Model -> Sub Msg
subscriptions _ = Time.every 1000 Tick

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }