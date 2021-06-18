port module Elements.Prediction exposing (main, viewBodyMockup)

import Browser
import Dict exposing (Dict)
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as JD
import Http

import Utils

import Widgets.CopyWidget as CopyWidget
import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Globals
import API
import Biatob.Proto.Mvp as Pb
import Utils exposing (Cents, PredictionId, Username)
import Time

epsilon : Float
epsilon = 0.0000001 -- 🎵 I hate floating-point arithmetic 🎶

port copy : String -> Cmd msg
port navigate : Maybe String -> Cmd msg
port authWidgetExternallyChanged : (AuthWidget.DomModification -> msg) -> Sub msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , predictionId : PredictionId
  , invitationWidget : SmallInvitationWidget.State
  , resolveStatus : ResolveRequestStatus
  , stakeField : String
  , bettorIsASkeptic : Bool
  , stakeStatus : StakeRequestStatus
  }

type ResolveRequestStatus = ResolveUnstarted | ResolveAwaitingResponse | ResolveSucceeded | ResolveFailed String
type StakeRequestStatus = StakeUnstarted | StakeAwaitingResponse | StakeSucceeded | StakeFailed String

type Msg
  = SetAuthWidget AuthWidget.State
  | SetInvitationWidget SmallInvitationWidget.State
  | CreateInvitation SmallInvitationWidget.State Pb.CreateInvitationRequest
  | CreateInvitationFinished Pb.CreateInvitationRequest (Result Http.Error Pb.CreateInvitationResponse)
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | Resolve Pb.Resolution
  | ResolveFinished Pb.ResolveRequest (Result Http.Error Pb.ResolveResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | Stake Cents
  | StakeFinished Pb.StakeRequest (Result Http.Error Pb.StakeResponse)
  | SetBettorIsASkeptic Bool
  | SetStakeField String
  | Copy String
  | Tick Time.Posix
  | AuthWidgetExternallyModified AuthWidget.DomModification
  | Ignore

init : JD.Value -> ( Model, Cmd Msg )
init flags =
  ( { globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
    , navbarAuth = AuthWidget.init
    , predictionId = Utils.mustDecodeFromFlags JD.string "predictionId" flags
    , invitationWidget = SmallInvitationWidget.init
    , resolveStatus = ResolveUnstarted
    , stakeStatus = StakeUnstarted
    , stakeField = ""
    , bettorIsASkeptic = True
    }
  , Cmd.none
  )

mustPrediction : Model -> Pb.UserPredictionView
mustPrediction model =
  Utils.must "must have loaded prediction being viewed" <| Dict.get model.predictionId model.globals.serverState.predictions

view : Model -> Browser.Document Msg
view model =
  let
    prediction = mustPrediction model
  in
  { title = "Prediction: by " ++ Utils.dateStr model.globals.timeZone (Utils.unixtimeToTime prediction.resolvesAtUnixtime) ++ ", " ++ prediction.prediction
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
    , H.main_ [] (viewBody model)
    ]
  }

viewBodyMockup : Globals.Globals -> Pb.UserPredictionView -> Html ()
viewBodyMockup globals prediction =
  viewBody
    { globals = globals
        |> Globals.handleGetPredictionResponse {predictionId="12345"} (Ok {getPredictionResult=Just <| Pb.GetPredictionResultPrediction prediction})
        |> Globals.handleSignOutResponse {} (Ok {})
    , navbarAuth = AuthWidget.init
    , predictionId = "12345"
    , invitationWidget = SmallInvitationWidget.init
    , resolveStatus = ResolveUnstarted
    , stakeStatus = StakeUnstarted
    , stakeField = ""
    , bettorIsASkeptic = True
    }
  |> H.div []
  |> H.map (\_ -> ())

viewBody : Model -> List (Html Msg)
viewBody model =
  let
    prediction = mustPrediction model
    isOwnPrediction = Globals.isSelf model.globals prediction.creator
  in
  [ H.h2 [] [H.text <| getTitleText model.globals.timeZone prediction]
  , viewSummaryTable model.globals.now model.globals.timeZone prediction
  , if List.isEmpty prediction.yourTrades then
      H.text ""
    else
      H.div []
      [ H.hr [] []
      , Utils.b "Your existing stake: "
      , if isOwnPrediction then
          viewTradesAsCreator model.globals.timeZone prediction
        else
          viewTradesAsBettor model.globals.timeZone prediction
      ]
  , if isOwnPrediction then
      H.div []
      [ H.hr [] []
      , viewResolveButtons model
      , H.hr [HA.style "margin" "2em 0"] []
      , H.text "If you want to link to your prediction, here are some snippets of HTML you could copy-paste:"
      , viewEmbedInfo model
      , H.text "If there are people you want to participate, but you haven't already established trust with them in Biatob, send them invitations: "
      , viewInvitationWidget model
      ]
    else
      viewStakeWidgetOrExcuse model
  , if not (Globals.isLoggedIn model.globals) then
      H.div []
      [ H.hr [HA.style "margin" "2em 0"] []
      , viewWhatIsThis model.predictionId prediction
      ]
    else
      H.text ""
  ]

viewResolveButtons : Model -> Html Msg
viewResolveButtons model =
  let
    prediction = mustPrediction model
    mistakeInfo =
      H.span [HA.style "color" "gray"]
        [ H.text " Mistake? You can always "
        , H.button
          [ HA.disabled (model.resolveStatus == ResolveAwaitingResponse)
          , HE.onClick <| Resolve Pb.ResolutionNoneYet
          ]
          [ H.text "un-resolve it." ]
        ]
  in
    H.div []
    [ Utils.b "Resolve this prediction: "
    , case Utils.currentResolution prediction of
        Pb.ResolutionYes ->
          mistakeInfo
        Pb.ResolutionNo ->
          mistakeInfo
        Pb.ResolutionInvalid ->
          mistakeInfo
        Pb.ResolutionNoneYet ->
          H.span []
          [ H.button [HA.disabled (model.resolveStatus == ResolveAwaitingResponse), HE.onClick <| Resolve Pb.ResolutionYes    ] [H.text "Resolve YES"]
          , H.button [HA.disabled (model.resolveStatus == ResolveAwaitingResponse), HE.onClick <| Resolve Pb.ResolutionNo     ] [H.text "Resolve NO"]
          , H.button [HA.disabled (model.resolveStatus == ResolveAwaitingResponse), HE.onClick <| Resolve Pb.ResolutionInvalid] [H.text "Resolve INVALID"]
          ]
        Pb.ResolutionUnrecognized_ _ ->
          H.span []
          [ H.span [HA.style "color" "red"] [H.text "unrecognized resolution"]
          , mistakeInfo
          ]
    , H.text " "
    , case model.resolveStatus of
        ResolveUnstarted -> H.text ""
        ResolveAwaitingResponse -> H.text ""
        ResolveSucceeded -> Utils.greenText "Resolved!"
        ResolveFailed e -> Utils.redText e
    ]

viewWillWontDropdown : Model -> Html Msg
viewWillWontDropdown model =
  let certainty = mustPrediction model |> Utils.mustPredictionCertainty in
  if certainty.high == 1.0 then
    H.text "won't"
  else
    H.select
      [ HE.onInput (\s -> SetBettorIsASkeptic (case s of
          "won't" -> True
          "will" -> False
          _ -> Debug.todo <| "invalid value" ++ Debug.toString s ++ "for skepticism dropdown"
        ))
      ]
      [ H.option [HA.value "won't", HA.selected <| model.bettorIsASkeptic] [H.text "won't"]
      , H.option [HA.value "will", HA.selected <| not <| model.bettorIsASkeptic] [H.text "will"]
      ]

viewStakeWidgetOrExcuse : Model -> Html Msg
viewStakeWidgetOrExcuse model =
  let prediction = mustPrediction model in
  if Utils.resolutionIsTerminal (Utils.currentResolution prediction) then
    H.text "This prediction has resolved, so cannot be bet in."
  else if prediction.closesUnixtime < Utils.timeToUnixtime model.globals.now then
    H.text <| "This prediction closed on " ++ Utils.dateStr model.globals.timeZone (Utils.predictionClosesTime prediction) ++ "."
  else
    case Globals.getTrustRelationship model.globals prediction.creator of
      Globals.LoggedOut ->
        H.span []
          [ H.text "You'll need to "
          , H.a [HA.href <| "/login?dest=" ++ Utils.pathToPrediction model.predictionId] [H.text "log in"]
          , H.text " if you want to bet on this prediction!"
          ]
      Globals.Self ->
        H.text "(You can't bet on your own predictions.)"
      Globals.Friends ->
        viewStakeWidget BettingEnabled model
      Globals.NoRelation ->
        H.span []
          [ H.text "You can't bet on this prediction yet, because you and "
          , Utils.renderUser prediction.creator
          , H.text " haven't told me that you trust each other to pay up if you lose! If, in real life, you "
          , Utils.i "do"
          , H.text " trust each other to pay your debts, send them an invitation! "
          , viewInvitationWidget model
          ]
      Globals.TrustsCurrentUser ->
        H.span []
          [ H.text "You don't trust "
          , Utils.renderUser prediction.creator
          , H.text " to pay their debts, so you probably don't want to bet on this prediction. If you actually "
          , Utils.i "do"
          , H.text " trust them to pay their debts, send them an invitation link: "
          , viewInvitationWidget model
          ]
      Globals.TrustedByCurrentUser ->
        H.span []
          [ Utils.renderUser prediction.creator, H.text " hasn't told me that they trust you! If you think that, in real life, they "
          , Utils.i "do"
          , H.text " trust you to pay your debts, send them an invitation link: "
          , viewInvitationWidget model
          , H.br [] []
          , H.text "Once they accept it, I'll know you trust each other, and I'll let you bet against each other."
          ]

type Bettability = BettingEnabled | BettingDisabled
viewStakeWidget : Bettability -> Model -> Html Msg
viewStakeWidget bettability model =
  let
    prediction = mustPrediction model
    certainty = Utils.mustPredictionCertainty prediction

    disableInputs = case bettability of
      BettingEnabled -> False
      BettingDisabled -> True
    creatorStakeFactor =
      if model.bettorIsASkeptic then
        certainty.low / (1 - certainty.low)
      else
        (1 - certainty.high) / certainty.high
    remainingCreatorStake =
      if model.bettorIsASkeptic then
        prediction.remainingStakeCentsVsSkeptics
      else
        prediction.remainingStakeCentsVsBelievers
    maxBettorStakeCents =
      if creatorStakeFactor == 0 then
        0
      else
        toFloat remainingCreatorStake / creatorStakeFactor + 0.001 |> floor
    stakeCents = parseCents {max=maxBettorStakeCents} model.stakeField
  in
  H.span []
    [ H.text " Bet $"
    , H.input
        [ HA.style "width" "5em"
        , HA.type_"number", HA.min "0", HA.max (toFloat maxBettorStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
        , HA.disabled disableInputs
        , HE.onInput SetStakeField
        , HA.value model.stakeField
        ]
        []
      |> Utils.appendValidationError (Utils.resultToErr stakeCents)
    , H.text " that this "
    , viewWillWontDropdown model
    , H.text <| " happen, against " ++ prediction.creator ++ "'s "
    , Utils.b (stakeCents |> Result.map (toFloat >> (*) creatorStakeFactor >> round >> Utils.formatCents) |> Result.withDefault "???")
    , H.text " that it "
    , H.text <| if model.bettorIsASkeptic then "will" else "won't"
    , H.text ". "
    , H.button
        (case stakeCents of
          Ok cents ->
            [ HA.disabled disableInputs
            , HE.onClick (Stake cents)
            ]
          Err _ ->
            [ HA.disabled True ]
        )
        [H.text "Commit"]
    , case model.stakeStatus of
        StakeUnstarted -> H.text ""
        StakeAwaitingResponse -> H.text ""
        StakeSucceeded -> Utils.greenText "Success!"
        StakeFailed e -> Utils.redText e
    , if model.bettorIsASkeptic then
        if prediction.remainingStakeCentsVsSkeptics /= prediction.maximumStakeCents then
          H.div [HA.style "opacity" "50%"] [H.text <| "(only " ++ Utils.formatCents prediction.remainingStakeCentsVsSkeptics ++ " of ", Utils.renderUser prediction.creator, H.text <| "'s initial stake remains, since they've already accepted some bets)"]
        else
          H.text ""
      else
        if prediction.remainingStakeCentsVsBelievers /= prediction.maximumStakeCents then
          H.div [HA.style "opacity" "50%"] [H.text <| "(only " ++ Utils.formatCents prediction.remainingStakeCentsVsBelievers ++ " of ", Utils.renderUser prediction.creator, H.text <| "'s initial stake remains, since they've already accepted some bets)"]
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

getTitleText : Time.Zone -> Pb.UserPredictionView -> String
getTitleText timeZone prediction =
  "Prediction: by " ++ (Utils.dateStr timeZone <| Utils.unixtimeToTime prediction.resolvesAtUnixtime) ++ ", " ++ prediction.prediction


viewSummaryTable : Time.Posix -> Time.Zone -> Pb.UserPredictionView -> Html Msg
viewSummaryTable now timeZone prediction =
  H.table [HA.class "prediction-summary-table"]
  [ H.tr []
    [ H.td [] [Utils.b "Prediction by:"]
    , H.td [] [Utils.renderUser prediction.creator]
    ]
  , H.tr []
    [ H.td [] [Utils.b "Confidence:"]
    , H.td [] [H.text <|
        (String.fromInt <| round <| 100 * (Utils.mustPredictionCertainty prediction).low)
        ++ "-" ++
        (String.fromInt <| round <| 100 * (Utils.mustPredictionCertainty prediction).high)
        ++ "%"]
    ]
  , H.tr []
    [ H.td [] [Utils.b "Stakes:"]
    , H.td [] [H.text <| "up to " ++ Utils.formatCents prediction.maximumStakeCents]
    ]
  , H.tr []
    [ H.td [] [Utils.b "Created on:"]
    , H.td [] [H.text <| Utils.dateStr timeZone (Utils.unixtimeToTime prediction.createdUnixtime)]
    ]
  , H.tr []
    [ H.td [] [Utils.b "Betting closes:"]
    , H.td [] [H.text <| Utils.dateStr timeZone (Utils.unixtimeToTime prediction.closesUnixtime)]
    ]
  , viewResolutionRow now timeZone prediction
  , case prediction.specialRules of
      "" ->
        H.text ""
      rules ->
        H.tr []
        [ H.td [] [Utils.b "Special rules:"]
        , H.td [] [H.text rules]
        ]
  ]

viewResolutionRow : Time.Posix -> Time.Zone -> Pb.UserPredictionView -> Html msg
viewResolutionRow now timeZone prediction =
  let
    auditLog : Html msg
    auditLog =
      if List.isEmpty prediction.resolutions then H.text "" else
      H.details [HA.style "display" "inline-block", HA.style "opacity" "50%"]
        [ H.summary [] [H.text "History"]
        , makeTable [HA.class "resolution-history-table"]
          [ ( [H.text "When"]
            , \event -> [H.text <| Utils.isoStr timeZone (Utils.unixtimeToTime event.unixtime)]
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
          prediction.resolutions
        ]
  in
  H.tr []
  [ H.td [] [Utils.b "Resolution:"]
  , H.td []
    [ case Utils.currentResolution prediction of
        Pb.ResolutionYes ->
          H.text "YES"
        Pb.ResolutionNo ->
          H.text "NO"
        Pb.ResolutionInvalid ->
          H.text "INVALID"
        Pb.ResolutionNoneYet ->
          H.text <|
            "none yet"
            ++ if prediction.resolvesAtUnixtime < Utils.timeToUnixtime now then
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

viewTradesAsCreator : Time.Zone -> Pb.UserPredictionView -> Html msg
viewTradesAsCreator timeZone prediction =
  let
    allTradesDetails : Username -> List Pb.Trade -> Html msg
    allTradesDetails bettor trades =
      H.details [HA.style "opacity" "50%"]
      [ H.summary [] [H.text "All trades"]
      , makeTable [HA.class "all-trades-details-table"]
        [ ( [H.text "When"]
          , \t -> [H.text (Utils.isoStr timeZone (Utils.unixtimeToTime t.transactedUnixtime))]
          )
        , ( [H.text "Your side"]
          , \t -> [H.text <| if t.bettorIsASkeptic then "YES" else "NO"]
          )
        , ( [H.text "Your stake"]
          , \t -> [H.text <| Utils.formatCents t.creatorStakeCents]
          )
        , ( [Utils.renderUser bettor, H.text "'s stake"]
          , \t -> [H.text <| Utils.formatCents t.bettorStakeCents]
          )
        ]
        trades
      ]
    tradesByBettor = groupTradesByBettor prediction.yourTrades
    bettorColumn =
      ( [H.text "Bettor"]
      , \(bettor, trades) ->
        [ Utils.renderUser bettor
        , allTradesDetails bettor trades
        ]
      )
    winningsColumns =
      case Utils.currentResolution prediction of
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
    makeTable [HA.class "winnings-by-bettor-table"] (bettorColumn :: winningsColumns) (Dict.toList tradesByBettor)

viewTradesAsBettor : Time.Zone -> Pb.UserPredictionView -> Html msg
viewTradesAsBettor timeZone prediction =
  let
    allTradesDetails : Username -> List Pb.Trade -> Html msg
    allTradesDetails counterparty trades =
      H.details [HA.style "opacity" "50%"]
      [ H.summary [] [H.text "All trades"]
      , makeTable [HA.class "all-trades-details-table"]
        [ ( [H.text "When"]
          , \t -> [H.text (Utils.isoStr timeZone (Utils.unixtimeToTime t.transactedUnixtime))]
          )
        , ( [H.text "Your side"]
          , \t -> [H.text <| if t.bettorIsASkeptic then "NO" else "YES"]
          )
        , ( [H.text "You staked"]
          , \t -> [H.text <| Utils.formatCents t.bettorStakeCents]
          )
        , ( [Utils.renderUser counterparty, H.text "'s stake"]
          , \t -> [H.text <| Utils.formatCents t.creatorStakeCents]
          )
        ]
        trades
      ]
  in
    case Utils.currentResolution prediction of
      Pb.ResolutionYes ->
        H.span []
        [ H.text "Resolved YES: "
        , Utils.b <| formatYouWin -(getTotalCreatorWinnings True prediction.yourTrades) ++ "!"
        , allTradesDetails prediction.creator prediction.yourTrades
        ]
      Pb.ResolutionNo ->
        H.span []
        [ H.text "Resolved NO: "
        , Utils.b <| formatYouWin -(getTotalCreatorWinnings False prediction.yourTrades) ++ "!"
        , allTradesDetails prediction.creator prediction.yourTrades
        ]
      Pb.ResolutionInvalid ->
        H.span []
        [ H.text <| "If YES, " ++ formatYouWin -(getTotalCreatorWinnings True prediction.yourTrades)
        , H.text <| "; if NO, " ++ formatYouWin -(getTotalCreatorWinnings False prediction.yourTrades)
        , H.text "."
        , allTradesDetails prediction.creator prediction.yourTrades
        ]
      Pb.ResolutionNoneYet ->
        H.span []
        [ H.text <| "If YES, " ++ formatYouWin -(getTotalCreatorWinnings True prediction.yourTrades)
        , H.text <| "; if NO, " ++ formatYouWin -(getTotalCreatorWinnings False prediction.yourTrades)
        , H.text "."
        , allTradesDetails prediction.creator prediction.yourTrades
        ]
      Pb.ResolutionUnrecognized_ _ ->
        H.text "??????"

getTotalCreatorWinnings : Bool -> List Pb.Trade -> Cents
getTotalCreatorWinnings resolvedYes trades =
  trades
  |> List.map (\t -> if (resolvedYes == t.bettorIsASkeptic) then t.bettorStakeCents else -t.creatorStakeCents)
  |> List.sum

groupTradesByBettor : List Pb.Trade -> Dict Username (List Pb.Trade)
groupTradesByBettor trades =
  let
    help : Dict Username (List Pb.Trade) -> List Pb.Trade -> Dict Username (List Pb.Trade)
    help accum remainder =
      case remainder of
        [] -> accum
        t :: rest -> help (accum |> Dict.update t.bettor (Maybe.withDefault [] >> (::) t >> Just)) rest
  in
    help Dict.empty trades

formatYouWin : Cents -> String
formatYouWin wonCents =
  if wonCents > 0 then
    "you win " ++ Utils.formatCents wonCents
  else
    "you owe " ++ Utils.formatCents (-wonCents)

makeTable : List (H.Attribute msg) -> List (List (Html msg), a -> List (Html msg)) -> List a -> Html msg
makeTable tableAttrs columns xs =
  let
    headerRow = H.tr [] <| List.map (\(header, _) -> H.th [] header) columns
    dataRows = List.map (\x -> H.tr [] (List.map (\(_, toTd) -> H.td [] (toTd x)) columns)) xs
  in
  H.table tableAttrs (headerRow :: dataRows)


viewInvitationWidget : Model -> Html Msg
viewInvitationWidget model =
  SmallInvitationWidget.view
    { setState = SetInvitationWidget
    , createInvitation = CreateInvitation
    , copy = Copy
    , destination = Just <| Utils.pathToPrediction model.predictionId
    , httpOrigin = model.globals.httpOrigin
    }
    model.invitationWidget
viewEmbedInfo : Model -> Html Msg
viewEmbedInfo model =
  let
    prediction = Utils.must "must have loaded prediction being viewed" <| Dict.get model.predictionId model.globals.serverState.predictions
    linkUrl = model.globals.httpOrigin ++ Utils.pathToPrediction model.predictionId  -- TODO(P0): needs origin to get stuck in text field
    imgUrl = model.globals.httpOrigin ++ Utils.pathToPrediction model.predictionId ++ "/embed.png"
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

viewWhatIsThis : PredictionId -> Pb.UserPredictionView -> Html msg
viewWhatIsThis predictionId prediction =
  H.details []
  [ H.summary [] [Utils.b "Huh? What is this?"]
  , H.p []
      [ H.text "This site is a tool that helps people make friendly wagers, thereby clarifying and concretizing their beliefs and making the world a better, saner place."
      ]
  , H.p []
      [ Utils.renderUser prediction.creator
      , H.text <| " is putting their money where their mouth is: they've staked " ++ Utils.formatCents prediction.maximumStakeCents ++ " of real-life money on this prediction,"
          ++ " and they're willing to bet at the above odds against anybody they trust. Good for them!"
      ]
  , H.p []
      [ H.text "If you know and trust ", Utils.renderUser prediction.creator
      , H.text <| ", and they know and trust you, and you want to bet against them on this prediction, then "
      , H.a [HA.href <| "/login?dest=" ++ Utils.pathToPrediction predictionId] [H.text "log in"]
      , H.text ", create an invitation, and send it to them over email/text/whatever! Once they accept it, I'll know you trust each other, and I'll let you bet against each other."
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

update : Msg -> Model -> ( Model , Cmd Msg )
update msg model =
  case msg of
    SetAuthWidget widgetState ->
      ( { model | navbarAuth = widgetState } , Cmd.none )
    SetInvitationWidget widgetState ->
      ( { model | invitationWidget = widgetState } , Cmd.none )
    CreateInvitation widgetState req ->
      ( { model | invitationWidget = widgetState }
      , API.postCreateInvitation (CreateInvitationFinished req) req
      )
    CreateInvitationFinished req res ->
      ( { model | globals = model.globals |> Globals.handleCreateInvitationResponse req res , invitationWidget = model.invitationWidget |> SmallInvitationWidget.handleCreateInvitationResponse res }
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
    RegisterUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postRegisterUsername (RegisterUsernameFinished req) req
      )
    RegisterUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleRegisterUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleRegisterUsernameResponse res
        }
      , case API.simplifyRegisterUsernameResponse res of
          Ok _ -> navigate <| Nothing
          Err _ -> Cmd.none
      )
    Resolve resolution ->
      ( { model | resolveStatus = ResolveAwaitingResponse }
      , let req = {predictionId=model.predictionId, resolution=resolution, notes=""} in API.postResolve (ResolveFinished req) req
      )
    ResolveFinished req res ->
      ( { model | globals = model.globals |> Globals.handleResolveResponse req res
                , resolveStatus = case API.simplifyResolveResponse res of
                    Ok _ -> ResolveSucceeded
                    Err e -> ResolveFailed e
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
          Ok _ -> navigate <| Just "/"
          Err _ -> Cmd.none
      )
    Stake cents ->
      ( { model | stakeStatus = StakeAwaitingResponse }
      , let req = {predictionId=model.predictionId, bettorIsASkeptic=model.bettorIsASkeptic, bettorStakeCents=cents} in API.postStake (StakeFinished req) req
      )
    StakeFinished req res ->
      ( { model | globals = model.globals |> Globals.handleStakeResponse req res
                , stakeStatus = case API.simplifyStakeResponse res of
                    Ok _ -> StakeSucceeded
                    Err e -> StakeFailed e
                , stakeField = case API.simplifyStakeResponse res of
                    Ok _ -> "0"
                    Err _ -> model.stakeField
        }
      , Cmd.none
      )
    SetBettorIsASkeptic bettorIsASkeptic ->
      ( { model | bettorIsASkeptic = bettorIsASkeptic }
      , Cmd.none
      )
    SetStakeField value ->
      ( { model | stakeField = value }
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

subscriptions : Model -> Sub Msg
subscriptions _ = authWidgetExternallyChanged AuthWidgetExternallyModified

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
