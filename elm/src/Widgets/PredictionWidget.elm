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
import Globals

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
  , creatorRelationship : Globals.TrustRelationship
  , timeZone : Time.Zone
  , now : Time.Posix
  }
type alias State =
  { stakeField : String
  , bettorSkepticismField : Skepticism
  , invitationWidget : SmallInvitationWidget.State
  , working : Bool
  , notification : Html Never
  }

type Skepticism = Skeptic | Believer

init : State
init =
  { stakeField = "0"
  , bettorSkepticismField = Skeptic
  , invitationWidget = SmallInvitationWidget.init
  , working = False
  , notification = H.text ""
  }

isBettorASkeptic : Config msg -> State -> Bool
isBettorASkeptic config state =
  let certainty = config.prediction |> Utils.mustPredictionCertainty in
  if certainty.high == 1.0 then
    True
  else if certainty.low == 0.0 then
    False
  else
    case state.bettorSkepticismField of
      Skeptic -> True
      Believer -> False

viewWillWontDropdown : Config msg -> State -> Html msg
viewWillWontDropdown config state =
  let certainty = config.prediction |> Utils.mustPredictionCertainty in
  if certainty.high == 1.0 then
    H.text "won't"
  else if certainty.low == 0.0 then
    H.text "will"
  else
    H.select
      [ HE.onInput (\s -> config.setState { state | bettorSkepticismField = case s of
          "won't" -> Skeptic
          "will" -> Believer
          _ -> Debug.todo <| "invalid value" ++ Debug.toString s ++ "for skepticism dropdown"
        })
      ]
      [ H.option [HA.value "won't", HA.selected <| isBettorASkeptic config state] [H.text "won't"]
      , H.option [HA.value "will", HA.selected <| not <| isBettorASkeptic config state] [H.text "will"]
      ]

viewStakeWidgetOrExcuse : Config msg -> State -> Html msg
viewStakeWidgetOrExcuse config state =
  let
    explanationWhyNotBettable =
      if Utils.resolutionIsTerminal (Utils.currentResolution config.prediction) then
        Just <| H.text "This prediction has resolved, so cannot be bet in."
      else if config.prediction.closesUnixtime < Utils.timeToUnixtime config.now then
        Just <| H.text <| "This prediction closed on " ++ Utils.dateStr config.timeZone (Utils.predictionClosesTime config.prediction) ++ "."
      else
        case config.creatorRelationship of
          Globals.LoggedOut ->
            Just <| H.span []
              [ H.text "You'll need to "
              , H.a [HA.href <| "/login?dest=" ++ Utils.pathToPrediction config.predictionId] [H.text "log in"]
              , H.text " if you want to bet on this prediction!"
              ]
          Globals.Self ->
            Just <| H.text "(You can't bet on your own predictions.)"
          Globals.Friends ->
            Nothing
          Globals.NoRelation ->
            Just <| H.span []
              [ H.text "You can't bet on this prediction yet, because you and "
              , Utils.renderUser config.prediction.creator
              , H.text " haven't told me that you trust each other to pay up if you lose! If, in real life, you "
              , Utils.i "do"
              , H.text " trust each other to pay your debts, send them an invitation! "
              , config.invitationWidget
              ]
          Globals.TrustsCurrentUser ->
            Just <| H.span []
              [ H.text "You don't trust "
              , Utils.renderUser config.prediction.creator
              , H.text " to pay their debts, so you probably don't want to bet on this prediction. If you actually "
              , Utils.i "do"
              , H.text " trust them to pay their debts, send them an invitation link: "
              , config.invitationWidget
              ]
          Globals.TrustedByCurrentUser ->
            Just <| H.span []
              [ Utils.renderUser config.prediction.creator, H.text " hasn't told me that they trust you! If you think that, in real life, they "
              , Utils.i "do"
              , H.text " trust you to pay your debts, send them an invitation link: "
              , config.invitationWidget
              , H.br [] []
              , H.text "Once they accept it, I'll know you trust each other, and I'll let you bet against each other."
              ]
  in
    case explanationWhyNotBettable of
      Nothing ->
        viewStakeWidget BettingEnabled config state
      Just expl ->
        expl

type Bettability = BettingEnabled | BettingDisabled
viewStakeWidget : Bettability -> Config msg -> State -> Html msg
viewStakeWidget bettability config state =
  let
    certainty = Utils.mustPredictionCertainty config.prediction

    disableInputs = case bettability of
      BettingEnabled -> False
      BettingDisabled -> True
    bettorIsASkeptic = isBettorASkeptic config state
    creatorStakeFactor =
      if bettorIsASkeptic then
        certainty.low / (1 - certainty.low)
      else
        (1 - certainty.high) / certainty.high
    remainingCreatorStake =
      if bettorIsASkeptic then
        config.prediction.remainingStakeCentsVsSkeptics
      else
        config.prediction.remainingStakeCentsVsBelievers
    maxBettorStakeCents =
      if creatorStakeFactor == 0 then
        0
      else
        toFloat remainingCreatorStake / creatorStakeFactor + 0.001 |> floor
    stakeCents = parseCents {max=maxBettorStakeCents} state.stakeField
  in
  H.span []
    [ H.text " Bet $"
    , H.input
        [ HA.style "width" "5em"
        , HA.type_"number", HA.min "0", HA.max (toFloat maxBettorStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
        , HA.disabled disableInputs
        , HE.onInput (\s -> config.setState {state | stakeField = s})
        , HA.value state.stakeField
        ]
        []
      |> Utils.appendValidationError (Utils.resultToErr stakeCents)
    , H.text " that this "
    , viewWillWontDropdown config state
    , H.text <| " happen, against " ++ config.prediction.creator ++ "'s "
    , Utils.b (stakeCents |> Result.map (toFloat >> (*) creatorStakeFactor >> round >> Utils.formatCents) |> Result.withDefault "???")
    , H.text " that it "
    , H.text <| if isBettorASkeptic config state then "will" else "won't"
    , H.text ". "
    , H.button
        (case stakeCents of
          Ok stake ->
            [ HA.disabled disableInputs
            , HE.onClick (config.stake {state | working=True, notification=H.text ""} {predictionId=config.predictionId, bettorIsASkeptic=bettorIsASkeptic, bettorStakeCents=stake})
            ]
          Err _ ->
            [ HA.disabled True ]
        )
        [H.text "Commit"]
    , state.notification |> H.map never
    , if isBettorASkeptic config state then
        if config.prediction.remainingStakeCentsVsSkeptics /= config.prediction.maximumStakeCents then
          H.div [HA.style "opacity" "50%"] [H.text <| "(only " ++ Utils.formatCents config.prediction.remainingStakeCentsVsSkeptics ++ " of ", Utils.renderUser config.prediction.creator, H.text <| "'s initial stake remains, since they've already accepted some bets)"]
        else
          H.text ""
      else
        if config.prediction.remainingStakeCentsVsBelievers /= config.prediction.maximumStakeCents then
          H.div [HA.style "opacity" "50%"] [H.text <| "(only " ++ Utils.formatCents config.prediction.remainingStakeCentsVsBelievers ++ " of ", Utils.renderUser config.prediction.creator, H.text <| "'s initial stake remains, since they've already accepted some bets)"]
        else
          H.text ""

    ]

parseCents : {max:Cents} -> String -> Result String Cents
parseCents {max} s =
  case String.toFloat s of
    Nothing -> Err "must be a number"
    Just dollars ->
      let n = round (100*dollars) in
      if n < 0 || n > max then Err ("must be between $0 and " ++ Utils.formatCents max) else Ok n

viewResolutionRow : Config msg -> State -> Html msg
viewResolutionRow config state =
  let
    auditLog : Html msg
    auditLog =
      if List.isEmpty config.prediction.resolutions then H.text "" else
      H.details [HA.style "display" "inline-block", HA.style "opacity" "50%"]
        [ H.summary [] [H.text "History"]
        , makeTable [HA.class "resolution-history-table"]
          [ ( [H.text "When"]
            , \event -> [H.text <| Utils.isoStr config.timeZone (Utils.unixtimeToTime event.unixtime)]
            )
          , ( [H.text "Resolution"]
            , \event -> [ H.text <| case event.resolution of
                  Pb.ResolutionYes -> "YES"
                  Pb.ResolutionNo -> "NO"
                  Pb.ResolutionInvalid -> "INVALID"
                  Pb.ResolutionNoneYet -> "UN-RESOLVED"
                  Pb.ResolutionUnrecognized_ _ -> "(??? unrecognized resolution ???)"
                ]
            )
          ]
          config.prediction.resolutions
        ]
  in
  H.tr []
  [ H.td [] [Utils.b "Resolution:"]
  , H.td []
    [ case Utils.currentResolution config.prediction of
        Pb.ResolutionYes ->
          H.text "YES"
        Pb.ResolutionNo ->
          H.text "NO"
        Pb.ResolutionInvalid ->
          H.text "INVALID"
        Pb.ResolutionNoneYet ->
          H.text <|
            "none yet"
            ++ if config.prediction.resolvesAtUnixtime < Utils.timeToUnixtime config.now then
              " (even though it should have resolved by now! Consider nudging the creator.)"
            else
              ""
        Pb.ResolutionUnrecognized_ _ ->
          H.span [HA.style "color" "red"]
            [ H.text "Oh dear, something has gone very strange with this prediction. Please "
            , H.a [HA.href "mailto:bugs@biatob.com"] [H.text "email bugs@biatob.com"]
            , H.text " with this URL to report it!"
            ]
    , H.text " "
    , auditLog
    ]
  ]

makeTable : List (H.Attribute msg) -> List (List (Html msg), a -> List (Html msg)) -> List a -> Html msg
makeTable tableAttrs columns xs =
  let
    headerRow = H.tr [] <| List.map (\(header, _) -> H.th [] header) columns
    dataRows = List.map (\x -> H.tr [] (List.map (\(_, toTd) -> H.td [] (toTd x)) columns)) xs
  in
  H.table tableAttrs (headerRow :: dataRows)

groupTradesByBettor : List Pb.Trade -> Dict Username (List Pb.Trade)
groupTradesByBettor trades =
  let
    help : Dict Username (List Pb.Trade) -> List Pb.Trade -> Dict Username (List Pb.Trade)
    help accum remainder =
      case remainder of
        [] -> accum
        t :: rest -> help (accum |> D.update t.bettor (Maybe.withDefault [] >> (::) t >> Just)) rest
  in
    help D.empty trades

getTotalCreatorWinnings : Bool -> List Pb.Trade -> Cents
getTotalCreatorWinnings resolvedYes trades =
  trades
  |> List.map (\t -> if (resolvedYes == t.bettorIsASkeptic) then t.bettorStakeCents else -t.creatorStakeCents)
  |> List.sum

formatYouWin : Cents -> String
formatYouWin wonCents =
  if wonCents > 0 then
    "you win " ++ Utils.formatCents wonCents
  else
    "you owe " ++ Utils.formatCents (-wonCents)

viewTrades : Config msg -> State -> Html msg
viewTrades config _ =
  let
    allTradesDetails : Bool -> Username -> List Pb.Trade -> Html msg
    allTradesDetails viewerIsBettor counterparty trades =
      H.details [HA.style "opacity" "50%"]
      [ H.summary [] [H.text "All trades"]
      , makeTable [HA.class "all-trades-details-table"]
        [ ( [H.text "When"]
          , \t -> [H.text (Utils.isoStr config.timeZone (Utils.unixtimeToTime t.transactedUnixtime))]
          )
        , ( if viewerIsBettor then [H.text "Your side"] else [Utils.renderUser counterparty, H.text "'s side"]
          , \t -> [H.text <| if t.bettorIsASkeptic then "NO" else "YES"]
          )
        , ( if viewerIsBettor then [H.text "You staked"] else [Utils.renderUser counterparty, H.text "'s stake"]
          , \t -> [H.text <| Utils.formatCents t.bettorStakeCents]
          )
        , ( if viewerIsBettor then [Utils.renderUser counterparty, H.text "'s stake"] else [H.text "Your stake"]
          , \t -> [H.text <| Utils.formatCents t.creatorStakeCents]
          )
        ]
        trades
      ]
  in
  case config.creatorRelationship of
    Globals.LoggedOut -> H.text ""
    Globals.Self ->
      let
        tradesByBettor = groupTradesByBettor config.prediction.yourTrades
        bettorColumn =
          ( [H.text "Bettor"]
          , \(bettor, trades) ->
            [ Utils.renderUser bettor
            , allTradesDetails False bettor trades
            ]
          )
        winningsColumns =
          case Utils.currentResolution config.prediction of
            Pb.ResolutionYes ->
              [ ( [H.text "Winnings"]
                , \(_, trades) -> [H.text <| formatYouWin <| getTotalCreatorWinnings True trades]
                )
              ]
            Pb.ResolutionNo ->
              [ ( [H.text "Winnings"]
                , \(_, trades) -> [H.text <| formatYouWin <| getTotalCreatorWinnings False trades]
                )
              ]
            Pb.ResolutionInvalid ->
              [ ( [H.text "if YES"]
                , \(_, trades) -> [H.text <| formatYouWin <| getTotalCreatorWinnings True trades]
                )
              , ( [H.text "if NO"]
                , \(_, trades) -> [H.text <| formatYouWin <| getTotalCreatorWinnings False trades]
                )
              ]
            Pb.ResolutionNoneYet ->
              [ ( [H.text "if YES"]
                , \(_, trades) -> [H.text <| formatYouWin <| getTotalCreatorWinnings True trades]
                )
              , ( [H.text "if NO"]
                , \(_, trades) -> [H.text <| formatYouWin <| getTotalCreatorWinnings False trades]
                )
              ]
            Pb.ResolutionUnrecognized_ _ ->
              []
      in
        makeTable [HA.class "winnings-by-bettor-table"] (bettorColumn :: winningsColumns) (D.toList tradesByBettor)

    _ ->
      case Utils.currentResolution config.prediction of
        Pb.ResolutionYes ->
          H.span []
          [ H.text "Resolved YES: "
          , Utils.b <| formatYouWin -(getTotalCreatorWinnings True config.prediction.yourTrades) ++ "!"
          , allTradesDetails True config.prediction.creator config.prediction.yourTrades
          ]
        Pb.ResolutionNo ->
          H.span []
          [ H.text "Resolved NO: "
          , Utils.b <| formatYouWin -(getTotalCreatorWinnings False config.prediction.yourTrades) ++ "!"
          , allTradesDetails True config.prediction.creator config.prediction.yourTrades
          ]
        Pb.ResolutionInvalid ->
          H.span []
          [ H.text <| "If YES, " ++ formatYouWin -(getTotalCreatorWinnings True config.prediction.yourTrades)
          , H.text <| "; if NO, " ++ formatYouWin -(getTotalCreatorWinnings False config.prediction.yourTrades)
          , H.text "."
          , allTradesDetails True config.prediction.creator config.prediction.yourTrades
          ]
        Pb.ResolutionNoneYet ->
          H.span []
          [ H.text <| "If YES, " ++ formatYouWin -(getTotalCreatorWinnings True config.prediction.yourTrades)
          , H.text <| "; if NO, " ++ formatYouWin -(getTotalCreatorWinnings False config.prediction.yourTrades)
          , H.text "."
          , allTradesDetails True config.prediction.creator config.prediction.yourTrades
          ]
        Pb.ResolutionUnrecognized_ _ ->
          H.text "??????"

viewResolveButtons : Config msg -> State -> Html msg
viewResolveButtons config state =
  case config.creatorRelationship of
    Globals.Self ->
      let
        mistakeInfo =
          H.span [HA.style "color" "gray"]
            [ H.text " Mistake? You can always "
            , H.button
              [ HE.onClick <| config.resolve {state | working = True, notification = H.text ""} {predictionId=config.predictionId, resolution=Pb.ResolutionNoneYet, notes=""} ]
              [ H.text "un-resolve it." ]
            ]
      in
        H.div []
        [ Utils.b "Resolve this prediction: "
        , case Utils.currentResolution config.prediction of
            Pb.ResolutionYes ->
              mistakeInfo
            Pb.ResolutionNo ->
              mistakeInfo
            Pb.ResolutionInvalid ->
              mistakeInfo
            Pb.ResolutionNoneYet ->
              H.span []
              [ H.button [HE.onClick <| config.resolve {state | working=True, notification=H.text ""} {predictionId=config.predictionId, resolution=Pb.ResolutionYes    , notes=""}] [H.text "Resolve YES"]
              , H.button [HE.onClick <| config.resolve {state | working=True, notification=H.text ""} {predictionId=config.predictionId, resolution=Pb.ResolutionNo     , notes=""}] [H.text "Resolve NO"]
              , H.button [HE.onClick <| config.resolve {state | working=True, notification=H.text ""} {predictionId=config.predictionId, resolution=Pb.ResolutionInvalid, notes=""}] [H.text "Resolve INVALID"]
              ]
            Pb.ResolutionUnrecognized_ _ ->
              H.span []
              [ H.span [HA.style "color" "red"] [H.text "unrecognized resolution"]
              , mistakeInfo
              ]
        , state.notification |> H.map never
        ]
    _ -> H.text ""

view : Config msg -> State -> Html msg
view config state =
  H.div []
    [ H.h2 [] [
        let text = H.text <| "Prediction: by " ++ (Utils.dateStr config.timeZone <| Utils.unixtimeToTime config.prediction.resolvesAtUnixtime) ++ ", " ++ config.prediction.prediction in
        if config.linkTitle then
          H.a [HA.href <| Utils.pathToPrediction config.predictionId] [text]
        else
          text
        ]
    , H.table [HA.class "prediction-summary-table"]
      [ H.tr []
        [ H.td [] [Utils.b "Prediction by:"]
        , H.td [] [Utils.renderUser config.prediction.creator]
        ]
      , H.tr []
        [ H.td [] [Utils.b "Confidence:"]
        , H.td [] [H.text <|
            (String.fromInt <| round <| 100 * (Utils.mustPredictionCertainty config.prediction).low)
            ++ "-" ++
            (String.fromInt <| round <| 100 * (Utils.mustPredictionCertainty config.prediction).high)
            ++ "%"]
        ]
      , H.tr []
        [ H.td [] [Utils.b "Stakes:"]
        , H.td [] [H.text <| "up to " ++ Utils.formatCents config.prediction.maximumStakeCents]
        ]
      , H.tr []
        [ H.td [] [Utils.b "Created on:"]
        , H.td [] [H.text <| Utils.dateStr config.timeZone (Utils.unixtimeToTime config.prediction.createdUnixtime)]
        ]
      , H.tr []
        [ H.td [] [Utils.b "Betting closes:"]
        , H.td [] [H.text <| Utils.dateStr config.timeZone (Utils.unixtimeToTime config.prediction.closesUnixtime)]
        ]
      , viewResolutionRow config state
      , case config.prediction.specialRules of
          "" ->
            H.text ""
          rules ->
            H.tr []
            [ H.td [] [Utils.b "Special rules:"]
            , H.td [] [H.text rules]
            ]
      ]
    , if List.isEmpty config.prediction.yourTrades then
        H.text ""
      else
        H.div []
        [ H.hr [] []
        , Utils.b "Your existing stake: "
        , viewTrades config state
        ]
    , H.hr [] []
    , case config.creatorRelationship of
        Globals.Self ->
          viewResolveButtons config state
        _ ->
          H.div []
          [ Utils.b "Make a bet: "
          , viewStakeWidgetOrExcuse config state
          ]
    ]

viewEmbedInfo : Config msg -> State -> Html msg
viewEmbedInfo config _ =
  let
    linkUrl = config.httpOrigin ++ Utils.pathToPrediction config.predictionId
    imgUrl = config.httpOrigin ++ Utils.pathToPrediction config.predictionId ++ "/embed.png"
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
              Ok _ -> Utils.greenText "Committed!"
              Err e -> Utils.redText e
          , stakeField = case API.simplifyStakeResponse res of
              Ok _ -> "0"
              Err _ -> state.stakeField
  }

handleResolveResponse : Result Http.Error Pb.ResolveResponse -> State -> State
handleResolveResponse res state =
  { state | working = False
          , notification = case API.simplifyResolveResponse res of
              Ok _ -> Utils.greenText "Resolved!"
              Err e -> Utils.redText e
  }
