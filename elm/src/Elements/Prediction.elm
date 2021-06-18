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
import Widgets.EmailSettingsWidget as EmailSettingsWidget
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Globals
import API
import Biatob.Proto.Mvp as Pb
import Utils exposing (Cents, PredictionId, Username)
import Time
import Bytes.Encode

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
  , emailSettingsWidget : EmailSettingsWidget.State
  , resolveStatus : RequestStatus
  , stakeField : String
  , bettorIsASkeptic : Bool
  , stakeStatus : RequestStatus
  , sendInvitationStatus : RequestStatus
  , setTrustedStatus : RequestStatus
  }

type RequestStatus = Unstarted | AwaitingResponse | Succeeded | Failed String

type Msg
  = SetAuthWidget AuthWidget.State
  | SetEmailWidget EmailSettingsWidget.State
  | SetInvitationWidget SmallInvitationWidget.State
  | SendInvitation
  | SendInvitationFinished Pb.SendInvitationRequest (Result Http.Error Pb.SendInvitationResponse)
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | Resolve Pb.Resolution
  | ResolveFinished Pb.ResolveRequest (Result Http.Error Pb.ResolveResponse)
  | SetCreatorTrusted
  | SetCreatorTrustedFinished Pb.SetTrustedRequest (Result Http.Error Pb.SetTrustedResponse)
  | SetEmail EmailSettingsWidget.State Pb.SetEmailRequest
  | SetEmailFinished Pb.SetEmailRequest (Result Http.Error Pb.SetEmailResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | Stake Cents
  | StakeFinished Pb.StakeRequest (Result Http.Error Pb.StakeResponse)
  | UpdateSettings EmailSettingsWidget.State Pb.UpdateSettingsRequest
  | UpdateSettingsFinished Pb.UpdateSettingsRequest (Result Http.Error Pb.UpdateSettingsResponse)
  | VerifyEmail EmailSettingsWidget.State Pb.VerifyEmailRequest
  | VerifyEmailFinished Pb.VerifyEmailRequest (Result Http.Error Pb.VerifyEmailResponse)
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
    , emailSettingsWidget = EmailSettingsWidget.init
    , resolveStatus = Unstarted
    , stakeStatus = Unstarted
    , setTrustedStatus = Unstarted
    , sendInvitationStatus = Unstarted
    , stakeField = "0"
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
  let
    emptyBytes = Bytes.Encode.encode <| Bytes.Encode.sequence []
    mockToken : Pb.AuthToken
    mockToken =
      { owner="__previewer__"
      , ownerDepr=Nothing
      , mintedUnixtime=0
      , expiresUnixtime=0
      , hmacOfRest=emptyBytes
      }
    mockSettings : Pb.GenericUserInfo
    mockSettings =
      { email = Just {emailFlowStateKind=Just (Pb.EmailFlowStateKindUnstarted Pb.Void)}
      , allowEmailInvitations = True
      , emailRemindersToResolve = True
      , emailResolutionNotifications = True
      , invitations = Dict.empty
      , loginType = Just (Pb.LoginTypeLoginPassword {salt=emptyBytes, scrypt=emptyBytes})
      , relationships = Dict.singleton prediction.creator (Just {trustsYou=True, trustedByYou=True})
      , trustedUsersDepr = []
      }
  in
  viewBody
    { globals = globals
        |> Globals.handleGetPredictionResponse {predictionId="12345"} (Ok {getPredictionResult=Just <| Pb.GetPredictionResultPrediction prediction})
        |> Globals.handleSignOutResponse {} (Ok {})
        |> Globals.handleLogInUsernameResponse {username="__previewer__", password=""} (Ok {logInUsernameResult=Just <| Pb.LogInUsernameResultOk {token=Just mockToken, userInfo=Just mockSettings}})
    , navbarAuth = AuthWidget.init
    , predictionId = "12345"
    , invitationWidget = SmallInvitationWidget.init
    , emailSettingsWidget = EmailSettingsWidget.init
    , resolveStatus = Unstarted
    , stakeStatus = Unstarted
    , setTrustedStatus = Unstarted
    , sendInvitationStatus = Unstarted
    , stakeField = "0"
    , bettorIsASkeptic = True
    }
  |> H.div []
  |> H.map (\_ -> ())

predictionAllowsEmailInvitation : Model -> Bool
predictionAllowsEmailInvitation model =
  (mustPrediction model).allowEmailInvitations

pendingEmailInvitation : Model -> Bool
pendingEmailInvitation model =
  case model.globals.serverState.settings of
    Just settings ->
      Dict.member
        (mustPrediction model).creator
        settings.invitations
    _ -> False
    

userHasEmailAddress : Model -> Bool
userHasEmailAddress model =
  case model.globals.serverState.settings of
    Just settings -> case settings.email of
      Just efs -> case efs.emailFlowStateKind of
        Just (Pb.EmailFlowStateKindVerified _) -> True
        _ -> False
      _ -> False
    _ -> False

type PrereqsForStaking
  = CanAlreadyStake
  | IsCreator
  | NeedsAccount
  | NeedsToSetTrusted
  | NeedsEmailAddress
  | NeedsToSendEmailInvitation
  | NeedsToWaitForInvitation
  | NeedsToTextUserPageLink

getPrereqsForStaking : Model -> PrereqsForStaking
getPrereqsForStaking model =
  let
    creator = (mustPrediction model).creator
  in
  if Globals.isSelf model.globals creator then
    IsCreator
  else if not (Globals.isLoggedIn model.globals) then
    NeedsAccount
  else if Globals.getTrustRelationship model.globals creator == Globals.Friends then
    CanAlreadyStake
  else if Globals.getTrustRelationship model.globals creator == Globals.TrustsCurrentUser then
    NeedsToSetTrusted
  else if predictionAllowsEmailInvitation model then
    if pendingEmailInvitation model then
      NeedsToWaitForInvitation
    else if userHasEmailAddress model then
      NeedsToSendEmailInvitation
    else
      NeedsEmailAddress
  else
    NeedsToTextUserPageLink

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
  , H.hr [] []
  , case getPrereqsForStaking model of
      IsCreator ->
        H.div []
        [ viewResolveButtons model
        , H.hr [HA.style "margin" "2em 0"] []
        , H.text "If you want to link to your prediction, here are some snippets of HTML you could copy-paste:"
        , viewEmbedInfo model
        ]
      NeedsAccount ->
        H.div []
        [ Utils.b "Make a bet:"
        , H.text " Before I let you bet against "
        , Utils.renderUser prediction.creator
        , H.text ", I have to make sure that they trust you to pay up if you lose!"
        , H.br [] []
        , H.text "Could I trouble you to "
        , H.a [HA.href <| "/login?dest=" ++ Utils.pathToPrediction model.predictionId] [H.text "log in or sign up"]
        , H.text " so I have some idea who you are?"
        ]
      CanAlreadyStake ->
        H.div []
        [ Utils.b "Make a bet:"
        , H.text " "
        , viewStakeWidget BettingEnabled model
        ]
      NeedsToSetTrusted ->
        H.div []
        [ Utils.b "Make a bet:"
        , H.text " Before I let you bet against "
        , Utils.renderUser prediction.creator
        , H.text ", I have to make sure that you trust them to pay up if they lose!"
        , H.br [] []
        , H.text "If you know who this account belongs to, and you trust them to pay up if they lose, then click "
        , H.button
          [ HA.disabled (model.setTrustedStatus == AwaitingResponse)
          , HE.onClick SetCreatorTrusted
          ]
          [ H.text <| "I trust '" ++ prediction.creator ++ "'" ]
        , case model.setTrustedStatus of
            Unstarted -> H.text ""
            AwaitingResponse -> H.text ""
            Succeeded -> Utils.greenText "(success!)"
            Failed e -> Utils.redText e
        , H.text " and then I'll let you bet on this!"
        ]
      NeedsToWaitForInvitation ->
        H.div []
        [ Utils.b "Make a bet:"
        , H.text " Before I let you bet against "
        , Utils.renderUser prediction.creator
        , H.text ", I have to make sure that they trust you to pay up if you lose!"
        , H.br [] []
        , H.text "I've sent them an email asking whether they trust you; you'll have to wait for them to say yes before you can bet on their predictions!"
        ]
      NeedsToSendEmailInvitation ->
        H.div []
        [ Utils.b "Make a bet:"
        , H.text " Before I let you bet against "
        , Utils.renderUser prediction.creator
        , H.text ", I have to make sure that they trust you to pay up if you lose!"
        , H.br [] []
        , H.text "May I share your email address with them so that they know who you are? "
        , H.button
          [ HA.disabled (model.sendInvitationStatus == AwaitingResponse)
          , HE.onClick SendInvitation
          ]
          [ H.text <| "I trust '" ++ prediction.creator ++ "'; ask them if they trust me" ]
        , H.br [] []
        , H.text "After they tell me that they trust you, I'll let you bet on this prediction!"
        ]
      NeedsEmailAddress ->
        H.div []
        [ Utils.b "Make a bet:"
        , H.text " Before I let you bet against "
        , Utils.renderUser prediction.creator
        , H.text ", I have to make sure that they trust you to pay up if you lose!"
        , H.br [] []
        , H.text "I can ask them if they trust you, but first, could I trouble you to add an email address to your account, as a way to identify you to them?"
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
      NeedsToTextUserPageLink ->
        H.div []
        [ Utils.b "Make a bet:"
        , H.text " Before I let you bet against "
        , Utils.renderUser prediction.creator
        , H.text ", I have to make sure that they trust you to pay up if you lose!"
        , H.br [] []
        , H.text "Normally, I'd offer to ask them for you, but they've disabled that feature! You'll need to send them a link to "
        , H.a [HA.href <| Utils.pathToUserPage <| .owner <| Utils.must "checked user is logged in" model.globals.authToken] [H.text "your user page"]
        , H.text ", over SMS/IM/email/whatever, and ask them to mark you as trusted."
        ]

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
          [ HA.disabled (model.resolveStatus == AwaitingResponse)
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
          [ H.button [HA.disabled (model.resolveStatus == AwaitingResponse), HE.onClick <| Resolve Pb.ResolutionYes    ] [H.text "Resolve YES"]
          , H.button [HA.disabled (model.resolveStatus == AwaitingResponse), HE.onClick <| Resolve Pb.ResolutionNo     ] [H.text "Resolve NO"]
          , H.button [HA.disabled (model.resolveStatus == AwaitingResponse), HE.onClick <| Resolve Pb.ResolutionInvalid] [H.text "Resolve INVALID"]
          ]
        Pb.ResolutionUnrecognized_ _ ->
          H.span []
          [ H.span [HA.style "color" "red"] [H.text "unrecognized resolution"]
          , mistakeInfo
          ]
    , H.text " "
    , case model.resolveStatus of
        Unstarted -> H.text ""
        AwaitingResponse -> H.text ""
        Succeeded -> Utils.greenText "Resolved!"
        Failed e -> Utils.redText e
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
        Unstarted -> H.text ""
        AwaitingResponse -> H.text ""
        Succeeded -> Utils.greenText "Success!"
        Failed e -> Utils.redText e
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
    SetEmailWidget widgetState ->
      ( { model | emailSettingsWidget = widgetState } , Cmd.none )
    SetInvitationWidget widgetState ->
      ( { model | invitationWidget = widgetState } , Cmd.none )
    SendInvitation ->
      ( { model | sendInvitationStatus = AwaitingResponse }
      , let req = {recipient=(mustPrediction model).creator} in API.postSendInvitation (SendInvitationFinished req) req
      )
    SendInvitationFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSendInvitationResponse req res , invitationWidget = model.invitationWidget |> SmallInvitationWidget.handleSendInvitationResponse res }
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
      ( { model | resolveStatus = AwaitingResponse }
      , let req = {predictionId=model.predictionId, resolution=resolution, notes=""} in API.postResolve (ResolveFinished req) req
      )
    ResolveFinished req res ->
      ( { model | globals = model.globals |> Globals.handleResolveResponse req res
                , resolveStatus = case API.simplifyResolveResponse res of
                    Ok _ -> Succeeded
                    Err e -> Failed e
        }
      , Cmd.none
      )
    SetCreatorTrusted ->
      ( { model | setTrustedStatus = AwaitingResponse }
      , let req = {whoDepr=Nothing, who=(mustPrediction model).creator, trusted=True} in API.postSetTrusted (SetCreatorTrustedFinished req) req
      )
    SetCreatorTrustedFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSetTrustedResponse req res
                , setTrustedStatus = case API.simplifySetTrustedResponse res of
                    Ok _ -> Succeeded
                    Err e -> Failed e
        }
      , Cmd.none
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
      ( { model | stakeStatus = AwaitingResponse }
      , let req = {predictionId=model.predictionId, bettorIsASkeptic=model.bettorIsASkeptic, bettorStakeCents=cents} in API.postStake (StakeFinished req) req
      )
    StakeFinished req res ->
      ( { model | globals = model.globals |> Globals.handleStakeResponse req res
                , stakeStatus = case API.simplifyStakeResponse res of
                    Ok _ -> Succeeded
                    Err e -> Failed e
                , stakeField = case API.simplifyStakeResponse res of
                    Ok _ -> "0"
                    Err _ -> model.stakeField
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
