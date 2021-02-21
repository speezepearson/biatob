port module ViewPredictionPage exposing (..)

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
import Task
import CopyWidget
import SmallInvitationWidget
import API
import SmallInvitationWidget exposing (Event(..))

port changed : () -> Cmd msg

type Event
  = Nevermind
  | CreateInvitation
  | Copy String
  | Staked {bettorIsASkeptic:Bool, bettorStakeCents:Int}
  | Resolve Pb.Resolution
type alias Context msg =
  { auth : Maybe Pb.AuthToken
  , prediction : Pb.UserPredictionView
  , predictionId : Int
  , now : Time.Posix
  , linkToAuthority : String
  , handle : Event -> Model -> msg
  }
type alias Model =
  { stakeForm : StakeForm.State
  , working : Bool
  , notification : Html ()
  , invitationWidget : SmallInvitationWidget.Model
  }

invitationWidgetCtx : Context msg -> Model -> SmallInvitationWidget.Context msg
invitationWidgetCtx ctx model =
  { httpOrigin = ctx.linkToAuthority
  , destination = Just <| "/p/" ++ String.fromInt ctx.predictionId
  , handle = \e m ->
      let
        event = case e of
          SmallInvitationWidget.Nevermind -> Nevermind
          SmallInvitationWidget.Copy s -> Copy s
          SmallInvitationWidget.CreateInvitation -> CreateInvitation
      in
      ctx.handle event { model | invitationWidget = m }
  }

init : Model
init =
  { stakeForm = StakeForm.init
  , working = False
  , notification = H.text ""
  , invitationWidget = SmallInvitationWidget.init
  }

handleStakeResponse : Result Http.Error Pb.StakeResponse -> Model -> Model
handleStakeResponse  res model =
  { model | stakeForm = model.stakeForm |> StakeForm.handleStakeResponse res }
handleCreateInvitationResponse : Pb.AuthToken -> Result Http.Error Pb.CreateInvitationResponse -> Model -> Model
handleCreateInvitationResponse auth res model =
  { model | invitationWidget = model.invitationWidget |> SmallInvitationWidget.handleCreateInvitationResponse auth res }
handleResolveResponse : Result Http.Error Pb.ResolveResponse -> Model -> Model
handleResolveResponse res model =
  case res of
    Err e ->
      { model | working = False , notification = Utils.redText (Debug.toString e) }
    Ok resp ->
      case resp.resolveResult of
        Just (Pb.ResolveResultOk _) ->
          { model | working = False
                  , notification = H.text ""
          }
        Just (Pb.ResolveResultError e) ->
          { model | working = False , notification = Utils.redText (Debug.toString e) }
        Nothing ->
          { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }

viewStakeFormOrExcuse : Context msg -> Model -> Html msg
viewStakeFormOrExcuse ctx model =
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
          StakeForm.view (stakeFormConfig ctx model) model.stakeForm
        (False, False) ->
          H.div []
            [ H.text <| "You and " ++ creator.displayName ++ " don't trust each other! If, in real life, you "
            , H.i [] [H.text "do"]
            , H.text " trust each other to pay your debts, send them an invitation! "
            , SmallInvitationWidget.view (invitationWidgetCtx ctx model) model.invitationWidget
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
            , SmallInvitationWidget.view (invitationWidgetCtx ctx model) model.invitationWidget
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

viewPredictionState : Context msg -> Model -> Html msg
viewPredictionState ctx model =
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

viewWinnings : Context msg -> Model -> Html msg
viewWinnings ctx model =
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

viewCreationParams : Context msg -> Model -> Html msg
viewCreationParams ctx model =
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

viewResolveButtons : Context msg -> Model -> Html msg
viewResolveButtons ctx model =
  if (Utils.mustPredictionCreator ctx.prediction).isSelf then
    H.div []
      [ let
          mistakeDetails =
            H.details [HA.style "color" "gray"]
              [ H.summary [] [H.text "Mistake?"]
              , H.text "If you resolved this prediction incorrectly, you can "
              , H.button [HE.onClick <| ctx.handle (Resolve Pb.ResolutionNoneYet) { model | working = True , notification = H.text "" }] [H.text "un-resolve it."]
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
              [ H.button [HE.onClick <| ctx.handle (Resolve Pb.ResolutionYes    ) { model | working = True , notification = H.text "" }] [H.text "Resolve YES"]
              , H.button [HE.onClick <| ctx.handle (Resolve Pb.ResolutionNo     ) { model | working = True , notification = H.text "" }] [H.text "Resolve NO"]
              , H.button [HE.onClick <| ctx.handle (Resolve Pb.ResolutionInvalid) { model | working = True , notification = H.text "" }] [H.text "Resolve INVALID"]
              ]
          Pb.ResolutionUnrecognized_ _ -> Debug.todo "unrecognized resolution"
      , model.notification |> H.map (\_ -> ctx.handle Nevermind model)
      ]
  else
    H.text ""

view : Context msg -> Model -> Html msg
view ctx model =
  let
    creator = Utils.mustPredictionCreator ctx.prediction
  in
  H.div []
    [ H.h2 [] [H.text <| "Prediction: by " ++ (String.left 10 <| Iso8601.fromTime <| Time.millisToPosix <| ctx.prediction.resolvesAtUnixtime * 1000) ++ ", " ++ ctx.prediction.prediction]
    , viewPredictionState ctx model
    , viewResolveButtons ctx model
    , viewWinnings ctx model
    , H.hr [] []
    , viewCreationParams ctx model
    , case ctx.prediction.specialRules of
        "" ->
          H.text ""
        rules ->
          H.div []
            [ H.strong [] [H.text "Special rules:"]
            , H.text <| " " ++ rules
            ]
    , H.hr [] []
    , viewStakeFormOrExcuse ctx model
    , if creator.isSelf then
        H.div []
          [ H.text "If you want to link to your prediction, here are some snippets of HTML you could copy-paste:"
          , viewEmbedInfo ctx model
          , H.text "If there are people you want to participate, but you haven't already established trust with them in Biatob, send them invitations: "
          , SmallInvitationWidget.view (invitationWidgetCtx ctx model) model.invitationWidget
          ]
      else
        H.text ""
    ]

viewEmbedInfo : Context msg -> Model -> Html msg
viewEmbedInfo ctx model =
  let
    linkUrl = ctx.linkToAuthority ++ "/p/" ++ String.fromInt ctx.predictionId  -- TODO(P0): needs origin to get stuck in text field
    imgUrl = ctx.linkToAuthority ++ "/p/" ++ String.fromInt ctx.predictionId ++ "/embed.png"
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
        , CopyWidget.view (\s -> ctx.handle (Copy s) model) imgCode
        , H.br [] []
        , H.text "This would render as: "
        , H.a [HA.href linkUrl]
          [ H.img (HA.src imgUrl :: (imgStyles |> List.map (\(k,v) -> HA.style k v))) []]
        ]
      , H.li [] <|
        [ H.text "A boring old link: "
        , CopyWidget.view (\s -> ctx.handle (Copy s) model) linkCode
        , H.br [] []
        , H.text "This would render as: "
        , H.a [HA.href linkUrl] [H.text linkText]
        ]
      ]

stakeFormConfig : Context msg -> Model -> StakeForm.Config msg
stakeFormConfig ctx model =
  { disableCommit = (ctx.auth == Nothing || (Utils.mustPredictionCreator ctx.prediction).isSelf)
  , prediction = ctx.prediction
  , handle = \e newForm ->
      let
        event = case e of
          StakeForm.Staked x -> Staked x
          StakeForm.Nevermind -> Nevermind
      in
      ctx.handle event { model | stakeForm = newForm }
  }

type alias PageModel = (Context PageMsg, Model)
type PageMsg
  = PageEvent Event Model
  | Tick Time.Posix
  | StakeFinished (Result Http.Error Pb.StakeResponse)
  | ResolveFinished (Result Http.Error Pb.ResolveResponse)
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)

main : Program JD.Value PageModel PageMsg
main =
  let
    init_ : JD.Value -> (PageModel, Cmd PageMsg)
    init_ flags =
      ( ( { prediction = Utils.mustDecodePbFromFlags Pb.userPredictionViewDecoder "predictionPbB64" flags
          , predictionId = Utils.mustDecodeFromFlags JD.int "predictionId" flags
          , auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
          , now = Time.millisToPosix 0
          , linkToAuthority = Utils.mustDecodeFromFlags JD.string "linkToAuthority" flags
          , handle = PageEvent
          }
        , init
        )
      , Task.perform Tick Time.now
      )

    update_ : PageMsg -> PageModel -> (PageModel, Cmd PageMsg)
    update_ msg (ctx, model) =
      case msg of
        PageEvent event newState ->
          let
            cmd = case event of
              Nevermind -> Cmd.none
              Copy s -> CopyWidget.copy s
              CreateInvitation -> API.postCreateInvitation CreateInvitationFinished {notes=""}
              Staked {bettorIsASkeptic, bettorStakeCents} -> API.postStake StakeFinished {predictionId=ctx.predictionId, bettorIsASkeptic=bettorIsASkeptic, bettorStakeCents=bettorStakeCents}
              Resolve resolution -> API.postResolve ResolveFinished {predictionId=ctx.predictionId, resolution=resolution, notes = ""}
          in
            ((ctx, newState), cmd)
        Tick now -> (({ctx | now = now}, model), Cmd.none)
        CreateInvitationFinished res ->
          ( ( ctx
            , model |> handleCreateInvitationResponse (ctx.auth |> Utils.must "TODO") res
            )
          , Cmd.none
          )
        StakeFinished res ->
          ( ( { ctx | prediction = case res |> Result.toMaybe |> Maybe.andThen .stakeResult of
                        Just (Pb.StakeResultOk pred) -> pred
                        _ -> ctx.prediction
              }
            , model |> handleStakeResponse res
            )
          , Cmd.none
          )
        ResolveFinished res ->
          ( ( { ctx | prediction = case res |> Result.toMaybe |> Maybe.andThen .resolveResult of
                        Just (Pb.ResolveResultOk pred) -> pred
                        _ -> ctx.prediction
              }
            , model |> handleResolveResponse res
            )
          , Cmd.none
          )

  in
  Browser.element
    { init = init_
    , subscriptions = \_ -> Time.every 1000 Tick
    , view = \(ctx, model) -> view ctx model
    , update = update_
    }
