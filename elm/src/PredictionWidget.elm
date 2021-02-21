module PredictionWidget exposing (..)

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

import StakeForm
import CopyWidget
import SmallInvitationWidget

type Event
  = CreateInvitation
  | Copy String
  | Staked {bettorIsASkeptic:Bool, bettorStakeCents:Int}
  | Resolve Pb.Resolution
type alias Context msg =
  { auth : Maybe Pb.AuthToken
  , prediction : Pb.UserPredictionView
  , predictionId : Int
  , now : Time.Posix
  , httpOrigin : String
  , handle : Maybe Event -> State -> msg
  }
type alias State =
  { stakeForm : StakeForm.State
  , working : Bool
  , notification : Html ()
  , invitationWidget : SmallInvitationWidget.State
  }

invitationWidgetCtx : Context msg -> State -> SmallInvitationWidget.Context msg
invitationWidgetCtx ctx state =
  { httpOrigin = ctx.httpOrigin
  , destination = Just <| "/p/" ++ String.fromInt ctx.predictionId
  , handle = \e m ->
      let
        event = case e of
          Nothing -> Nothing
          Just (SmallInvitationWidget.Copy s) -> Just (Copy s)
          Just SmallInvitationWidget.CreateInvitation -> Just (CreateInvitation)
      in
      ctx.handle event { state | invitationWidget = m }
  }

init : State
init =
  { stakeForm = StakeForm.init
  , working = False
  , notification = H.text ""
  , invitationWidget = SmallInvitationWidget.init
  }

handleStakeResponse : Result Http.Error Pb.StakeResponse -> State -> State
handleStakeResponse  res state =
  { state | stakeForm = state.stakeForm |> StakeForm.handleStakeResponse res }
handleCreateInvitationResponse : Pb.AuthToken -> Result Http.Error Pb.CreateInvitationResponse -> State -> State
handleCreateInvitationResponse auth res state =
  { state | invitationWidget = state.invitationWidget |> SmallInvitationWidget.handleCreateInvitationResponse auth res }
handleResolveResponse : Result Http.Error Pb.ResolveResponse -> State -> State
handleResolveResponse res state =
  case res of
    Err e ->
      { state | working = False , notification = Utils.redText (Debug.toString e) }
    Ok resp ->
      case resp.resolveResult of
        Just (Pb.ResolveResultOk _) ->
          { state | working = False
                  , notification = H.text ""
          }
        Just (Pb.ResolveResultError e) ->
          { state | working = False , notification = Utils.redText (Debug.toString e) }
        Nothing ->
          { state | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }

viewStakeFormOrExcuse : Context msg -> State -> Html msg
viewStakeFormOrExcuse ctx state =
  let creator = Utils.mustPredictionCreator ctx.prediction in
  if Utils.resolutionIsTerminal (Utils.currentResolution ctx.prediction) then
    H.text "This prediction has resolved, so cannot be bet in."
  else if Utils.secondsToClose ctx.now ctx.prediction <= 0 then
    H.text <| "This prediction closed on " ++ Utils.dateStr Time.utc (Utils.predictionClosesTime ctx.prediction) ++ " (UTC)."
  else case ctx.auth of
    Nothing ->
      H.div []
        [ H.text "You must be logged in to participate in this prediction!"
        ]
    Just _ ->
      if creator.isSelf then
        H.text ""
      else case (creator.trustsYou, creator.isTrusted) of
        (True, True) ->
          StakeForm.view (stakeFormConfig ctx state) state.stakeForm
        (False, False) ->
          H.div []
            [ H.text <| "You and " ++ creator.displayName ++ " don't trust each other! If, in real life, you "
            , H.i [] [H.text "do"]
            , H.text " trust each other to pay your debts, send them an invitation! "
            , SmallInvitationWidget.view (invitationWidgetCtx ctx state) state.invitationWidget
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
            , SmallInvitationWidget.view (invitationWidgetCtx ctx state) state.invitationWidget
            ]

creatorWinningsByBettor : Bool -> List Pb.Trade -> Dict String Int -- TODO: avoid key serialization collisions
creatorWinningsByBettor resolvedYes trades =
  trades
  |> List.foldl (\t d -> D.update (Utils.renderUserPlain <| Utils.mustTradeBettor t) (Maybe.withDefault 0 >> ((+) (if xor resolvedYes t.bettorIsASkeptic then -t.creatorStakeCents else t.bettorStakeCents)) >> Just) d) D.empty

stateWinnings : String -> Int -> String
stateWinnings counterparty win =
  (if win > 0 then counterparty ++ " owes you" else "You owe " ++ counterparty) ++ " " ++ Utils.formatCents (abs win) ++ "."

enumerateWinnings : Dict String Int -> Html msg
enumerateWinnings winningsByUser =
  H.ul [] <| (
    winningsByUser
    |> D.toList
    |> List.sortBy (\(b, _) -> b)
    |> List.map (\(b, win) -> H.li [] [H.text <| stateWinnings b win])
    )

viewPredictionState : Context msg -> State -> Html msg
viewPredictionState ctx state =
  let
    auditLog : Html msg
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
          nowUnixtime = Time.posixToMillis ctx.now // 1000
          secondsToClose = ctx.prediction.closesUnixtime - nowUnixtime
          secondsToResolve = ctx.prediction.resolvesAtUnixtime - nowUnixtime
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

viewWinnings : Context msg -> State -> Html msg
viewWinnings ctx state =
  let
    auditLog : Html msg
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
    ifRes : Bool -> Html msg
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

viewCreationParams : Context msg -> State -> Html msg
viewCreationParams ctx state =
  let
    creator = Utils.mustPredictionCreator ctx.prediction
    openTime = ctx.prediction.createdUnixtime |> (*) 1000 |> Time.millisToPosix
    certainty = Utils.mustPredictionCertainty ctx.prediction
  in
  H.p []
    [ H.text <| "On " ++ Utils.dateStr Time.utc openTime ++ " UTC, "
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

viewResolveButtons : Context msg -> State -> Html msg
viewResolveButtons ctx state =
  if (Utils.mustPredictionCreator ctx.prediction).isSelf then
    H.div []
      [ let
          mistakeDetails =
            H.details [HA.style "color" "gray"]
              [ H.summary [] [H.text "Mistake?"]
              , H.text "If you resolved this prediction incorrectly, you can "
              , H.button [HE.onClick <| ctx.handle (Just <| Resolve Pb.ResolutionNoneYet) { state | working = True , notification = H.text "" }] [H.text "un-resolve it."]
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
              [ H.button [HE.onClick <| ctx.handle (Just <| Resolve Pb.ResolutionYes    ) { state | working = True , notification = H.text "" }] [H.text "Resolve YES"]
              , H.button [HE.onClick <| ctx.handle (Just <| Resolve Pb.ResolutionNo     ) { state | working = True , notification = H.text "" }] [H.text "Resolve NO"]
              , H.button [HE.onClick <| ctx.handle (Just <| Resolve Pb.ResolutionInvalid) { state | working = True , notification = H.text "" }] [H.text "Resolve INVALID"]
              ]
          Pb.ResolutionUnrecognized_ _ -> Debug.todo "unrecognized resolution"
      , state.notification |> H.map (\_ -> ctx.handle Nothing state)
      ]
  else
    H.text ""

view : Context msg -> State -> Html msg
view ctx state =
  let
    creator = Utils.mustPredictionCreator ctx.prediction
  in
  H.div []
    [ H.h2 [] [H.text <| "Prediction: by " ++ (String.left 10 <| Iso8601.fromTime <| Time.millisToPosix <| ctx.prediction.resolvesAtUnixtime * 1000) ++ ", " ++ ctx.prediction.prediction]
    , viewPredictionState ctx state
    , viewResolveButtons ctx state
    , viewWinnings ctx state
    , H.hr [] []
    , viewCreationParams ctx state
    , case ctx.prediction.specialRules of
        "" ->
          H.text ""
        rules ->
          H.div []
            [ H.strong [] [H.text "Special rules:"]
            , H.text <| " " ++ rules
            ]
    , H.hr [] []
    , viewStakeFormOrExcuse ctx state
    , if creator.isSelf then
        H.div []
          [ H.text "If you want to link to your prediction, here are some snippets of HTML you could copy-paste:"
          , viewEmbedInfo ctx state
          , H.text "If there are people you want to participate, but you haven't already established trust with them in Biatob, send them invitations: "
          , SmallInvitationWidget.view (invitationWidgetCtx ctx state) state.invitationWidget
          ]
      else
        H.text ""
    ]

viewEmbedInfo : Context msg -> State -> Html msg
viewEmbedInfo ctx state =
  let
    linkUrl = ctx.httpOrigin ++ "/p/" ++ String.fromInt ctx.predictionId  -- TODO(P0): needs origin to get stuck in text field
    imgUrl = ctx.httpOrigin ++ "/p/" ++ String.fromInt ctx.predictionId ++ "/embed.png"
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
        , CopyWidget.view (\s -> ctx.handle (Just <| Copy s) state) imgCode
        , H.br [] []
        , H.text "This would render as: "
        , H.a [HA.href linkUrl]
          [ H.img (HA.src imgUrl :: (imgStyles |> List.map (\(k,v) -> HA.style k v))) []]
        ]
      , H.li [] <|
        [ H.text "A boring old link: "
        , CopyWidget.view (\s -> ctx.handle (Just <| Copy s) state) linkCode
        , H.br [] []
        , H.text "This would render as: "
        , H.a [HA.href linkUrl] [H.text linkText]
        ]
      ]

stakeFormConfig : Context msg -> State -> StakeForm.Config msg
stakeFormConfig ctx state =
  { disableCommit = (ctx.auth == Nothing || (Utils.mustPredictionCreator ctx.prediction).isSelf)
  , prediction = ctx.prediction
  , handle = \e newForm ->
      let
        event = case e of
          Just (StakeForm.Staked x) -> Just <| Staked x
          Nothing -> Nothing
      in
      ctx.handle event { state | stakeForm = newForm }
  }
