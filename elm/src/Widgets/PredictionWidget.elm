module Widgets.PredictionWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Time
import Dict as D exposing (Dict)

import Iso8601
import Biatob.Proto.Mvp as Pb
import Utils exposing (Cents, PredictionId, Username)

import Widgets.StakeWidget as StakeWidget
import Widgets.CopyWidget as CopyWidget
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Page

type Msg
  = SetInvitationWidget SmallInvitationWidget.State
  | CreateInvitation SmallInvitationWidget.State Pb.CreateInvitationRequest
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)
  | SetStakeWidget StakeWidget.State
  | Stake StakeWidget.State Pb.StakeRequest
  | StakeFinished (Result Http.Error Pb.StakeResponse)
  | Copy String
  | Resolve Pb.Resolution
  | ResolveFinished (Result Http.Error Pb.ResolveResponse)
type alias Model =
  { stakeWidget : StakeWidget.State
  , working : Bool
  , notification : Html Never
  , invitationWidget : SmallInvitationWidget.State
  , linkTitle : Bool
  , predictionId : PredictionId
  }

init : PredictionId -> Model
init predictionId =
  { stakeWidget = StakeWidget.init predictionId
  , working = False
  , notification = H.text ""
  , invitationWidget = SmallInvitationWidget.init
  , linkTitle = False
  , predictionId = predictionId
  }
setLinkTitle : Bool -> Model -> Model
setLinkTitle linkTitle model =
  { model | linkTitle = linkTitle }

update : Msg -> Model -> ( Model , Page.Command Msg )
update msg model =
  case msg of
    SetInvitationWidget widgetState ->
      ( { model | invitationWidget = widgetState } , Page.NoCmd )
    CreateInvitation widgetState req ->
      ( { model | invitationWidget = widgetState }
      , Page.RequestCmd <| Page.CreateInvitationRequest CreateInvitationFinished req
      )
    CreateInvitationFinished res ->
      ( { model | invitationWidget = model.invitationWidget |> SmallInvitationWidget.handleCreateInvitationResponse res }
      , Page.NoCmd
      )
    Copy s ->
      ( model
      , Page.CopyCmd s
      )

    SetStakeWidget widgetState ->
      ( { model | stakeWidget = widgetState } , Page.NoCmd )
    Stake widgetState req ->
      ( { model | stakeWidget = widgetState }
      , Page.RequestCmd <| Page.StakeRequest StakeFinished req
      )
    StakeFinished res ->
      ( { model | stakeWidget = model.stakeWidget |> StakeWidget.handleStakeResponse res }
      , Page.NoCmd
      )

    Resolve resolution ->
      ( { model | working = True , notification = H.text "" }
      , Page.RequestCmd <| Page.ResolveRequest ResolveFinished {predictionId=model.predictionId, resolution=resolution, notes=""}
      )
    ResolveFinished res ->
      case res of
        Err e ->
          ( { model | working = False , notification = Utils.redText (Debug.toString e) } , Page.NoCmd )
        Ok resp ->
          case resp.resolveResult of
            Just (Pb.ResolveResultOk _) ->
              ( { model | working = False , notification = H.text "" } , Page.NoCmd )
            Just (Pb.ResolveResultError e) ->
              ( { model | working = False , notification = Utils.redText (Debug.toString e) } , Page.NoCmd )
            Nothing ->
              ( { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" } , Page.NoCmd )

viewStakeWidgetOrExcuse : Page.Globals -> Model -> Html Msg
viewStakeWidgetOrExcuse globals model =
  let
    prediction = mustHaveLoadedPrediction model.predictionId globals
    creator = prediction.creator
  in
  if Utils.resolutionIsTerminal (Utils.currentResolution prediction) then
    H.text "This prediction has resolved, so cannot be bet in."
  else if prediction.closesUnixtime < Utils.timeToUnixtime globals.now then
    H.text <| "This prediction closed on " ++ Utils.dateStr globals.timeZone (Utils.predictionClosesTime prediction) ++ "."
  else if not (Page.isLoggedIn globals) then
    H.div []
      [ H.text "You must be logged in to bet on this prediction!"
      ]
  else
    if Page.isSelf globals creator then
      H.text ""
    else case Page.getRelationship globals creator |> Maybe.map (\r -> (r.trusting, r.trusted)) |> Maybe.withDefault (False, False) of
      (True, True) ->
        StakeWidget.view
          { setState = SetStakeWidget
          , stake = Stake
          , predictionId = model.predictionId
          , prediction = Utils.must "TODO" <| D.get model.predictionId globals.serverState.predictions
          , now = globals.now
          }
          model.stakeWidget
      (False, False) ->
        H.div []
          [ H.text "You and "
          , Utils.renderUser creator
          , H.text " don't trust each other! If, in real life, you "
          , Utils.i "do"
          , H.text " trust each other to pay your debts, send them an invitation! "
          , viewInvitationWidget globals model
          ]
      (True, False) ->
        H.div []
          [ H.text "You don't trust "
          , Utils.renderUser creator
          , H.text "."
          ]
      (False, True) ->
        H.div []
          [ Utils.renderUser creator, H.text " hasn't marked you as trusted! If you think that, in real life, they "
          , Utils.i "do"
          , H.text " trust you to pay your debts, send them an invitation link: "
          , viewInvitationWidget globals model
          ]

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

enumerateWinnings : Dict Username Cents -> Html Msg
enumerateWinnings winningsByUser =
  H.ul [] <| (
    winningsByUser
    |> D.toList
    |> List.sortBy (\(b, _) -> b)
    |> List.map (\(b, win) -> H.li [] [stateWinnings b win])
    )

mustHaveLoadedPrediction : PredictionId -> Page.Globals -> Pb.UserPredictionView
mustHaveLoadedPrediction predictionId globals =
  Utils.must "prediction is not loaded in ServerState" <| D.get predictionId globals.serverState.predictions

viewPredictionState : Page.Globals -> Model -> Html Msg
viewPredictionState globals model =
  let
    prediction = mustHaveLoadedPrediction model.predictionId globals
    auditLog : Html Msg
    auditLog =
      if List.isEmpty prediction.resolutions then H.text "" else
      H.details [HA.style "opacity" "50%"]
        [ H.summary [] [H.text "Details"]
        , prediction.resolutions
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
    [ case Utils.currentResolution prediction of
      Pb.ResolutionYes ->
        H.text "This prediction has resolved YES. "
      Pb.ResolutionNo ->
        H.text "This prediction has resolved NO. "
      Pb.ResolutionInvalid ->
        H.text "This prediction has resolved INVALID. "
      Pb.ResolutionNoneYet ->
        let
          secondsToClose = prediction.closesUnixtime - Utils.timeToUnixtime globals.now
          secondsToResolve = prediction.resolvesAtUnixtime - Utils.timeToUnixtime globals.now
        in
          H.text <|
            ( if secondsToClose > 0 then
                "Betting closes " ++ (
                  if secondsToClose < 86400 then
                    "in " ++ Utils.renderIntervalSeconds secondsToClose
                  else
                    "on " ++ Utils.dateStr globals.timeZone (Utils.unixtimeToTime prediction.closesUnixtime)
                ) ++ ", and "
              else
                "Betting closed on" ++ Utils.dateStr globals.timeZone (Utils.unixtimeToTime prediction.closesUnixtime) ++ ", and "
            ) ++
            ( if secondsToResolve > 0 then
                "the prediction should resolve " ++ (
                  if secondsToResolve < 86400 then
                    "in " ++ Utils.renderIntervalSeconds secondsToResolve
                  else
                    "on " ++ Utils.dateStr globals.timeZone (Utils.unixtimeToTime prediction.resolvesAtUnixtime)
                ) ++ ". "
              else
                "the prediction should have resolved on " ++ Utils.dateStr globals.timeZone (Utils.unixtimeToTime prediction.resolvesAtUnixtime) ++ ". Consider pinging the creator! "
            )
      Pb.ResolutionUnrecognized_ _ ->
        H.span [HA.style "color" "red"]
          [H.text "Oh dear, something has gone very strange with this prediction. Please email TODO with this URL to report it!"]
    , auditLog
    ]

viewWinnings : Page.Globals -> Model -> Html Msg
viewWinnings globals model =
  let
    prediction = mustHaveLoadedPrediction model.predictionId globals
    auditLog : Html Msg
    auditLog =
      if List.isEmpty prediction.yourTrades then H.text "" else
      H.details [HA.style "opacity" "50%"]
        [ H.summary [] [H.text "Details"]
        , prediction.yourTrades
          |> List.map (\t -> H.li [] [ H.text <| "[" ++ Utils.isoStr Time.utc (Utils.unixtimeToTime t.transactedUnixtime) ++ " UTC] "
                                     , Utils.renderUser t.bettor
                                     , H.text <| " bet " ++ (if t.bettorIsASkeptic then "NO" else "YES") ++ " staking " ++ Utils.formatCents t.bettorStakeCents ++ " against " ++ Utils.formatCents t.creatorStakeCents])
          |> H.ul []
        ]
    ifRes : Bool -> Html Msg
    ifRes res =
      creatorWinningsByBettor res prediction.yourTrades
        |>  if Page.isSelf globals prediction.creator then
              enumerateWinnings
            else
              (D.values >> List.sum >> (\n -> -n) >> stateWinnings prediction.creator)
  in
  if List.isEmpty prediction.yourTrades then H.text "" else
  H.div []
    [ case Utils.currentResolution prediction of
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

viewCreationParams : Page.Globals -> Model -> Html Msg
viewCreationParams globals model =
  let
    prediction = mustHaveLoadedPrediction model.predictionId globals
    creator = prediction.creator
    openTime = Utils.unixtimeToTime prediction.createdUnixtime
    certainty = Utils.mustPredictionCertainty prediction
  in
  H.p []
    [ H.text <| "On " ++ Utils.dateStr globals.timeZone openTime ++ ", "
    , if Page.isSelf globals creator then Utils.b "you" else Utils.renderUser creator
    , H.text " assigned this a "
    , certainty.low |> (*) 100 |> round |> String.fromInt |> H.text
    , H.text "-"
    , certainty.high |> (*) 100 |> round |> String.fromInt |> H.text
    , H.text "% chance, and staked "
    , prediction.maximumStakeCents |> Utils.formatCents |> H.text
    , case (prediction.maximumStakeCents - prediction.remainingStakeCentsVsSkeptics, prediction.maximumStakeCents - prediction.remainingStakeCentsVsBelievers) of
        (0, 0) -> H.text ""
        (promisedToSkeptics, 0) -> H.span [HA.style "opacity" "50%"] [H.text <| " (though they've already promised away " ++ Utils.formatCents promisedToSkeptics ++ " if this doesn't happen)"]
        (0, promisedToBelievers) -> H.span [HA.style "opacity" "50%"] [H.text <| " (though they've already promised away " ++ Utils.formatCents promisedToBelievers ++ " if this happens)"]
        (promisedToSkeptics, promisedToBelievers) -> H.span [HA.style "opacity" "50%"] [H.text <| " (though they've already promised away " ++ Utils.formatCents promisedToSkeptics ++ " if this doesn't happen, and " ++ Utils.formatCents promisedToBelievers ++ " if it does)"]
    , H.text "."
    ]

viewResolveButtons : Page.Globals -> Model -> Html Msg
viewResolveButtons globals model =
  let
    prediction = mustHaveLoadedPrediction model.predictionId globals
  in
  if Page.isSelf globals prediction.creator then
    H.div []
      [ let
          mistakeDetails =
            H.details [HA.style "color" "gray"]
              [ H.summary [] [H.text "Mistake?"]
              , H.text "If you resolved this prediction incorrectly, you can "
              , H.button [HE.onClick (Resolve Pb.ResolutionNoneYet)] [H.text "un-resolve it."]
              ]
        in
        case Utils.currentResolution prediction of
          Pb.ResolutionYes ->
            mistakeDetails
          Pb.ResolutionNo ->
            mistakeDetails
          Pb.ResolutionInvalid ->
            mistakeDetails
          Pb.ResolutionNoneYet ->
            H.div []
              [ H.button [HE.onClick (Resolve Pb.ResolutionYes    )] [H.text "Resolve YES"]
              , H.button [HE.onClick (Resolve Pb.ResolutionNo     )] [H.text "Resolve NO"]
              , H.button [HE.onClick (Resolve Pb.ResolutionInvalid)] [H.text "Resolve INVALID"]
              ]
          Pb.ResolutionUnrecognized_ _ -> Debug.todo "unrecognized resolution"
      , model.notification |> H.map never
      ]
  else
    H.text ""

view : Page.Globals -> Model -> Html Msg
view globals model =
  let
    prediction = mustHaveLoadedPrediction model.predictionId globals
    creator = prediction.creator
  in
  H.div []
    [ H.h2 [] [
        let text = H.text <| "Prediction: by " ++ (String.left 10 <| Iso8601.fromTime <| Utils.unixtimeToTime prediction.resolvesAtUnixtime) ++ ", " ++ prediction.prediction in
        if model.linkTitle then
          H.a [HA.href <| "/p/" ++ String.fromInt model.predictionId] [text]
        else
          text
        ]
    , viewPredictionState globals model
    , viewResolveButtons globals model
    , viewWinnings globals model
    , H.hr [] []
    , viewCreationParams globals model
    , case prediction.specialRules of
        "" ->
          H.text ""
        rules ->
          H.div []
            [ Utils.b "Special rules:"
            , H.text <| " " ++ rules
            ]
    , H.hr [] []
    , viewStakeWidgetOrExcuse globals model
    , if Page.isLoggedIn globals then
        H.text ""
      else
        H.div []
          [ H.hr [HA.style "margin" "4em 0"] []
          , H.h3 [] [H.text "Huh? What is this?"]
          , H.p []
              [ H.text "This site is a tool that helps people make friendly wagers, thereby clarifying and concretizing their beliefs and making the world a better, saner place."
              ]
          , H.p []
              [ Utils.renderUser creator
              , H.text <| " is putting their money where their mouth is: they've staked " ++ Utils.formatCents prediction.maximumStakeCents ++ " of real-life money on this prediction,"
                  ++ " and they're willing to bet at the above odds against anybody they trust. Good for them!"
              ]
          , H.p []
              [ H.text "If you know and trust ", Utils.renderUser creator
              , H.text <| ", and they know and trust you, and you want to bet against them on this prediction,"
                  ++ " then message them however you normally do, and ask them for an invitation to this market!"
              ]
          , H.hr [] []
          , H.h3 [] [H.text "But... why would you do this?"]
          , H.p []
              [ H.text "Personally, when I force myself to make concrete predictions -- especially on topics I feel strongly about -- it frequently turns out that "
              , Utils.i "I don't actually believe what I thought I did."
              , H.text " Crazy, right!? Brains suck! And betting, i.e. attaching money to my predictions, is "
              , H.a [HA.href "https://marginalrevolution.com/marginalrevolution/2012/11/a-bet-is-a-tax-on-bullshit.html"]
                  [ H.text "an incentive to actually try to get them right"
                  ]
              , H.text ": it forces my brain to cut through (some of) the layers of "
              , H.a [HA.href "https://en.wikipedia.org/wiki/Social-desirability_bias"]
                  [ H.text "social-desirability bias"
                  ]
              , H.text " and "
              , H.a [HA.href "https://www.lesswrong.com/posts/DSnamjnW7Ad8vEEKd/trivers-on-self-deception"]
                  [ H.text "Triversian self-deception"
                  ]
              , H.text " to lay bare "
              , H.a [HA.href "https://www.lesswrong.com/posts/a7n8GdKiAZRX86T5A/making-beliefs-pay-rent-in-anticipated-experiences"]
                  [ H.text "my actual beliefs about what I expect to see"
                  ]
              , H.text "."
              ]
          , H.p [] [H.text "I made this tool to share that joy with you."]
          ]
    , if Page.isSelf globals creator then
        H.div []
          [ H.text "If you want to link to your prediction, here are some snippets of HTML you could copy-paste:"
          , viewEmbedInfo globals model
          , H.text "If there are people you want to participate, but you haven't already established trust with them in Biatob, send them invitations: "
          , viewInvitationWidget globals model
          ]
      else
        H.text ""
    ]

viewEmbedInfo : Page.Globals -> Model -> Html Msg
viewEmbedInfo globals model =
  let
    prediction = mustHaveLoadedPrediction model.predictionId globals
    linkUrl = globals.httpOrigin ++ "/p/" ++ String.fromInt model.predictionId  -- TODO(P0): needs origin to get stuck in text field
    imgUrl = globals.httpOrigin ++ "/p/" ++ String.fromInt model.predictionId ++ "/embed.png"
    imgStyles = [("max-height","1.5ex"), ("border-bottom","1px solid #008800")]
    imgCode =
      "<a href=\"" ++ linkUrl ++ "\">"
      ++ "<img style=\"" ++ (imgStyles |> List.map (\(k,v) -> k++":"++v) |> String.join ";") ++ "\" src=\"" ++ imgUrl ++ "\" /></a>"
    linkText =
      "["
      ++ Utils.formatCents (prediction.maximumStakeCents // 100 * 100)
      ++ " @ "
      ++ String.fromInt (round <| (Utils.mustPredictionCertainty prediction).low * 100)
      ++ "-"
      ++ String.fromInt (round <| (Utils.mustPredictionCertainty prediction).high * 100)
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

viewInvitationWidget : Page.Globals -> Model -> Html Msg
viewInvitationWidget globals model =
  SmallInvitationWidget.view
    { setState = SetInvitationWidget
    , createInvitation = CreateInvitation
    , copy = Copy
    , destination = Just <| "/p/" ++ String.fromInt model.predictionId
    , httpOrigin = globals.httpOrigin
    }
    model.invitationWidget

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
