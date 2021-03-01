module Widgets.PredictionWidget exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD
import Time
import Dict as D exposing (Dict)

import Iso8601
import Biatob.Proto.Mvp as Pb
import Utils

import Widgets.StakeWidget as StakeWidget
import Widgets.CopyWidget as CopyWidget
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Page

type Msg
  = InvitationMsg SmallInvitationWidget.Msg
  | StakeMsg StakeWidget.Msg
  | Copy String
  | Resolve Int Pb.Resolution
  | ResolveFinished (Result Http.Error Pb.ResolveResponse)
type alias Context =
  { predictionId : Int
  , prediction : Pb.UserPredictionView
  , shouldLinkTitle : Bool
  }
type ContextEvent = SetPrediction Pb.UserPredictionView
type alias Model =
  { stakeForm : StakeWidget.Model
  , working : Bool
  , notification : Html Never
  , invitationWidget : SmallInvitationWidget.Model
  }

init : Int -> Model
init predictionId =
  { stakeForm = StakeWidget.init
  , working = False
  , notification = H.text ""
  , invitationWidget = SmallInvitationWidget.init (Just <| "/p/" ++ String.fromInt predictionId)
  }

update : Msg -> Model -> ( Model , Page.Command Msg, Maybe ContextEvent )
update msg model =
  case msg of
    InvitationMsg widgetMsg ->
      let (newWidget, widgetCmd) = SmallInvitationWidget.update widgetMsg model.invitationWidget in
      ( { model | invitationWidget = newWidget }
      , Page.mapCmd InvitationMsg widgetCmd
      , Nothing
      )
    StakeMsg widgetMsg ->
      let (newWidget, widgetCmd, event) = StakeWidget.update widgetMsg model.stakeForm in
      ( { model | stakeForm = newWidget }
      , Page.mapCmd StakeMsg widgetCmd
      , case event of
          Nothing -> Nothing
          Just (StakeWidget.SetPrediction pred) -> Just (SetPrediction pred)
      )
    Copy s ->
      ( model
      , Page.CopyCmd s
      , Nothing
      )

    Resolve predictionId resolution ->
      ( { model | working = True , notification = H.text "" }
      , Page.RequestCmd <| Page.ResolveRequest ResolveFinished {predictionId=predictionId, resolution=resolution, notes=""}
      , Nothing
      )
    ResolveFinished res ->
      case res of
        Err e ->
          ( { model | working = False , notification = Utils.redText (Debug.toString e) } , Page.NoCmd , Nothing )
        Ok resp ->
          case resp.resolveResult of
            Just (Pb.ResolveResultOk newPrediction) ->
              ( { model | working = False , notification = H.text "" } , Page.NoCmd , Just (SetPrediction newPrediction) )
            Just (Pb.ResolveResultError e) ->
              ( { model | working = False , notification = Utils.redText (Debug.toString e) } , Page.NoCmd , Nothing )
            Nothing ->
              ( { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" } , Page.NoCmd , Nothing )

viewStakeWidgetOrExcuse : Context -> Page.Globals -> Model -> Html Msg
viewStakeWidgetOrExcuse ctx globals model =
  let creator = Utils.mustPredictionCreator ctx.prediction in
  if Utils.resolutionIsTerminal (Utils.currentResolution ctx.prediction) then
    H.text "This prediction has resolved, so cannot be bet in."
  else if ctx.prediction.closesUnixtime < Utils.timeToUnixtime globals.now then
    H.text <| "This prediction closed on " ++ Utils.dateStr globals.timeZone (Utils.predictionClosesTime ctx.prediction) ++ "."
  else if not (Page.isLoggedIn globals) then
    H.div []
      [ H.text "You must be logged in to participate in this prediction!"
      ]
  else
    if creator.isSelf then
      H.text ""
    else case (creator.trustsYou, creator.isTrusted) of
      (True, True) ->
        StakeWidget.view {prediction=ctx.prediction, predictionId=ctx.predictionId, disableCommit=False{- TODO -}} globals model.stakeForm |> H.map StakeMsg
      (False, False) ->
        H.div []
          [ H.text <| "You and " ++ creator.displayName ++ " don't trust each other! If, in real life, you "
          , H.i [] [H.text "do"]
          , H.text " trust each other to pay your debts, send them an invitation! "
          , SmallInvitationWidget.view globals model.invitationWidget |> H.map InvitationMsg
          ]
      (True, False) ->
        H.div []
          [ H.text <| "You don't trust " ++ creator.displayName ++ "."
          -- TODO(P0)
          ]
      (False, True) ->
        H.div []
          [ H.text <| creator.displayName ++ " hasn't marked you as trusted! If you think that, in real life, they "
          , H.i [] [H.text "do"]
          , H.text " trust you to pay your debts, send them an invitation link: "
          , SmallInvitationWidget.view globals model.invitationWidget |> H.map InvitationMsg
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
    |> List.sortBy (\(b, _) -> b)
    |> List.map (\(b, win) -> H.li [] [H.text <| stateWinnings b win])
    )

viewPredictionState : Context -> Page.Globals -> Model -> Html Msg
viewPredictionState ctx globals model =
  let
    auditLog : Html Msg
    auditLog =
      if List.isEmpty ctx.prediction.resolutions then H.text "" else
      H.details [HA.style "opacity" "50%"]
        [ H.summary [] [H.text "Details"]
        , ctx.prediction.resolutions
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
    [ case Utils.currentResolution ctx.prediction of
      Pb.ResolutionYes ->
        H.text "This prediction has resolved YES. "
      Pb.ResolutionNo ->
        H.text "This prediction has resolved NO. "
      Pb.ResolutionInvalid ->
        H.text "This prediction has resolved INVALID. "
      Pb.ResolutionNoneYet ->
        let
          secondsToClose = ctx.prediction.closesUnixtime - Utils.timeToUnixtime globals.now
          secondsToResolve = ctx.prediction.resolvesAtUnixtime - Utils.timeToUnixtime globals.now
        in
          H.text <|
            ( if secondsToClose > 0 then
                "Betting closes " ++ (
                  if secondsToClose < 86400 then
                    "in " ++ Utils.renderIntervalSeconds secondsToClose
                  else
                    "on " ++ Utils.dateStr globals.timeZone (Utils.unixtimeToTime ctx.prediction.closesUnixtime)
                ) ++ ", and "
              else
                "Betting closed on" ++ Utils.dateStr globals.timeZone (Utils.unixtimeToTime ctx.prediction.closesUnixtime) ++ ", and "
            ) ++
            ( if secondsToResolve > 0 then
                "the prediction should resolve " ++ (
                  if secondsToResolve < 86400 then
                    "in " ++ Utils.renderIntervalSeconds secondsToResolve
                  else
                    "on " ++ Utils.dateStr globals.timeZone (Utils.unixtimeToTime ctx.prediction.resolvesAtUnixtime)
                ) ++ ". "
              else
                "the prediction should have resolved on " ++ Utils.dateStr globals.timeZone (Utils.unixtimeToTime ctx.prediction.resolvesAtUnixtime) ++ ". Consider pinging the creator! "
            )
      Pb.ResolutionUnrecognized_ _ ->
        H.span [HA.style "color" "red"]
          [H.text "Oh dear, something has gone very strange with this prediction. Please email TODO with this URL to report it!"]
    , auditLog
    ]

viewWinnings : Context -> Page.Globals -> Model -> Html Msg
viewWinnings ctx globals model =
  let
    auditLog : Html Msg
    auditLog =
      if List.isEmpty ctx.prediction.yourTrades then H.text "" else
      H.details [HA.style "opacity" "50%"]
        [ H.summary [] [H.text "Details"]
        , ctx.prediction.yourTrades
          |> List.map (\t -> H.li [] [ H.text <| "[" ++ Utils.isoStr Time.utc (Utils.unixtimeToTime t.transactedUnixtime) ++ " UTC] "
                                     , Utils.renderUser (Utils.mustTradeBettor t)
                                     , H.text <| " bet " ++ (if t.bettorIsASkeptic then "NO" else "YES") ++ " staking " ++ Utils.formatCents t.bettorStakeCents ++ " against " ++ Utils.formatCents t.creatorStakeCents])
          |> H.ul []
        ]
    ifRes : Bool -> Html Msg
    ifRes res =
      creatorWinningsByBettor res ctx.prediction.yourTrades
        |> let creator = Utils.mustPredictionCreator ctx.prediction in
            if creator.isSelf then
              enumerateWinnings
            else
              (D.values >> List.sum >> (\n -> -n) >> stateWinnings creator.displayName >> H.text)
  in
  if List.isEmpty ctx.prediction.yourTrades then H.text "" else
  H.div []
    [ case Utils.currentResolution ctx.prediction of
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

viewCreationParams : Context -> Page.Globals -> Model -> Html Msg
viewCreationParams ctx globals model =
  let
    creator = Utils.mustPredictionCreator ctx.prediction
    openTime = Utils.unixtimeToTime ctx.prediction.createdUnixtime
    certainty = Utils.mustPredictionCertainty ctx.prediction
  in
  H.p []
    [ H.text <| "On " ++ Utils.dateStr globals.timeZone openTime ++ ", "
    , H.strong [] [H.text <| if creator.isSelf then "you" else creator.displayName]
    , H.text " assigned this a "
    , certainty.low |> (*) 100 |> round |> String.fromInt |> H.text
    , H.text "-"
    , certainty.high |> (*) 100 |> round |> String.fromInt |> H.text
    , H.text "% chance, and staked "
    , ctx.prediction.maximumStakeCents |> Utils.formatCents |> H.text
    , case (ctx.prediction.maximumStakeCents - ctx.prediction.remainingStakeCentsVsSkeptics, ctx.prediction.maximumStakeCents - ctx.prediction.remainingStakeCentsVsBelievers) of
        (0, 0) -> H.text ""
        (promisedToSkeptics, 0) -> H.span [HA.style "opacity" "50%"] [H.text <| " (though they've already promised away " ++ Utils.formatCents promisedToSkeptics ++ " if this doesn't happen)"]
        (0, promisedToBelievers) -> H.span [HA.style "opacity" "50%"] [H.text <| " (though they've already promised away " ++ Utils.formatCents promisedToBelievers ++ " if this happens)"]
        (promisedToSkeptics, promisedToBelievers) -> H.span [HA.style "opacity" "50%"] [H.text <| " (though they've already promised away " ++ Utils.formatCents promisedToSkeptics ++ " if this doesn't happen, and " ++ Utils.formatCents promisedToBelievers ++ " if it does)"]
    , H.text "."
    ]

viewResolveButtons : Context -> Page.Globals -> Model -> Html Msg
viewResolveButtons ctx globals model =
  if (Utils.mustPredictionCreator ctx.prediction).isSelf then
    H.div []
      [ let
          mistakeDetails =
            H.details [HA.style "color" "gray"]
              [ H.summary [] [H.text "Mistake?"]
              , H.text "If you resolved this prediction incorrectly, you can "
              , H.button [HE.onClick (Resolve ctx.predictionId Pb.ResolutionNoneYet)] [H.text "un-resolve it."]
              ]
        in
        case Utils.currentResolution ctx.prediction of
          Pb.ResolutionYes ->
            mistakeDetails
          Pb.ResolutionNo ->
            mistakeDetails
          Pb.ResolutionInvalid ->
            mistakeDetails
          Pb.ResolutionNoneYet ->
            H.div []
              [ H.button [HE.onClick (Resolve ctx.predictionId Pb.ResolutionYes    )] [H.text "Resolve YES"]
              , H.button [HE.onClick (Resolve ctx.predictionId Pb.ResolutionNo     )] [H.text "Resolve NO"]
              , H.button [HE.onClick (Resolve ctx.predictionId Pb.ResolutionInvalid)] [H.text "Resolve INVALID"]
              ]
          Pb.ResolutionUnrecognized_ _ -> Debug.todo "unrecognized resolution"
      , model.notification |> H.map never
      ]
  else
    H.text ""

view : Context -> Page.Globals -> Model -> Html Msg
view ctx globals model =
  let
    creator = Utils.mustPredictionCreator ctx.prediction
  in
  H.div []
    [ H.h2 [] [
        let text = H.text <| "Prediction: by " ++ (String.left 10 <| Iso8601.fromTime <| Utils.unixtimeToTime ctx.prediction.resolvesAtUnixtime) ++ ", " ++ ctx.prediction.prediction in
        if ctx.shouldLinkTitle then
          H.a [HA.href <| "/p/" ++ String.fromInt ctx.predictionId] [text]
        else
          text
        ]
    , viewPredictionState ctx globals model
    , viewResolveButtons ctx globals model
    , viewWinnings ctx globals model
    , H.hr [] []
    , viewCreationParams ctx globals model
    , case ctx.prediction.specialRules of
        "" ->
          H.text ""
        rules ->
          H.div []
            [ H.strong [] [H.text "Special rules:"]
            , H.text <| " " ++ rules
            ]
    , H.hr [] []
    , viewStakeWidgetOrExcuse ctx globals model
    , if creator.isSelf then
        H.div []
          [ H.text "If you want to link to your prediction, here are some snippets of HTML you could copy-paste:"
          , viewEmbedInfo ctx globals model
          , H.text "If there are people you want to participate, but you haven't already established trust with them in Biatob, send them invitations: "
          , SmallInvitationWidget.view globals model.invitationWidget |> H.map InvitationMsg
          ]
      else
        H.text ""
    ]

viewEmbedInfo : Context -> Page.Globals -> Model -> Html Msg
viewEmbedInfo ctx globals model =
  let
    linkUrl = globals.httpOrigin ++ "/p/" ++ String.fromInt ctx.predictionId  -- TODO(P0): needs origin to get stuck in text field
    imgUrl = globals.httpOrigin ++ "/p/" ++ String.fromInt ctx.predictionId ++ "/embed.png"
    imgStyles = [("max-height","1.5ex"), ("border-bottom","1px solid #008800")]
    imgCode =
      "<a href=\"" ++ linkUrl ++ "\">"
      ++ "<img style=\"" ++ (imgStyles |> List.map (\(k,v) -> k++":"++v) |> String.join ";") ++ "\" src=\"" ++ imgUrl ++ "\" /></a>"
    linkText =
      "["
      ++ Utils.formatCents (ctx.prediction.maximumStakeCents // 100 * 100)
      ++ " @ "
      ++ String.fromInt (round <| (Utils.mustPredictionCertainty ctx.prediction).low * 100)
      ++ "-"
      ++ String.fromInt (round <| (Utils.mustPredictionCertainty ctx.prediction).high * 100)
      ++ "%]"
    linkCode =
      "<a href=\"" ++ linkUrl ++ "\">" ++ linkText ++ "</a>"
  in
    H.ul []
      [ H.li [] <|
        [ H.text "A linked inline image: "
        , CopyWidget.view Copy imgCode
        , H.br [] []
        , H.text "This would render as: "
        , H.a [HA.href linkUrl]
          [ H.img (HA.src imgUrl :: (imgStyles |> List.map (\(k,v) -> HA.style k v))) []]
        ]
      , H.li [] <|
        [ H.text "A boring old link: "
        , CopyWidget.view Copy linkCode
        , H.br [] []
        , H.text "This would render as: "
        , H.a [HA.href linkUrl] [H.text linkText]
        ]
      ]
