module Widgets.PredictionWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Time
import Dict as D exposing (Dict)

import Iso8601
import Biatob.Proto.Mvp as Pb
import Utils exposing (Cents, PredictionId, Username, b)

import Widgets.CopyWidget as CopyWidget
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import API

epsilon : Float
epsilon = 0.0000001 -- 🎵 I hate floating-point arithmetic 🎶

type alias Config msg =
  { setState : State -> msg
  , copy : String -> msg
  , stake : State -> Pb.StakeRequest -> msg
  , resolve : State -> Pb.ResolveRequest -> msg
  , invitationWidget : Html msg
  , linkTitle : Bool
  , disableCommit : Bool
  , predictionId : PredictionId
  , prediction : Pb.UserPredictionView
  , httpOrigin : String
  , creatorRelationship : CreatorRelationship
  , timeZone : Time.Zone
  , now : Time.Posix
  }
type alias State =
  { believerStakeField : String
  , skepticStakeField : String
  , invitationWidget : SmallInvitationWidget.State
  , working : Bool
  , notification : Html Never
  }

init : State
init =
  { believerStakeField = "0"
  , skepticStakeField = "0"
  , invitationWidget = SmallInvitationWidget.init
  , working = False
  , notification = H.text ""
  }

type CreatorRelationship = LoggedOut | Self | Friends | TrustsOwner | TrustedByOwner | NoRelation
viewStakeWidgetOrExcuse : Config msg -> State -> Html msg
viewStakeWidgetOrExcuse config state =
  if Utils.resolutionIsTerminal (Utils.currentResolution config.prediction) then
    H.text "This prediction has resolved, so cannot be bet in."
  else if config.prediction.closesUnixtime < Utils.timeToUnixtime config.now then
    H.text <| "This prediction closed on " ++ Utils.dateStr config.timeZone (Utils.predictionClosesTime config.prediction) ++ "."
  else
    case config.creatorRelationship of
      LoggedOut ->
        H.div []
          [ H.text "You must be logged in to bet on this prediction!"
          ]
      Self -> H.text ""
      Friends -> viewStakeWidget config state
      NoRelation ->
        H.div []
          [ H.text "You and "
          , Utils.renderUser config.prediction.creator
          , H.text " don't trust each other! If, in real life, you "
          , Utils.i "do"
          , H.text " trust each other to pay your debts, send them an invitation! "
          , config.invitationWidget
          ]
      TrustedByOwner ->
        H.div []
          [ H.text "You don't trust "
          , Utils.renderUser config.prediction.creator
          , H.text " to pay their debts, so you probably don't want to bet on this prediction. If you actually"
          , Utils.i "do"
          , H.text " trust them to pay their debts, send them an invitation link: "
          , config.invitationWidget
          ]
      TrustsOwner ->
        H.div []
          [ Utils.renderUser config.prediction.creator, H.text " hasn't marked you as trusted! If you think that, in real life, they "
          , Utils.i "do"
          , H.text " trust you to pay your debts, send them an invitation link: "
          , config.invitationWidget
          ]

viewStakeWidget : Config msg -> State -> Html msg
viewStakeWidget config state =
  let
    certainty = Utils.mustPredictionCertainty config.prediction

    isClosed = Utils.timeToUnixtime config.now > config.prediction.closesUnixtime
    disableInputs = isClosed || Utils.resolutionIsTerminal (Utils.currentResolution config.prediction)
    creatorStakeFactorVsBelievers = (1 - certainty.high) / certainty.high
    creatorStakeFactorVsSkeptics = certainty.low / (1 - certainty.low)
    maxBelieverStakeCents = if creatorStakeFactorVsBelievers == 0 then 0 else toFloat config.prediction.remainingStakeCentsVsBelievers / creatorStakeFactorVsBelievers + 0.001 |> floor
    maxSkepticStakeCents = if creatorStakeFactorVsSkeptics == 0 then 0 else toFloat config.prediction.remainingStakeCentsVsSkeptics / creatorStakeFactorVsSkeptics + 0.001 |> floor
  in
  H.div []
    [ if certainty.low == 0 then H.text "" else
      let skepticStakeCents = parseCents {max=maxSkepticStakeCents} state.skepticStakeField in
      H.p []
      [ H.text "Do you ", b "strongly doubt", H.text " that this will happen? Then stake $"
      , H.input
          [ HA.style "width" "5em"
          , HA.type_"number", HA.min "0", HA.max (toFloat maxSkepticStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
          , HA.disabled disableInputs
          , HE.onInput (\s -> config.setState {state | skepticStakeField = s})
          , HA.value state.skepticStakeField
          ]
          []
        |> Utils.appendValidationError (Utils.resultToErr skepticStakeCents)
      , H.text " that it won't, against ", Utils.renderUser config.prediction.creator, H.text "'s "
      , Utils.b (skepticStakeCents |> Result.map (toFloat >> (*) creatorStakeFactorVsSkeptics >> round >> Utils.formatCents) |> Result.withDefault "???")
      , H.text ". "
      , H.button
          (case skepticStakeCents of
            Ok stake ->
              [ HE.onClick (config.stake {state | working=True, notification=H.text ""} {predictionId=config.predictionId, bettorIsASkeptic=True, bettorStakeCents=stake}) ]
            Err _ ->
              [ HA.disabled True ]
          )
          [H.text "Commit"]
      ]
    , if certainty.high == 1 then H.text "" else
      let believerStakeCents = parseCents {max=maxBelieverStakeCents} state.believerStakeField in
      H.p []
      [ H.text "Do you ", b "strongly believe", H.text " that this will happen? Then stake $"
      , H.input
          [ HA.style "width" "5em"
          , HA.type_"number", HA.min "0", HA.max (toFloat maxBelieverStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
          , HA.disabled disableInputs
          , HE.onInput (\s -> config.setState {state | believerStakeField=s})
          , HA.value state.believerStakeField
          ]
          []
        |> Utils.appendValidationError (Utils.resultToErr believerStakeCents)
      , H.text " that it will, against ", Utils.renderUser config.prediction.creator, H.text "'s "
      , Utils.b (believerStakeCents |> Result.map (toFloat >> (*) creatorStakeFactorVsBelievers >> round >> Utils.formatCents) |> Result.withDefault "???")
      , H.text ". "
      , H.button
          (case believerStakeCents of
            Ok stake ->
              [ HE.onClick (config.stake {state | working=True, notification=H.text ""} {predictionId=config.predictionId, bettorIsASkeptic=False, bettorStakeCents=stake}) ]
            Err _ ->
              [ HA.disabled True ]
          )
          [H.text "Commit"]
      ]
    , state.notification |> H.map never
    ]

parseCents : {max:Cents} -> String -> Result String Cents
parseCents {max} s =
  case String.toFloat s of
    Nothing -> Err "must be a number"
    Just dollars ->
      let n = round (100*dollars) in
      if n < 0 || n > max then Err ("must be between $0 and " ++ Utils.formatCents max) else Ok n

creatorWinningsByBettor : Bool -> List Pb.Trade -> Dict Username Cents
creatorWinningsByBettor resolvedYes trades =
  trades
  |> List.foldl (\t d -> D.update t.bettor (Maybe.withDefault 0 >> ((+) (if xor resolvedYes t.bettorIsASkeptic then -t.creatorStakeCents else t.bettorStakeCents)) >> Just) d) D.empty

stateWinnings : Username -> Cents -> Html a
stateWinnings counterparty win =
  H.span [] <|
    ( if win > 0 then
        [Utils.renderUser counterparty, H.text " owes you"]
      else
        [H.text "You owe ", Utils.renderUser counterparty]
    ) ++ [H.text <| " " ++ Utils.formatCents (abs win) ++ "."]

enumerateWinnings : Dict Username Cents -> Html a
enumerateWinnings winningsByUser =
  H.ul [] <| (
    winningsByUser
    |> D.toList
    |> List.sortBy (\(b, _) -> b)
    |> List.map (\(b, win) -> H.li [] [stateWinnings b win])
    )

viewPredictionState : Config msg -> State -> Html msg
viewPredictionState config _ =
  let
    auditLog : Html msg
    auditLog =
      if List.isEmpty config.prediction.resolutions then H.text "" else
      H.details [HA.style "opacity" "50%"]
        [ H.summary [] [H.text "Details"]
        , config.prediction.resolutions
          |> List.map (\event -> H.li []
              [ H.text <| "[" ++ Utils.isoStr config.timeZone (Utils.unixtimeToTime event.unixtime) ++ "] "
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
    [ case Utils.currentResolution config.prediction of
      Pb.ResolutionYes ->
        H.text "This prediction has resolved YES. "
      Pb.ResolutionNo ->
        H.text "This prediction has resolved NO. "
      Pb.ResolutionInvalid ->
        H.text "This prediction has resolved INVALID. "
      Pb.ResolutionNoneYet ->
        let
          secondsToClose = config.prediction.closesUnixtime - Utils.timeToUnixtime config.now
          secondsToResolve = config.prediction.resolvesAtUnixtime - Utils.timeToUnixtime config.now
        in
          H.text <|
            ( if secondsToClose > 0 then
                "Betting closes " ++ (
                  if secondsToClose < 86400 then
                    "in " ++ Utils.renderIntervalSeconds secondsToClose
                  else
                    "on " ++ Utils.dateStr config.timeZone (Utils.unixtimeToTime config.prediction.closesUnixtime)
                ) ++ ", and "
              else
                "Betting closed on" ++ Utils.dateStr config.timeZone (Utils.unixtimeToTime config.prediction.closesUnixtime) ++ ", and "
            ) ++
            ( if secondsToResolve > 0 then
                "the prediction should resolve " ++ (
                  if secondsToResolve < 86400 then
                    "in " ++ Utils.renderIntervalSeconds secondsToResolve
                  else
                    "on " ++ Utils.dateStr config.timeZone (Utils.unixtimeToTime config.prediction.resolvesAtUnixtime)
                ) ++ ". "
              else
                "the prediction should have resolved on " ++ Utils.dateStr config.timeZone (Utils.unixtimeToTime config.prediction.resolvesAtUnixtime) ++ ". Consider pinging the creator! "
            )
      Pb.ResolutionUnrecognized_ _ ->
        H.span [HA.style "color" "red"]
          [H.text "Oh dear, something has gone very strange with this prediction. Please email TODO with this URL to report it!"]
    , auditLog
    ]

viewWinnings : Config msg -> State -> Html msg
viewWinnings config _ =
  let
    auditLog : Html msg
    auditLog =
      if List.isEmpty config.prediction.yourTrades then H.text "" else
      H.details [HA.style "opacity" "50%"]
        [ H.summary [] [H.text "Details"]
        , config.prediction.yourTrades
          |> List.map (\t -> H.li [] [ H.text <| "[" ++ Utils.isoStr config.timeZone (Utils.unixtimeToTime t.transactedUnixtime) ++ "] "
                                     , Utils.renderUser t.bettor
                                     , H.text <| " bet " ++ (if t.bettorIsASkeptic then "NO" else "YES") ++ " staking " ++ Utils.formatCents t.bettorStakeCents ++ " against " ++ Utils.formatCents t.creatorStakeCents])
          |> H.ul []
        ]
    ifRes : Bool -> Html msg
    ifRes res =
      let creatorWinnings = creatorWinningsByBettor res config.prediction.yourTrades in
      case config.creatorRelationship of
        Self -> enumerateWinnings creatorWinnings
        LoggedOut -> H.text ""
        _ -> creatorWinnings |> D.values |> List.sum |> (\n -> -n) |> stateWinnings config.prediction.creator
  in
  if List.isEmpty config.prediction.yourTrades then H.text "" else
  H.div []
    [ case Utils.currentResolution config.prediction of
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
      Pb.ResolutionUnrecognized_ _ -> Debug.todo "unrecognized resolution"
    , auditLog
    ]

viewCreationParams : Config msg -> State -> Html msg
viewCreationParams config _ =
  let
    openTime = Utils.unixtimeToTime config.prediction.createdUnixtime
    certainty = Utils.mustPredictionCertainty config.prediction
  in
  H.p []
    [ H.text <| "On " ++ Utils.dateStr config.timeZone openTime ++ ", "
    , case config.creatorRelationship of
        Self -> Utils.b "you"
        _ -> Utils.renderUser config.prediction.creator
    , H.text " assigned this a "
    , certainty.low |> (*) 100 |> round |> String.fromInt |> H.text
    , H.text "-"
    , certainty.high |> (*) 100 |> round |> String.fromInt |> H.text
    , H.text "% chance, and staked "
    , config.prediction.maximumStakeCents |> Utils.formatCents |> H.text
    , case (config.prediction.maximumStakeCents - config.prediction.remainingStakeCentsVsSkeptics, config.prediction.maximumStakeCents - config.prediction.remainingStakeCentsVsBelievers) of
        (0, 0) -> H.text ""
        (promisedToSkeptics, 0) -> H.span [HA.style "opacity" "50%"] [H.text <| " (though they've already promised away " ++ Utils.formatCents promisedToSkeptics ++ " if this doesn't happen)"]
        (0, promisedToBelievers) -> H.span [HA.style "opacity" "50%"] [H.text <| " (though they've already promised away " ++ Utils.formatCents promisedToBelievers ++ " if this happens)"]
        (promisedToSkeptics, promisedToBelievers) -> H.span [HA.style "opacity" "50%"] [H.text <| " (though they've already promised away " ++ Utils.formatCents promisedToSkeptics ++ " if this doesn't happen, and " ++ Utils.formatCents promisedToBelievers ++ " if it does)"]
    , H.text "."
    ]

viewResolveButtons : Config msg -> State -> Html msg
viewResolveButtons config state =
  case config.creatorRelationship of
    Self ->
      H.div []
      [ let
          mistakeDetails =
            H.details [HA.style "color" "gray"]
              [ H.summary [] [H.text "Mistake?"]
              , H.text "If you resolved this prediction incorrectly, you can "
              , H.button
                [ HE.onClick <| config.resolve {state | working = True, notification = H.text ""} {predictionId=config.predictionId, resolution=Pb.ResolutionNoneYet, notes=""} ]
                [ H.text "un-resolve it." ]
              ]
        in
        case Utils.currentResolution config.prediction of
          Pb.ResolutionYes ->
            mistakeDetails
          Pb.ResolutionNo ->
            mistakeDetails
          Pb.ResolutionInvalid ->
            mistakeDetails
          Pb.ResolutionNoneYet ->
            H.div []
              [ H.button [HE.onClick <| config.resolve {state | working=True, notification=H.text ""} {predictionId=config.predictionId, resolution=Pb.ResolutionYes    , notes=""}] [H.text "Resolve YES"]
              , H.button [HE.onClick <| config.resolve {state | working=True, notification=H.text ""} {predictionId=config.predictionId, resolution=Pb.ResolutionNo     , notes=""}] [H.text "Resolve NO"]
              , H.button [HE.onClick <| config.resolve {state | working=True, notification=H.text ""} {predictionId=config.predictionId, resolution=Pb.ResolutionInvalid, notes=""}] [H.text "Resolve INVALID"]
              ]
          Pb.ResolutionUnrecognized_ _ -> Debug.todo "unrecognized resolution"
      , state.notification |> H.map never
      ]
    _ -> H.text ""

view : Config msg -> State -> Html msg
view config state =
  H.div []
    [ H.h2 [] [
        let text = H.text <| "Prediction: by " ++ (String.left 10 <| Iso8601.fromTime <| Utils.unixtimeToTime config.prediction.resolvesAtUnixtime) ++ ", " ++ config.prediction.prediction in
        if config.linkTitle then
          H.a [HA.href <| "/p/" ++ String.fromInt config.predictionId] [text]
        else
          text
        ]
    , viewPredictionState config state
    , viewResolveButtons config state
    , viewWinnings config state
    , H.hr [] []
    , viewCreationParams config state
    , case config.prediction.specialRules of
        "" ->
          H.text ""
        rules ->
          H.div []
            [ Utils.b "Special rules:"
            , H.text <| " " ++ rules
            ]
    , H.hr [] []
    , viewStakeWidgetOrExcuse config state
    ]

viewEmbedInfo : Config msg -> State -> Html msg
viewEmbedInfo config _ =
  let
    linkUrl = config.httpOrigin ++ "/p/" ++ String.fromInt config.predictionId  -- TODO(P0): needs origin to get stuck in text field
    imgUrl = config.httpOrigin ++ "/p/" ++ String.fromInt config.predictionId ++ "/embed.png"
    imgStyles = [("max-height","1.5ex"), ("border-bottom","1px solid #008800")]
    imgCode =
      "<a href=\"" ++ linkUrl ++ "\">"
      ++ "<img style=\"" ++ (imgStyles |> List.map (\(k,v) -> k++":"++v) |> String.join ";") ++ "\" src=\"" ++ imgUrl ++ "\" /></a>"
    linkText =
      "["
      ++ Utils.formatCents (config.prediction.maximumStakeCents // 100 * 100)
      ++ " @ "
      ++ String.fromInt (round <| (Utils.mustPredictionCertainty config.prediction).low * 100)
      ++ "-"
      ++ String.fromInt (round <| (Utils.mustPredictionCertainty config.prediction).high * 100)
      ++ "%]"
    linkCode =
      "<a href=\"" ++ linkUrl ++ "\">" ++ linkText ++ "</a>"
  in
    H.ul []
      [ H.li [] <|
        [ H.text "A linked inline image: "
        , CopyWidget.view config.copy imgCode
        , H.br [] []
        , H.text "This would render as: "
        , H.a [HA.href linkUrl]
          [ H.img (HA.src imgUrl :: (imgStyles |> List.map (\(k,v) -> HA.style k v))) []]
        ]
      , H.li [] <|
        [ H.text "A boring old link: "
        , CopyWidget.view config.copy linkCode
        , H.br [] []
        , H.text "This would render as: "
        , H.a [HA.href linkUrl] [H.text linkText]
        ]
      ]

handleStakeResponse : Result Http.Error Pb.StakeResponse -> State -> State
handleStakeResponse res state =
  { state | working = False
          , notification = case API.simplifyStakeResponse res of
              Ok _ -> H.text ""
              Err e -> Utils.redText e
  }

handleResolveResponse : Result Http.Error Pb.ResolveResponse -> State -> State
handleResolveResponse res state =
  { state | working = False
          , notification = case API.simplifyResolveResponse res of
              Ok _ -> H.text ""
              Err e -> Utils.redText e
  }
