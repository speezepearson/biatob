port module Elements.Prediction exposing (main, viewBodyMockup)

import Browser
import Dict exposing (Dict)
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as JD
import Http

import Widgets.CopyWidget as CopyWidget
import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Widgets.EmailSettingsWidget as EmailSettingsWidget
import Globals
import API
import Biatob.Proto.Mvp as Pb
import Utils exposing (Cents, PredictionId, Username, isOk, viewError)
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
  , authWidget : AuthWidget.State
  , predictionId : PredictionId
  , emailSettingsWidget : EmailSettingsWidget.State
  , resolveStatus : RequestStatus
  , stakeField : String
  , bettorIsASkeptic : Bool
  , stakeStatus : RequestStatus
  , sendInvitationStatus : RequestStatus
  , setTrustedStatus : RequestStatus
  , shareEmbedding : EmbeddingFields
  }

type alias EmbeddingFields =
  { format : EmbeddingFormat
  , contentType : EmbeddingContentType
  , color : EmbeddedImageColor
  , fontSize : EmbeddedImageFontSize
  }

type EmbeddedImageColor = Red | DarkGreen | DarkBlue | Black | White
imageColorIdString color = case color of
  Red -> "red"
  DarkGreen -> "darkgreen"
  DarkBlue -> "darkblue"
  Black -> "black"
  White -> "white"
imageColorDisplayName color = case color of
  Red -> "red"
  DarkGreen -> "green"
  DarkBlue -> "blue"
  Black -> "black"
  White -> "white"
imageColorCssCode color = case color of
  Red ->       "rgb(255, 0  , 0  )"
  DarkGreen -> "rgb(0  , 128, 0  )"
  DarkBlue ->  "rgb(0  , 0  , 128)"
  Black ->     "rgb(0  , 0  , 0  )"
  White ->     "rgb(255, 255, 255)"
type EmbeddedImageFontSize = SixPt | EightPt | TenPt | TwelvePt | FourteenPt | EighteenPt | TwentyFourPt
imageFontSizeIdString size = case size of
  SixPt -> "6pt"
  EightPt -> "8pt"
  TenPt -> "10pt"
  TwelvePt -> "12pt"
  FourteenPt -> "14pt"
  EighteenPt -> "18pt"
  TwentyFourPt -> "24pt"
imageFontSizeDisplayName = imageFontSizeIdString
type EmbeddingFormat = EmbedHtml | EmbedMarkdown
formatDisplayName fmt = case fmt of
  EmbedHtml -> "HTML"
  EmbedMarkdown -> "Markdown"

type EmbeddingContentType = Link | Image
contentTypeDisplayName ct = case ct of
  Link -> "link"
  Image -> "image"

embeddedLinkText : String -> PredictionId -> Pb.UserPredictionView -> String
embeddedLinkText httpOrigin predictionId prediction =
  let
    certainty = Utils.mustPredictionCertainty prediction
  in
    "(bet "
    ++ Utils.formatCents (prediction.maximumStakeCents // 100 * 100)
    ++ " @ "
    ++ String.fromInt (round <| certainty.low * 100)
    ++ (if certainty.high < 1 then
          "-"
          ++ String.fromInt (round <| certainty.high * 100)
          ++ ""
        else
          ""
       )
    ++ ")"
embeddedImageUrl : String -> PredictionId -> EmbeddedImageColor -> EmbeddedImageFontSize -> String
embeddedImageUrl httpOrigin predictionId color size =
  httpOrigin
  ++ Utils.pathToPrediction predictionId
  ++ "/embed-" ++ imageColorIdString color
  ++ "-" ++ imageFontSizeIdString size
  ++ ".png"
embeddedImageStyles : EmbeddingFields -> List (String, String)
embeddedImageStyles fields =
  [ ("max-height", "1.5em")
  , ("border-bottom", "1px solid " ++ imageColorCssCode fields.color)
  ]
embeddingPreview : String -> PredictionId -> Pb.UserPredictionView -> EmbeddingFields -> Html msg
embeddingPreview httpOrigin predictionId prediction fields =
  let
    linkUrl = httpOrigin ++ Utils.pathToPrediction predictionId
    text = embeddedLinkText httpOrigin predictionId prediction
  in
  case fields.contentType |> Debug.log "contentType" of
    Link -> H.a [HA.href linkUrl] [H.text text]
    Image ->
      H.a [HA.href linkUrl]
        [ H.img
          ( [ HA.alt text
            , HA.src <| embeddedImageUrl httpOrigin predictionId fields.color fields.fontSize
            ]
            ++ (embeddedImageStyles fields |> List.map (\(k,v) -> HA.style k v))
          )
          []
        ]

embeddingCode : String -> PredictionId -> Pb.UserPredictionView -> EmbeddingFields -> String
embeddingCode httpOrigin predictionId prediction fields =
  let
    linkUrl = httpOrigin ++ Utils.pathToPrediction predictionId
    text = embeddedLinkText httpOrigin predictionId prediction
  in
  case fields.contentType of
    Link ->
      case fields.format of
        EmbedHtml -> "<a href=\"" ++ linkUrl ++ "\">" ++ text ++ "</a>"
        EmbedMarkdown -> "[" ++ text ++ "](" ++ linkUrl ++ ")"
    Image ->
      let
        imageUrl = embeddedImageUrl httpOrigin predictionId fields.color fields.fontSize
        imageStyles = embeddedImageStyles fields
      in
      case fields.format of
        EmbedHtml ->
          ( "<a href=\"" ++ linkUrl ++ "\">"
            ++ "<img alt=\"" ++ text ++ "\""
            ++ " src=\"" ++ imageUrl ++ "\""
            ++ " style=\"" ++ String.join "; " (List.map (\(k,v) -> k++":"++v) imageStyles) ++ "\""
            ++ " />"
            ++ "</a>"
          )
        EmbedMarkdown -> "[![" ++ text ++ "](" ++ imageUrl ++ ")](" ++ linkUrl ++ ")"

type RequestStatus = Unstarted | AwaitingResponse | Succeeded | Failed String
type AuthWidgetLoc = Navbar | Inline

type Msg
  = SetAuthWidget AuthWidgetLoc AuthWidget.State
  | SetEmailWidget EmailSettingsWidget.State
  | SendInvitation
  | SendInvitationFinished Pb.SendInvitationRequest (Result Http.Error Pb.SendInvitationResponse)
  | LogInUsername AuthWidgetLoc AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished AuthWidgetLoc Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidgetLoc AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished AuthWidgetLoc Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | Resolve Pb.Resolution
  | ResolveFinished Pb.ResolveRequest (Result Http.Error Pb.ResolveResponse)
  | SetCreatorTrusted
  | SetCreatorTrustedFinished Pb.SetTrustedRequest (Result Http.Error Pb.SetTrustedResponse)
  | SetEmail EmailSettingsWidget.State Pb.SetEmailRequest
  | SetEmailFinished Pb.SetEmailRequest (Result Http.Error Pb.SetEmailResponse)
  | SignOut AuthWidgetLoc AuthWidget.State Pb.SignOutRequest
  | SignOutFinished AuthWidgetLoc Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | QueueStake Cents
  | QueueStakeFinished Pb.QueueStakeRequest (Result Http.Error Pb.QueueStakeResponse)
  | Stake Cents
  | StakeFinished Pb.StakeRequest (Result Http.Error Pb.StakeResponse)
  | UpdateSettings EmailSettingsWidget.State Pb.UpdateSettingsRequest
  | UpdateSettingsFinished Pb.UpdateSettingsRequest (Result Http.Error Pb.UpdateSettingsResponse)
  | VerifyEmail EmailSettingsWidget.State Pb.VerifyEmailRequest
  | VerifyEmailFinished Pb.VerifyEmailRequest (Result Http.Error Pb.VerifyEmailResponse)
  | SetBettorIsASkeptic Bool
  | SetStakeField String
  | SetEmbedding EmbeddingFields
  | Copy String
  | Tick Time.Posix
  | AuthWidgetExternallyModified AuthWidget.DomModification
  | Ignore

init : JD.Value -> ( Model, Cmd Msg )
init flags =
  let
    globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
    predictionId = Utils.mustDecodeFromFlags JD.string "predictionId" flags
    prediction = Utils.must "must have loaded prediction being viewed" <| Dict.get predictionId globals.serverState.predictions
  in
  ( { globals = globals
    , navbarAuth = AuthWidget.init
    , authWidget = AuthWidget.init
    , predictionId = predictionId
    , emailSettingsWidget = EmailSettingsWidget.init
    , resolveStatus = Unstarted
    , stakeStatus = Unstarted
    , setTrustedStatus = Unstarted
    , sendInvitationStatus = Unstarted
    , stakeField = "10"
    , bettorIsASkeptic = True
    , shareEmbedding = { format = EmbedHtml, contentType = Image , color = DarkGreen , fontSize = FourteenPt }
    } |> updateBettorInputFields prediction
  , Cmd.none
  )

updateBettorInputFields : Pb.UserPredictionView -> Model -> Model
updateBettorInputFields prediction model =
  let
    bettorIsASkeptic = not (canAnyBelieversBet prediction && not (canAnySkepticsBet prediction))
  in
  { model | stakeField = min 1000 (getBetParameters bettorIsASkeptic prediction).maxBettorStake |> Utils.formatCents |> String.replace "$" ""
          , bettorIsASkeptic = bettorIsASkeptic
  }

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
        { setState = SetAuthWidget Navbar
        , logInUsername = LogInUsername Navbar
        , register = RegisterUsername Navbar
        , signOut = SignOut Navbar
        , ignore = Ignore
        , auth = Globals.getAuth model.globals
        , id = "navbar-auth"
        }
        model.navbarAuth
    , H.main_ [HA.class "container"] (viewBody model)
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
    ({ globals = globals
        |> Globals.handleGetPredictionResponse {predictionId="12345"} (Ok {getPredictionResult=Just <| Pb.GetPredictionResultPrediction prediction})
        |> Globals.handleSignOutResponse {} (Ok {})
        |> Globals.handleLogInUsernameResponse {username="__previewer__", password=""} (Ok {logInUsernameResult=Just <| Pb.LogInUsernameResultOk {token=Just mockToken, userInfo=Just mockSettings}})
    , navbarAuth = AuthWidget.init
    , authWidget = AuthWidget.init
    , predictionId = "12345"
    , emailSettingsWidget = EmailSettingsWidget.init
    , resolveStatus = Unstarted
    , stakeStatus = Unstarted
    , setTrustedStatus = Unstarted
    , sendInvitationStatus = Unstarted
    , stakeField = "10"
    , bettorIsASkeptic = True
    , shareEmbedding = { format = EmbedHtml, contentType = Image , color = DarkGreen , fontSize = FourteenPt }
    } |> updateBettorInputFields prediction)
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
  | CreatorStakeExhausted
  | NeedsAccount
  | NeedsToSetTrusted
  | NeedsEmailAddress
  | NeedsToSendEmailInvitation
  | NeedsToWaitForInvitation
  | NeedsToTextUserPageLink

getBetParameters : Bool -> Pb.UserPredictionView -> { remainingCreatorStake : Cents , creatorStakeFactor : Float , maxBettorStake : Cents }
getBetParameters bettorIsASkeptic prediction =
  let
    certainty = Utils.mustPredictionCertainty prediction
    creatorStakeFactor =
      if bettorIsASkeptic then
        certainty.low / (1 - certainty.low)
      else
        (1 - certainty.high) / certainty.high
    remainingCreatorStake =
      if bettorIsASkeptic then
        prediction.remainingStakeCentsVsSkeptics
      else
        prediction.remainingStakeCentsVsBelievers
    maxBettorStake =
      (if creatorStakeFactor == 0 then
        0
      else
        toFloat remainingCreatorStake / creatorStakeFactor + epsilon |> floor
      )
      |> (\n -> if toFloat n * creatorStakeFactor < 1 then 0 else n )
      |> min Utils.maxLegalStakeCents
  in
    { remainingCreatorStake = remainingCreatorStake
    , creatorStakeFactor = creatorStakeFactor
    , maxBettorStake = maxBettorStake
    } |> Debug.log "bet params"


canAnySkepticsBet : Pb.UserPredictionView -> Bool
canAnySkepticsBet prediction =
  (getBetParameters True prediction).maxBettorStake > 0
canAnyBelieversBet : Pb.UserPredictionView -> Bool
canAnyBelieversBet prediction =
  (getBetParameters False prediction).maxBettorStake > 0

getPrereqsForStaking : Model -> PrereqsForStaking
getPrereqsForStaking model =
  let
    prediction = mustPrediction model
    creator = prediction.creator
  in
  if Globals.isSelf model.globals creator then
    IsCreator
  else if not (Globals.isLoggedIn model.globals) then
    NeedsAccount
  else if not (canAnySkepticsBet prediction) && not (canAnyBelieversBet prediction) then
    CreatorStakeExhausted
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
    maybeButHeresAQueueForm =
      if Globals.getRelationship model.globals prediction.creator |> Maybe.map .trustedByYou |> Maybe.withDefault False then
        H.p []
        [ H.text "However! While you're waiting for them to trust you back, I'll let you "
        , Utils.i "queue up"
        , H.text " bets that I'll apply once "
        , Utils.renderUser prediction.creator
        , H.text " tells me they trust you."
        , viewStakeWidget QueueingNecessary model
        ]
      else
        H.text ""
  in
  [ H.h2 [HA.class "text-center"] [H.text <| getTitleText model.globals.timeZone prediction]
  , H.hr [] []
  , H.div [HA.class "row row-cols-12"]
    [ H.div [HA.class "col-md-4"] [viewSummaryTable model.globals.now model.globals.timeZone prediction]
    , H.div [HA.class "col-md-8"]
      [ if List.isEmpty prediction.yourTrades then
          H.text ""
        else
          H.div []
          [ Utils.b "Your existing stake: "
          , if isOwnPrediction then
              viewTradesAsCreator model.globals.timeZone prediction
            else
              viewTradesAsBettor model.globals.timeZone prediction prediction.yourTrades
          , H.hr [] []
          ]
      , if (not isOwnPrediction) || List.isEmpty prediction.yourQueuedTrades then
          H.text ""
        else
          H.div []
          [ Utils.b "Your queued stake"
          , H.text " (from bets that I'll apply once "
          , Utils.renderUser prediction.creator
          , H.text " tells me they trust you): "
          , viewTradesAsBettor model.globals.timeZone prediction
            <| List.map
                (\qt -> {bettor=qt.bettor, bettorIsASkeptic=qt.bettorIsASkeptic, bettorStakeCents=qt.bettorStakeCents, creatorStakeCents=qt.creatorStakeCents, transactedUnixtime=qt.enqueuedAtUnixtime})
                prediction.yourQueuedTrades
          , H.hr [] []
          ]

      , case getPrereqsForStaking model of
          IsCreator ->
            H.div []
            [ viewResolveButtons model
            , H.hr [HA.style "margin" "2em 0"] []
            , H.text "If you want to link to your prediction, here's some code you could copy-paste:"
            , viewEmbedInfo model
            ]
          CreatorStakeExhausted ->
            H.div []
            [ Utils.b "Make a bet: "
            , Utils.renderUser prediction.creator
            , H.text " has already accepted so many bets that they've reached their maximum risk of "
            , H.text <| Utils.formatCents prediction.maximumStakeCents
            , H.text "! So, sadly, no further betting is possible."
            ]
          NeedsAccount ->
            H.div []
            [ Utils.b "Make a bet:"
            , H.text " Before I let you bet against "
            , Utils.renderUser prediction.creator
            , H.text ", I have to make sure that they trust you to pay up if you lose!"
            , H.br [] []
            , H.text "Could I trouble you to log in or sign up, so I have some idea who you are?"
            , H.div [HA.class "m-1 mx-4"]
              [ AuthWidget.view
                { setState = SetAuthWidget Inline
                , logInUsername = LogInUsername Inline
                , register = RegisterUsername Inline
                , signOut = SignOut Inline
                , ignore = Ignore
                , auth = Globals.getAuth model.globals
                , id = "inline-auth"
                }
                model.authWidget
              ]
            ]
          CanAlreadyStake ->
            H.div []
            [ Utils.b "Make a bet:"
            , H.text " "
            , viewStakeWidget QueueingUnnecessary model
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
              , HA.class "btn btn-sm btn-primary"
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
            [ H.p []
              [ Utils.b "Make a bet:"
              , H.text " Before I let you bet against "
              , Utils.renderUser prediction.creator
              , H.text ", I have to make sure that they trust you to pay up if you lose!"
              , H.br [] []
              , H.text "I've sent them an email asking whether they trust you; you'll have to wait for them to say yes before you can bet on their predictions!"
            ]
            , maybeButHeresAQueueForm
            ]
          NeedsToSendEmailInvitation ->
            H.div []
            [ H.p []
              [ Utils.b "Make a bet:"
              , H.text " Before I let you bet against "
              , Utils.renderUser prediction.creator
              , H.text ", I have to make sure that they trust you to pay up if you lose!"
              , H.br [] []
              , H.text "May I share your email address with them so that they know who you are? "
              , H.button
                [ HA.disabled (model.sendInvitationStatus == AwaitingResponse)
                , HE.onClick SendInvitation
                , HA.class "btn btn-sm btn-primary"
                ]
                [ H.text <| "Yes, I trust '" ++ prediction.creator ++ "', and I'm pretty sure they trust me too." ]
              , H.br [] []
              , H.text "After they tell me that they trust you, I'll let you bet on this prediction!"
              ]
            , H.p []
              [ H.text "Alternatively, you could "
              , if Globals.getRelationship model.globals prediction.creator |> Maybe.map .trustedByYou |> Maybe.withDefault False then
                  H.span []
                  [ H.text " text/email/whatever them a link to "
                  , H.a [HA.href <| Utils.pathToUserPage <| Utils.must "NeedsEmailAddress only possible for logged-in users" <| Globals.getOwnUsername model.globals] [H.text "your user page"]
                  , H.text " and ask them to mark you as trusted."
                  ]
                else
                  H.span []
                  [ H.text " click "
                  , H.button
                    [ HA.disabled (model.setTrustedStatus == AwaitingResponse)
                    , HE.onClick SetCreatorTrusted
                    , HA.class "btn btn-sm btn-primary"
                    ]
                    [ H.text <| "I trust '" ++ prediction.creator ++ "'" ]
                  , case model.setTrustedStatus of
                      Unstarted -> H.text ""
                      AwaitingResponse -> H.text ""
                      Succeeded -> Utils.greenText "(success!)"
                      Failed e -> Utils.redText e
                  , H.text " and text/email/whatever them a link to "
                  , H.a [HA.href <| Utils.pathToUserPage <| Utils.must "NeedsEmailAddress only possible for logged-in users" <| Globals.getOwnUsername model.globals] [H.text "your user page"]
                  , H.text " and ask them to mark you as trusted."
                  ]
                ]
            , maybeButHeresAQueueForm
            ]
          NeedsEmailAddress ->
            H.div []
            [ H.p []
              [ Utils.b "Make a bet:"
              , H.text " Before I let you bet against "
              , Utils.renderUser prediction.creator
              , H.text ", I have to make sure that they trust you to pay up if you lose!"
              , H.br [] []
              , H.text "I can ask them if they trust you, but first, could I trouble you to add an email address to your account, as a way to identify you to them?"
              , H.div [HA.class "m-1 mx-4"]
                [ EmailSettingsWidget.view
                  { setState = SetEmailWidget
                  , ignore = Ignore
                  , setEmail = SetEmail
                  , verifyEmail = VerifyEmail
                  , updateSettings = UpdateSettings
                  , userInfo = Utils.must "checked that user is logged in" model.globals.serverState.settings
                  }
                  model.emailSettingsWidget
                ]
              ]
            , H.p []
              [ H.text "Alternatively, you could "
              , if Globals.getRelationship model.globals prediction.creator |> Maybe.map .trustedByYou |> Maybe.withDefault False then
                  H.span []
                  [ H.text " text/email/whatever them a link to "
                  , H.a [HA.href <| Utils.pathToUserPage <| Utils.must "NeedsEmailAddress only possible for logged-in users" <| Globals.getOwnUsername model.globals] [H.text "your user page"]
                  , H.text " and ask them to mark you as trusted."
                  ]
                else
                  H.span []
                  [ H.text " click "
                  , H.button
                    [ HA.disabled (model.setTrustedStatus == AwaitingResponse)
                    , HE.onClick SetCreatorTrusted
                    , HA.class "btn btn-sm btn-primary"
                    ]
                    [ H.text <| "I trust '" ++ prediction.creator ++ "'" ]
                  , case model.setTrustedStatus of
                      Unstarted -> H.text ""
                      AwaitingResponse -> H.text ""
                      Succeeded -> Utils.greenText "(success!)"
                      Failed e -> Utils.redText e
                  , H.text " and text/email/whatever them a link to "
                  , H.a [HA.href <| Utils.pathToUserPage <| Utils.must "NeedsEmailAddress only possible for logged-in users" <| Globals.getOwnUsername model.globals] [H.text "your user page"]
                  , H.text " and ask them to mark you as trusted."
                  ]
                ]
            , maybeButHeresAQueueForm
            ]
          NeedsToTextUserPageLink ->
            H.div []
            [ H.p []
              [ Utils.b "Make a bet:"
              , H.text " Before I let you bet against "
              , Utils.renderUser prediction.creator
              , H.text ", I have to make sure that they trust you to pay up if you lose!"
              , H.br [] []
              , H.text "Normally, I'd offer to ask them for you, but they've disabled that feature! You'll need to send them a link to "
              , H.a [HA.href <| Utils.pathToUserPage <| Utils.must "checked user is logged in" <| Globals.getOwnUsername model.globals] [H.text "your user page"]
              , H.text ", over SMS/IM/email/whatever, and ask them to mark you as trusted."
              ]
            , maybeButHeresAQueueForm
            ]
      ]
    , if not (Globals.isLoggedIn model.globals) then
        H.div []
        [ H.hr [HA.style "margin" "2em 0"] []
        , viewWhatIsThis model.predictionId prediction
        ]
      else
        H.text ""
    ]
  ]

viewResolveButtons : Model -> Html Msg
viewResolveButtons model =
  let
    prediction = mustPrediction model
    mistakeInfo : String -> Html Msg
    mistakeInfo s =
      H.span [HA.style "color" "gray"]
        [ H.text "You said that this "
        , H.text s
        , H.text ". If that was a mistake, you can always "
        , H.button
          [ HA.disabled (model.resolveStatus == AwaitingResponse)
          , HE.onClick <| Resolve Pb.ResolutionNoneYet
          , HA.class "btn btn-sm py-0 btn-outline-secondary"
          ]
          [ H.text "un-resolve it." ]
        ]
  in
    H.div []
    [ Utils.b "Resolve this prediction: "
    , case Utils.currentResolution prediction of
        Pb.ResolutionYes ->
          mistakeInfo "HAPPENED"
        Pb.ResolutionNo ->
          mistakeInfo "DID NOT HAPPEN"
        Pb.ResolutionInvalid ->
          mistakeInfo "was INVALID"
        Pb.ResolutionNoneYet ->
          H.span []
          [ H.button [HA.class "btn btn-sm py-0 btn-outline-primary mx-2", HA.disabled (model.resolveStatus == AwaitingResponse), HE.onClick <| Resolve Pb.ResolutionYes    ] [H.text "It happened!"]
          , H.button [HA.class "btn btn-sm py-0 btn-outline-primary mx-2", HA.disabled (model.resolveStatus == AwaitingResponse), HE.onClick <| Resolve Pb.ResolutionNo     ] [H.text "It didn't happen!"]
          , H.button [HA.class "btn btn-sm py-0 btn-outline-secondary mx-2", HA.disabled (model.resolveStatus == AwaitingResponse), HE.onClick <| Resolve Pb.ResolutionInvalid] [H.text "Invalid prediction / impossible to resolve"]
          ]
        Pb.ResolutionUnrecognized_ _ ->
          H.span []
          [ H.span [HA.style "color" "red"] [H.text "unrecognized resolution"]
          , mistakeInfo "??????"
          ]
    , H.text " "
    , case model.resolveStatus of
        Unstarted -> H.text ""
        AwaitingResponse -> H.text ""
        Succeeded -> Utils.greenText "Resolution updated!"
        Failed e -> Utils.redText e
    ]

viewWillWontDropdown : Model -> Html Msg
viewWillWontDropdown model =
  if not (canAnyBelieversBet (mustPrediction model)) then
    Utils.b "won't"
  else if not (canAnySkepticsBet (mustPrediction model)) then
    Utils.b "will"
  else
    H.select
      [ HE.onInput (\s -> SetBettorIsASkeptic (case s of
          "won't" -> True
          "will" -> False
          _ -> Debug.todo <| "invalid value" ++ Debug.toString s ++ "for skepticism dropdown"
        ))
      , HA.class "form-select form-select-sm d-inline-block w-auto"
      ]
      [ H.option [HA.value "won't", HA.selected <| model.bettorIsASkeptic] [H.text "won't"]
      , H.option [HA.value "will", HA.selected <| not <| model.bettorIsASkeptic] [H.text "will"]
      ]

type Bettability = QueueingNecessary | QueueingUnnecessary
viewStakeWidget : Bettability -> Model -> Html Msg
viewStakeWidget bettability model =
  let
    prediction = mustPrediction model

    betParameters = getBetParameters model.bettorIsASkeptic prediction
    stakeCents = case String.toFloat model.stakeField of
      Nothing -> Err "must be a number"
      Just dollars ->
        let n = floor (100*dollars) in
        if n < 0 || n > betParameters.maxBettorStake then
          Err <|
            "must be between $0 and " ++ Utils.formatCents betParameters.maxBettorStake
            ++ ": " ++ if betParameters.maxBettorStake == Utils.maxLegalStakeCents then
                "I don't (yet) want this site used for enormous bets"
              else
                (prediction.creator ++ " isn't willing to make larger bets")
        else
          Ok n
  in
  H.span []
    [ H.text " Bet $"
    , H.input
        [ HA.style "width" "7em"
        , HA.type_"number", HA.min "0", HA.max (toFloat betParameters.maxBettorStake / 100 + epsilon |> String.fromFloat), HA.step "any"
        , HA.class "form-control form-control-sm d-inline-block"
        , HA.id "stakeField"
        , HE.onInput SetStakeField
        , HA.value model.stakeField
        , HA.class (if isOk stakeCents then "" else "is-invalid")
        ]
        []
    , H.text " that this "
    , viewWillWontDropdown model
    , H.text <| " happen, against " ++ prediction.creator ++ "'s "
    , Utils.b (stakeCents |> Result.map (toFloat >> (*) betParameters.creatorStakeFactor >> floor >> Utils.formatCents) |> Result.withDefault "???")
    , H.text " that it "
    , H.text <| if model.bettorIsASkeptic then "will" else "won't"
    , H.text ". "
    , H.button
        (HA.class "btn btn-sm py-0 btn-primary" :: case stakeCents of
          Ok 0 ->
            [ HA.disabled True ]
          Ok cents ->
            [ HE.onClick <| case bettability of
                QueueingNecessary -> QueueStake cents
                QueueingUnnecessary -> Stake cents
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
          H.div [HA.style "opacity" "50%"]
          <|  if prediction.remainingStakeCentsVsSkeptics == 0 then
                [ Utils.renderUser prediction.creator
                , H.text <| " has reached their limit of " ++ Utils.formatCents prediction.maximumStakeCents
                , H.text " on this bet, and isn't willing to risk losing any more!"
                ]
              else
                [ H.text <| "Only " ++ Utils.formatCents prediction.remainingStakeCentsVsSkeptics ++ " of "
                , Utils.renderUser prediction.creator
                , H.text <| "'s initial stake remains, since they've already accepted some bets."
                ]
        else
          H.text ""
      else
        if prediction.remainingStakeCentsVsBelievers /= prediction.maximumStakeCents then
          H.div [HA.style "opacity" "50%"]
          <|  if prediction.remainingStakeCentsVsBelievers == 0 then
                [ Utils.renderUser prediction.creator
                , H.text <| " has reached their limit of " ++ Utils.formatCents prediction.maximumStakeCents
                , H.text " on this bet, and isn't willing to risk losing any more!"
                ]
              else
                [ H.text <| "Only " ++ Utils.formatCents prediction.remainingStakeCentsVsBelievers ++ " of "
                , Utils.renderUser prediction.creator
                , H.text <| "'s initial stake remains, since they've already accepted some bets."
                ]
        else
          H.text ""
    , H.div [HA.class "invalid-feedback"] [viewError stakeCents]
    ]

getTitleText : Time.Zone -> Pb.UserPredictionView -> String
getTitleText timeZone prediction =
  "Prediction: by " ++ (Utils.dateStr timeZone <| Utils.unixtimeToTime prediction.resolvesAtUnixtime) ++ ", " ++ prediction.prediction


viewSummaryTable : Time.Posix -> Time.Zone -> Pb.UserPredictionView -> Html Msg
viewSummaryTable now timeZone prediction =
  H.table [HA.class "table table-sm", HA.class "col-4"]
  [ H.tbody []
    [ H.tr []
      [ H.th [HA.scope "row"] [H.text "Prediction by:"]
      , H.td [] [Utils.renderUser prediction.creator]
      ]
    , H.tr []
      [ H.th [HA.scope "row"] [H.text "Confidence:"]
      , H.td [] [H.text <|
          (String.fromInt <| round <| 100 * (Utils.mustPredictionCertainty prediction).low)
          ++ "-" ++
          (String.fromInt <| round <| 100 * (Utils.mustPredictionCertainty prediction).high)
          ++ "%"]
      ]
    , H.tr []
      [ H.th [HA.scope "row"] [H.text "Stakes:"]
      , H.td [] [H.text <| "up to " ++ Utils.formatCents prediction.maximumStakeCents]
      ]
    , H.tr []
      [ H.th [HA.scope "row"] [H.text "Created on:"]
      , H.td [] [H.text <| Utils.dateStr timeZone (Utils.unixtimeToTime prediction.createdUnixtime)]
      ]
    , let secondsRemaining = prediction.closesUnixtime - Utils.timeToUnixtime now in
      H.tr []
      [ H.th [HA.scope "row"] [H.text <| "Betting " ++ (if secondsRemaining < 0 then "closed" else "closes") ++ ":"]
      , H.td []
        [ H.text <| Utils.dateStr timeZone (Utils.unixtimeToTime prediction.closesUnixtime)
        , if 0 < secondsRemaining && secondsRemaining < 86400 * 3 then
            H.text <| " (in " ++ Utils.renderIntervalSeconds secondsRemaining ++ ")"
          else
            H.text ""
        ]
      ]
    , viewResolutionRow now timeZone prediction
    , case prediction.specialRules of
        "" ->
          H.text ""
        rules ->
          H.tr []
          [ H.th [HA.scope "row"] [H.text "Special rules:"]
          , H.td [] [H.text rules]
          ]
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
                  Pb.ResolutionYes -> "happened"
                  Pb.ResolutionNo -> "did not happen"
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
  [ H.th [HA.scope "row"] [H.text "Resolution:"]
  , H.td []
    [ case Utils.currentResolution prediction of
        Pb.ResolutionYes ->
          H.text "it happened"
        Pb.ResolutionNo ->
          H.text "it didn't happen"
        Pb.ResolutionInvalid ->
          H.text "INVALID PREDICTION"
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
          , \t -> [H.text <| if t.bettorIsASkeptic then "will happen" else "will not happen"]
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
          [ ( [H.text "if it happens"]
            , \(_, trades) -> [H.text <| formatYouWin <| getTotalCreatorWinnings True trades]
            )
          , ( [H.text "if not"]
            , \(_, trades) -> [H.text <| formatYouWin <| getTotalCreatorWinnings False trades]
            )
          ]
        Pb.ResolutionNoneYet ->
          [ ( [H.text "if it happens"]
            , \(_, trades) -> [H.text <| formatYouWin <| getTotalCreatorWinnings True trades]
            )
          , ( [H.text "if not"]
            , \(_, trades) -> [H.text <| formatYouWin <| getTotalCreatorWinnings False trades]
            )
          ]
        Pb.ResolutionUnrecognized_ _ ->
          []
  in
    makeTable [HA.class "winnings-by-bettor-table"] (bettorColumn :: winningsColumns) (Dict.toList tradesByBettor)

viewTradesAsBettor : Time.Zone -> Pb.UserPredictionView -> List Pb.Trade -> Html msg
viewTradesAsBettor timeZone prediction trades =
  let
    allTradesDetails : Html msg
    allTradesDetails =
      H.details [HA.style "opacity" "50%"]
      [ H.summary [] [H.text "All trades"]
      , makeTable [HA.class "all-trades-details-table"]
        [ ( [H.text "When"]
          , \t -> [H.text (Utils.isoStr timeZone (Utils.unixtimeToTime t.transactedUnixtime))]
          )
        , ( [H.text "Your side"]
          , \t -> [H.text <| if t.bettorIsASkeptic then "it won't happen" else "it will happen"]
          )
        , ( [H.text "You staked"]
          , \t -> [H.text <| Utils.formatCents t.bettorStakeCents]
          )
        , ( [Utils.renderUser prediction.creator, H.text "'s stake"]
          , \t -> [H.text <| Utils.formatCents t.creatorStakeCents]
          )
        ]
        trades
      ]
  in
    case Utils.currentResolution prediction of
      Pb.ResolutionYes ->
        H.span []
        [ H.text "The predicted event happened: "
        , Utils.b <| formatYouWin -(getTotalCreatorWinnings True trades) ++ "!"
        , allTradesDetails
        ]
      Pb.ResolutionNo ->
        H.span []
        [ H.text "The predicted event didn't happen: "
        , Utils.b <| formatYouWin -(getTotalCreatorWinnings False trades) ++ "!"
        , allTradesDetails
        ]
      Pb.ResolutionInvalid ->
        H.span []
        [ H.text <| "If it happens, " ++ formatYouWin -(getTotalCreatorWinnings True trades)
        , H.text <| "; if not, " ++ formatYouWin -(getTotalCreatorWinnings False trades)
        , H.text "."
        , allTradesDetails
        ]
      Pb.ResolutionNoneYet ->
        H.span []
        [ H.text <| "If it happens, " ++ formatYouWin -(getTotalCreatorWinnings True trades)
        , H.text <| "; if not, " ++ formatYouWin -(getTotalCreatorWinnings False trades)
        , H.text "."
        , allTradesDetails
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
    headerRow = H.tr [] <| List.map (\(header, _) -> H.th [HA.scope "col"] header) columns
    dataRows = List.map (\x -> H.tr [] (List.map (\(_, toTd) -> H.td [] (toTd x)) columns)) xs
  in
  H.table (HA.class "table" :: tableAttrs)
  [ H.thead [] [headerRow]
  , H.tbody [] dataRows
  ]

viewEmbedInfo : Model -> Html Msg
viewEmbedInfo model =
  let
    prediction = Utils.must "must have loaded prediction being viewed" <| Dict.get model.predictionId model.globals.serverState.predictions
    allFormats = [EmbedHtml, EmbedMarkdown]
    displayNameToFormat s = Utils.must ("somehow got input " ++ s) <| List.head <| List.filter (formatDisplayName >> (==) s) allFormats
    allContentTypes = [Link, Image]
    displayNameToContentType s = Utils.must ("somehow got input " ++ s) <| List.head <| List.filter (contentTypeDisplayName >> (==) s) allContentTypes
    allColors = [DarkGreen, DarkBlue, Red, Black, White]
    displayNameToColor s = Utils.must ("somehow got input " ++ s) <| List.head <| List.filter (imageColorDisplayName >> (==) s) allColors
    allFontSizes = [SixPt, EightPt, TenPt, TwelvePt, FourteenPt, EighteenPt, TwentyFourPt]
    displayNameToFontSize s = Utils.must ("somehow got input " ++ s) <| List.head <| List.filter (imageFontSizeDisplayName >> (==) s) allFontSizes

    dropdown : (a -> EmbeddingFields -> EmbeddingFields) -> List a -> a -> (a -> String) -> Html Msg
    dropdown updateEmbedding options selected toDisplayName =
      let mustFromDisplayName s = options |> List.filter (\o -> toDisplayName o == s) |> List.head |> Utils.must ("somehow got input " ++ s) in
      options
      |> List.map (\opt -> H.option [HA.selected (opt == selected), HA.value (toDisplayName opt)] [H.text (toDisplayName opt)])
      |> H.select
          [ HA.class "form-select py-0 ps-0 d-inline-block w-auto"
          , HE.onInput (\s -> SetEmbedding (model.shareEmbedding |> updateEmbedding (mustFromDisplayName s)))
          ]
  in
    H.form []
    [ H.div []
      [ dropdown (\format embedding -> {embedding | format = format}) allFormats model.shareEmbedding.format formatDisplayName
      , dropdown (\contentType embedding -> {embedding | contentType = contentType}) allContentTypes model.shareEmbedding.contentType contentTypeDisplayName
      , case model.shareEmbedding.contentType of
          Link -> H.text ""
          Image -> dropdown (\newColor embedding -> {embedding | color = newColor}) allColors model.shareEmbedding.color imageColorDisplayName
      , case model.shareEmbedding.contentType of
          Link -> H.text ""
          Image -> dropdown (\newSize embedding -> {embedding | fontSize = newSize}) allFontSizes model.shareEmbedding.fontSize imageFontSizeDisplayName
      ]
    , H.div []
      [ CopyWidget.view Copy (embeddingCode model.globals.httpOrigin model.predictionId (mustPrediction model) model.shareEmbedding)
      , H.text " renders as "
      , embeddingPreview model.globals.httpOrigin model.predictionId (mustPrediction model) model.shareEmbedding
      , case model.shareEmbedding.contentType of
          Link -> H.text ""
          Image -> H.div [HA.class " mx-3 my-1 text-secondary"] [H.small [] [H.text " (This image's main advantage over a bare link is that it will always show the current state of the prediction, e.g. whether it's resolved and how much people have bet against you.)"]]
      ]
    ]

viewWhatIsThis : PredictionId -> Pb.UserPredictionView -> Html msg
viewWhatIsThis predictionId prediction =
  H.details [HA.class "mx-3"]
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
      , H.text <| ", and they know and trust you, and you disagree with them on this prediction, then "
      , H.a [HA.href <| "/login?dest=" ++ Utils.pathToPrediction predictionId] [H.text "log in"]
      , H.text " to bet against them!"
      ]
  , H.hr [] []
  , H.strong [] [H.text "But... why would you do this?"]
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

updateAuthWidget : AuthWidgetLoc -> (AuthWidget.State -> AuthWidget.State) -> Model -> Model
updateAuthWidget loc f model =
  case loc of
    Navbar -> { model | navbarAuth = model.navbarAuth |> f }
    Inline -> { model | authWidget = model.authWidget |> f }

update : Msg -> Model -> ( Model , Cmd Msg )
update msg model =
  case msg of
    SetAuthWidget loc widgetState ->
      ( updateAuthWidget loc (always widgetState) model , Cmd.none )
    SetEmailWidget widgetState ->
      ( { model | emailSettingsWidget = widgetState } , Cmd.none )
    SendInvitation ->
      ( { model | sendInvitationStatus = AwaitingResponse }
      , let req = {recipient=(mustPrediction model).creator} in API.postSendInvitation (SendInvitationFinished req) req
      )
    SendInvitationFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSendInvitationResponse req res
                , sendInvitationStatus = case API.simplifySendInvitationResponse res of
                    Ok _ -> Succeeded
                    Err e -> Failed e
                }
      , Cmd.none
      )
    LogInUsername loc widgetState req ->
      ( updateAuthWidget loc (always widgetState) model
      , API.postLogInUsername (LogInUsernameFinished loc req) req
      )
    LogInUsernameFinished loc req res ->
      ( updateAuthWidget loc (AuthWidget.handleLogInUsernameResponse res) { model | globals = model.globals |> Globals.handleLogInUsernameResponse req res }
      , case API.simplifyLogInUsernameResponse res of
          Ok _ -> navigate <| Nothing
          Err _ -> Cmd.none
      )
    RegisterUsername loc widgetState req ->
      ( updateAuthWidget loc (always widgetState) model
      , API.postRegisterUsername (RegisterUsernameFinished loc req) req
      )
    RegisterUsernameFinished loc req res ->
      ( updateAuthWidget loc (AuthWidget.handleRegisterUsernameResponse res) { model | globals = model.globals |> Globals.handleRegisterUsernameResponse req res }
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
    SignOut loc widgetState req ->
      ( updateAuthWidget loc (always widgetState) model
      , API.postSignOut (SignOutFinished loc req) req
      )
    SignOutFinished loc req res ->
      ( updateAuthWidget loc (AuthWidget.handleSignOutResponse res) { model | globals = model.globals |> Globals.handleSignOutResponse req res }
      , case API.simplifySignOutResponse res of
          Ok _ -> navigate <| Just "/"
          Err _ -> Cmd.none
      )
    Stake cents ->
      ( { model | stakeStatus = AwaitingResponse }
      , let req = {predictionId=model.predictionId, bettorIsASkeptic=model.bettorIsASkeptic, bettorStakeCents=cents} in API.postStake (StakeFinished req) req
      )
    StakeFinished req res ->
      ( case API.simplifyStakeResponse res of
          Ok prediction ->
            { model | globals = model.globals |> Globals.handleStakeResponse req res
                    , stakeStatus = Succeeded
            } |> updateBettorInputFields prediction
          Err e ->
            { model | globals = model.globals |> Globals.handleStakeResponse req res
                    , stakeStatus = Failed e
            }
      , Cmd.none
      )
    QueueStake cents ->
      ( { model | stakeStatus = AwaitingResponse }
      , let req = {predictionId=model.predictionId, bettorIsASkeptic=model.bettorIsASkeptic, bettorStakeCents=cents} in API.postQueueStake (QueueStakeFinished req) req
      )
    QueueStakeFinished req res ->
      ( case API.simplifyQueueStakeResponse res of
          Ok prediction ->
            { model | globals = model.globals |> Globals.handleQueueStakeResponse req res
                    , stakeStatus = Succeeded
            } |> updateBettorInputFields prediction
          Err e ->
            { model | globals = model.globals |> Globals.handleQueueStakeResponse req res
                    , stakeStatus = Failed e
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
      ( { model | bettorIsASkeptic = bettorIsASkeptic , stakeStatus = Unstarted }
      , Cmd.none
      )
    SetStakeField value ->
      ( { model | stakeField = value , stakeStatus = Unstarted }
      , Cmd.none
      )
    SetEmbedding value ->
      ( { model | shareEmbedding = value }
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
