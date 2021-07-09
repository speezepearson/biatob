port module Elements.Prediction exposing (..)

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
  , resolveNotesField : String
  , resolveStatus : RequestStatus
  , stakeField : String
  , bettorSide : Utils.BetSide
  , stakeStatus : RequestStatus
  , sendInvitationStatus : RequestStatus
  , setTrustedStatus : RequestStatus
  , shareEmbedding : EmbeddingFields
  }

type alias EmbeddingFields =
  { format : EmbeddingFormat
  , contentType : EmbeddingContentType
  , fontSize : EmbeddedImageFontSize
  , style : EmbeddedImageStyle
  }

type EmbeddedImageStyle = PlainLink | LessWrong | Red | DarkGreen | DarkBlue | Black | White
imageStyleIdString color = case color of
  PlainLink -> "plainlink"
  LessWrong -> "lesswrong"
  Red -> "red"
  DarkGreen -> "darkgreen"
  DarkBlue -> "darkblue"
  Black -> "black"
  White -> "white"
imageStyleDisplayName color = case color of
  PlainLink -> "plain link"
  LessWrong -> "LessWrong"
  Red -> "red"
  DarkGreen -> "green"
  DarkBlue -> "blue"
  Black -> "black"
  White -> "white"
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

embeddedLinkText : Pb.UserPredictionView -> String
embeddedLinkText prediction =
  let
    certainty = Utils.mustPredictionCertainty prediction
  in
    "(bet: "
    ++ Utils.formatCents (prediction.maximumStakeCents // 100 * 100)
    ++ " at "
    ++ String.fromInt (round <| certainty.low * 100)
    ++ (if certainty.high < 1 then
          "-"
          ++ String.fromInt (round <| certainty.high * 100)
          ++ ""
        else
          ""
       )
    ++ "%)"
embeddedImageUrl : String -> PredictionId -> EmbeddedImageStyle -> EmbeddedImageFontSize -> String
embeddedImageUrl httpOrigin predictionId style size =
  httpOrigin
  ++ Utils.pathToPrediction predictionId
  ++ "/embed-" ++ imageStyleIdString style
  ++ "-" ++ imageFontSizeIdString size
  ++ ".png"
embeddedImageStyles : EmbeddingFields -> List (String, String)
embeddedImageStyles _ =
  [ ("max-height", "1.5em")
  ]
embeddingPreview : String -> PredictionId -> Pb.UserPredictionView -> EmbeddingFields -> Html msg
embeddingPreview httpOrigin predictionId prediction fields =
  let
    linkUrl = httpOrigin ++ Utils.pathToPrediction predictionId
    text = embeddedLinkText prediction
  in
  case fields.contentType of
    Link -> H.a [HA.href linkUrl] [H.text text]
    Image ->
      H.a [HA.href linkUrl]
        [ H.img
          ( [ HA.alt text
            , HA.src <| embeddedImageUrl httpOrigin predictionId fields.style fields.fontSize
            ]
            ++ (embeddedImageStyles fields |> List.map (\(k,v) -> HA.style k v))
          )
          []
        ]

embeddingCode : String -> PredictionId -> Pb.UserPredictionView -> EmbeddingFields -> String
embeddingCode httpOrigin predictionId prediction fields =
  let
    linkUrl = httpOrigin ++ Utils.pathToPrediction predictionId
    text = embeddedLinkText prediction
  in
  case fields.contentType of
    Link ->
      case fields.format of
        EmbedHtml -> "<a href=\"" ++ linkUrl ++ "\">" ++ text ++ "</a>"
        EmbedMarkdown -> "[" ++ text ++ "](" ++ linkUrl ++ ")"
    Image ->
      let
        imageUrl = embeddedImageUrl httpOrigin predictionId fields.style fields.fontSize
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
  | SetBettorSide Utils.BetSide
  | SetStakeField String
  | SetEmbedding EmbeddingFields
  | SetResolveNotesField String
  | Copy String
  | Tick Time.Posix
  | AuthWidgetExternallyModified AuthWidget.DomModification
  | Ignore

init : JD.Value -> ( Model, Cmd Msg )
init flags =
  ( initInternal
      (JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags")
      (Utils.mustDecodeFromFlags JD.string "predictionId" flags)
  , Cmd.none
  )

initInternal : Globals.Globals -> PredictionId -> Model
initInternal globals predictionId =
  let
    prediction = Utils.must "must have loaded prediction being viewed" <| Dict.get predictionId globals.serverState.predictions
  in
  { globals = globals
  , navbarAuth = AuthWidget.init
  , authWidget = AuthWidget.init
  , predictionId = predictionId
  , emailSettingsWidget = EmailSettingsWidget.init
  , resolveNotesField = ""
  , resolveStatus = Unstarted
  , stakeStatus = Unstarted
  , setTrustedStatus = Unstarted
  , sendInvitationStatus = Unstarted
  , stakeField = "10"
  , bettorSide = Utils.Skeptic
  , shareEmbedding = { format = EmbedHtml, contentType = Image , style = PlainLink , fontSize = FourteenPt }
  } |> updateBettorInputFields prediction

updateBettorInputFields : Pb.UserPredictionView -> Model -> Model
updateBettorInputFields prediction model =
  let
    newSide =
      if isSideAvailable Utils.Believer prediction && not (isSideAvailable Utils.Skeptic prediction) then
        Utils.Believer
      else
        Utils.Skeptic
  in
  { model | stakeField = min 1000 (getBetParameters newSide prediction).maxBettorStake |> Utils.formatCents |> String.replace "$" ""
          , bettorSide = newSide
  }

mustPrediction : Model -> Pb.UserPredictionView
mustPrediction model =
  Utils.must "must have loaded prediction being viewed" <| Dict.get model.predictionId model.globals.serverState.predictions

view : Model -> Browser.Document Msg
view model =
  let
    prediction = mustPrediction model
  in
  { title = String.concat <| getTitleTextChunks model.globals.timeZone prediction
  , body =
    [ Navbar.view
        { setState = SetAuthWidget Navbar
        , logInUsername = LogInUsername Navbar
        , register = RegisterUsername Navbar
        , signOut = SignOut Navbar
        , ignore = Ignore
        , username = Globals.getOwnUsername model.globals
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
      , emailInvitationAcceptanceNotifications = True
      , invitations = Dict.empty
      , loginType = Just (Pb.LoginTypeLoginPassword {salt=emptyBytes, scrypt=emptyBytes})
      , relationships = Dict.singleton prediction.creator (Just {trustsYou=True, trustedByYou=True})
      }

    newGlobals =
      globals
      |> Globals.handleGetPredictionResponse {predictionId="my-predid"} (Ok {getPredictionResult=Just <| Pb.GetPredictionResultPrediction prediction})
      |> Globals.handleSignOutResponse {} (Ok {})
      |> Globals.handleLogInUsernameResponse {username="__previewer__", password=""} (Ok {logInUsernameResult=Just <| Pb.LogInUsernameResultOk {token=Just mockToken, userInfo=Just mockSettings}})
  in
  initInternal newGlobals "my-predid"
  |> viewBody
  |> H.div []
  |> H.map (\_ -> ())

predictionAllowsEmailInvitation : Model -> Bool
predictionAllowsEmailInvitation model =
  (mustPrediction model).allowEmailInvitations

pendingEmailInvitation : Model -> Bool
pendingEmailInvitation model =
  case Globals.getUserInfo model.globals of
    Just settings ->
      Dict.member
        (mustPrediction model).creator
        settings.invitations
    _ -> False


userEmailAddress : Model -> Maybe String
userEmailAddress model =
  case Globals.getUserInfo model.globals of
    Just settings -> case settings.email of
      Just efs -> case efs.emailFlowStateKind of
        Just (Pb.EmailFlowStateKindVerified addr) -> Just addr
        _ -> Nothing
      _ -> Nothing
    _ -> Nothing

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

getBetParameters : Utils.BetSide -> Pb.UserPredictionView -> { remainingCreatorStake : Cents , creatorStakeFactor : Float , maxBettorStake : Cents }
getBetParameters side prediction =
  let
    certainty = Utils.mustPredictionCertainty prediction
    creatorStakeFactor = case side of
      Utils.Skeptic -> certainty.low / (1 - certainty.low)
      Utils.Believer -> (1 - certainty.high) / certainty.high
    queuedCreatorStake =
      prediction.yourQueuedTrades
      |> List.filter (.bettorIsASkeptic >> Utils.betSideFromIsSkeptical >> (==) side)
      |> List.map .creatorStakeCents
      |> List.sum
    remainingCreatorStake = case side of
      Utils.Skeptic -> (prediction.remainingStakeCentsVsSkeptics - queuedCreatorStake)
      Utils.Believer -> (prediction.remainingStakeCentsVsBelievers - queuedCreatorStake)
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
    }

isSideAvailable : Utils.BetSide -> Pb.UserPredictionView -> Bool
isSideAvailable prediction side =
  (getBetParameters prediction side).maxBettorStake > 0

getPrereqsForStaking : Model -> PrereqsForStaking
getPrereqsForStaking model =
  let
    prediction = mustPrediction model
    creator = prediction.creator
  in
  if Globals.isSelf model.globals creator then
    IsCreator
  else if not (isSideAvailable Utils.Skeptic prediction) && not (isSideAvailable Utils.Believer prediction) then
    CreatorStakeExhausted
  else if not (Globals.isLoggedIn model.globals) then
    NeedsAccount
  else if Globals.getTrustRelationship model.globals creator == Globals.Friends then
    CanAlreadyStake
  else if Globals.getRelationship model.globals creator |> Maybe.map (\r -> r.trustsYou && not r.trustedByYou) |> Maybe.withDefault False then
    NeedsToSetTrusted
  else if Globals.getRelationship model.globals creator |> Maybe.map (not << .trustedByYou) |> Maybe.withDefault False |> (&&) (not (predictionAllowsEmailInvitation model)) then
    NeedsToSetTrusted
  else if predictionAllowsEmailInvitation model then
    if pendingEmailInvitation model then
      NeedsToWaitForInvitation
    else if userEmailAddress model /= Nothing then
      NeedsToSendEmailInvitation
    else
      NeedsEmailAddress
  else
    NeedsToTextUserPageLink

viewYourStake : Maybe Username -> Time.Zone -> Pb.UserPredictionView -> Html Msg
viewYourStake self timeZone prediction =
  if List.isEmpty prediction.yourTrades then
    H.text ""
  else
    H.div []
    [ H.h4 [HA.class "text-center"] [H.text "Your stake"]
    , H.div [HA.class "mx-lg-5"]
      [ if self == Just prediction.creator then
          viewTradesAsCreator timeZone prediction
        else
          viewTradesAsBettor timeZone prediction prediction.yourTrades
      ]
    , H.hr [HA.class "my-4"] []
    ]
viewYourQueuedStake : Maybe Username -> Time.Zone -> Pb.UserPredictionView -> Html Msg
viewYourQueuedStake self timeZone prediction =
  if List.isEmpty prediction.yourQueuedTrades then
    H.text ""
  else if self == Just prediction.creator then
    H.text ""
  else
    H.div []
    [ H.h4 [HA.class "text-center"] [H.text "Your queued stake"]
    , H.div [HA.class "mx-lg-5"]
      [ H.div [HA.class "text-center text-secondary"]
        [ H.text " (from bets that I'll apply once "
        , Utils.renderUser prediction.creator
        , H.text " tells me they trust you)"
        ]
      , H.br [] []
      , viewTradesAsBettor timeZone prediction
        <| List.map
            (\qt -> {bettor=qt.bettor, bettorIsASkeptic=qt.bettorIsASkeptic, bettorStakeCents=qt.bettorStakeCents, creatorStakeCents=qt.creatorStakeCents, transactedUnixtime=qt.enqueuedAtUnixtime})
            prediction.yourQueuedTrades
      ]
    , H.hr [HA.class "my-4"] []
    ]
viewBody : Model -> List (Html Msg)
viewBody model =
  let
    prediction = mustPrediction model
    isOwnPrediction = Globals.isSelf model.globals prediction.creator
    maybeOrYouCouldSwapUserPages =
      case Globals.getOwnUsername model.globals of
        Nothing -> H.text ""
        Just self ->
          H.small [] [H.details [HA.class "mt-2 text-secondary"]
          [ H.summary [] [H.text "But I hate giving out my email address!"]
          , H.text "Well, if you trust ", Utils.renderUser prediction.creator, H.text ", you presumably have some way to communicate with them over SMS or email or whatever. You could send them a link to "
          , H.a [HA.href <| Utils.pathToUserPage self] [H.text "your user page"]
          , H.text " and ask them to mark you as trusted."
          ]]
  in
  [ H.h2 [HA.id "prediction-title", HA.class "text-center"] <| List.map H.text <| getTitleTextChunks model.globals.timeZone prediction
  , H.hr [] []
  , H.div [HA.class "row row-cols-12"]
    [ H.div [HA.class "col-md-4"] [viewSummaryTable model.globals.now model.globals.timeZone prediction]
    , H.div [HA.class "col-md-8"]
      [ viewYourStake (Globals.getOwnUsername model.globals) model.globals.timeZone prediction
      , viewYourQueuedStake (Globals.getOwnUsername model.globals) model.globals.timeZone prediction
      , case getPrereqsForStaking model of
          IsCreator ->
            H.div [HA.id "resolve-section"]
            [ H.h4 [HA.class "text-center"] [H.text "Resolve this prediction"]
            , viewResolutionForm model.resolveNotesField model.resolveStatus (Utils.currentResolution prediction)
            , H.hr [HA.style "margin" "2em 0"] []
            , H.text "If you want to link to your prediction, here's some code you could copy-paste:"
            , viewEmbedInfo model.globals.httpOrigin model.shareEmbedding model.predictionId prediction
            ]
          CreatorStakeExhausted ->
            H.div [HA.id "make-a-bet-section", HA.class "text-secondary"]
            [ H.h4 [HA.class "text-center"] [H.text "Make a bet"]
            , Utils.renderUser prediction.creator
            , H.text " has already accepted so many bets that they've reached their maximum risk of "
            , H.text <| Utils.formatCents prediction.maximumStakeCents
            , H.text "! So, sadly, no further betting is possible."
            ]
          NeedsAccount ->
            H.div [HA.id "make-a-bet-section"]
            [ H.h4 [HA.class "text-center"] [H.text "Make a bet"]
            , H.text " Only people with accounts can bet!"
            , H.br [] []
            , H.small [HA.class "mx-3 text-secondary"]
              [ H.text " Otherwise, how will "
              , Utils.renderUser prediction.creator
              , H.text " know who you are?"
              ]
            , H.div [HA.class "m-1 mx-4"]
              [ AuthWidget.view
                { setState = SetAuthWidget Inline
                , logInUsername = LogInUsername Inline
                , register = RegisterUsername Inline
                , signOut = SignOut Inline
                , ignore = Ignore
                , username = Globals.getOwnUsername model.globals
                , id = "inline-auth"
                }
                model.authWidget
              ]
            ]
          CanAlreadyStake ->
            H.div [HA.id "make-a-bet-section"]
            [ H.h4 [HA.class "text-center"] [H.text "Make a bet"]
            , viewStakeWidget QueueingUnnecessary model.stakeField model.stakeStatus model.bettorSide prediction
            ]
          NeedsToSetTrusted ->
            H.div [HA.id "make-a-bet-section", HA.class "text-center"]
            [ H.h4 [] [H.text "Make a bet"]
            , H.button
              [ HA.disabled (model.setTrustedStatus == AwaitingResponse)
              , HE.onClick SetCreatorTrusted
              , HA.class "btn btn-sm btn-primary"
              ]
              [ H.text <| "I know @" ++ prediction.creator ++ ", and I trust them to pay up"]
            , case model.setTrustedStatus of
                Unstarted -> H.text ""
                AwaitingResponse -> H.text ""
                Succeeded -> Utils.greenText "(success!)"
                Failed e -> Utils.redText e
            ]
          NeedsToWaitForInvitation ->
            H.div [HA.id "make-a-bet-section"]
            [ H.h4 [HA.class "text-center"] [H.text "Make a bet"]
            , viewStakeWidget
              ( QueueingNecessary <| H.span [] [H.text "I've emailed them to ask, but they haven't responded yet."])
              model.stakeField model.stakeStatus model.bettorSide prediction
            ]
          NeedsToSendEmailInvitation ->
            H.div [HA.id "make-a-bet-section"]
            [ H.h4 [HA.class "text-center"] [H.text "Make a bet"]
            , H.div [HA.class "text-center"]
              [ H.button
                [ HA.disabled (model.sendInvitationStatus == AwaitingResponse)
                , HE.onClick SendInvitation
                , HA.class "btn btn-sm py-0 btn-primary"
                ]
                [ H.text <| "Ask @" ++ prediction.creator ++ " if they trust me"
                ]
              , H.text " "
              , case model.sendInvitationStatus of
                  Unstarted -> H.text ""
                  AwaitingResponse -> H.text ""
                  Succeeded -> H.text "Success!"
                  Failed e -> Utils.redText e
              ]
            , H.div [HA.class "text-center text-secondary"]
              [ H.text "This will require sharing your email address ("
              , H.code [HA.style "color" "inherit"] [ H.text <| Utils.must "must have email address, else would take the NeedsEmailAddress branch" <| userEmailAddress model ]
              , H.text ") with them."
              ]
            , maybeOrYouCouldSwapUserPages
            ]
          NeedsEmailAddress ->
            H.div [HA.id "make-a-bet-section"]
            [ H.p []
              [ H.h4 [HA.class "text-center"] [H.text "Make a bet"]
              , H.text "You need an email address in order to bet!"
              , H.br [] []
              , H.small [HA.class "mx-3 text-secondary"]
                [ H.text " I need it so I can identify you to "
                , Utils.renderUser prediction.creator
                , H.text " when I ask them whether they trust you."
                ]
              , H.div [HA.class "m-1 mx-4"]
                [ EmailSettingsWidget.view
                  { setState = SetEmailWidget
                  , ignore = Ignore
                  , setEmail = SetEmail
                  , updateSettings = UpdateSettings
                  , userInfo = Utils.must "checked that user is logged in" (Globals.getUserInfo model.globals)
                  , showAllEmailSettings = False
                  }
                  model.emailSettingsWidget
                ]
              , maybeOrYouCouldSwapUserPages
              ]
            ]
          NeedsToTextUserPageLink ->
            H.div [HA.id "make-a-bet-section"]
            [ H.p []
              [ H.h4 [HA.class "text-center"] [H.text "Make a bet"]
              , viewStakeWidget
                ( QueueingNecessary <|
                  H.span []
                  [ H.span [HA.class "text-danger"]
                    [ H.text "You'll need to contact them over SMS/IM/email/whatever,"
                    ]
                  , H.text " send them a link to "
                  , H.a [HA.href <| Utils.pathToUserPage <| Utils.must "checked user is logged in" <| Globals.getOwnUsername model.globals] [H.text "your user page"]
                  , H.text ", and ask them to mark you as trusted. Sorry it's such a hassle. I'd normally offer to ask them for you, but they disabled that option."
                  ]
                )
                model.stakeField model.stakeStatus model.bettorSide prediction
              ]
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

viewResolutionForm : String -> RequestStatus -> Pb.Resolution -> Html Msg
viewResolutionForm notesField resolveStatus currentResolution =
  let
    working = (resolveStatus == AwaitingResponse)
    notesFieldBlock =
      H.div [HA.class "mx-4 my-4"]
      [ H.text "Explanation / supporting evidence:"
      , H.textarea
        [ HA.class "form-control"
        , HA.id "resolveNotesField"
        , HE.onInput SetResolveNotesField
        , HA.value notesField
        , HA.disabled (working)
        ]
        []
      ]
    mistakeInfo : String -> Html Msg
    mistakeInfo s =
      H.span [HA.style "color" "gray"]
        [ H.text "You said that this "
        , H.text s
        , H.text ". If that was a mistake, you can always "
        , H.button
          [ HA.disabled working
          , HE.onClick <| Resolve Pb.ResolutionNoneYet
          , HA.class "btn btn-sm py-0 btn-outline-secondary"
          ]
          [ H.text "un-resolve it." ]
        , notesFieldBlock
        ]
  in
    H.div []
    [ case currentResolution of
        Pb.ResolutionYes ->
          mistakeInfo "HAPPENED"
        Pb.ResolutionNo ->
          mistakeInfo "DID NOT HAPPEN"
        Pb.ResolutionInvalid ->
          mistakeInfo "was INVALID"
        Pb.ResolutionNoneYet ->
          H.div []
          [ notesFieldBlock
          , H.div [HA.class "my-2"]
            [ H.button [HA.class "btn btn-sm py-0 btn-outline-primary   mx-1", HA.disabled working, HE.onClick <| Resolve Pb.ResolutionYes    ] [H.text "It happened!"]
            , H.button [HA.class "btn btn-sm py-0 btn-outline-primary   mx-1", HA.disabled working, HE.onClick <| Resolve Pb.ResolutionNo     ] [H.text "It didn't happen!"]
            , H.button [HA.class "btn btn-sm py-0 btn-outline-secondary mx-1", HA.disabled working, HE.onClick <| Resolve Pb.ResolutionInvalid] [H.text "Invalid prediction / impossible to resolve"]
            ]
          ]
        Pb.ResolutionUnrecognized_ _ ->
          H.span []
          [ H.span [HA.style "color" "red"] [H.text "unrecognized resolution"]
          , mistakeInfo "??????"
          ]
    , H.text " "
    , case resolveStatus of
        Unstarted -> H.text ""
        AwaitingResponse -> H.text ""
        Succeeded -> Utils.greenText "Resolution updated!"
        Failed e -> Utils.redText e
    ]

willWontDropdownOnInput : String -> Msg
willWontDropdownOnInput s =
  case s of
    "won't" -> SetBettorSide Utils.Skeptic
    "will" -> SetBettorSide Utils.Believer
    _ -> Ignore |> Debug.log ("invalid value" ++ Debug.toString s ++ "for skepticism dropdown")
viewWillWontDropdown : Utils.BetSide -> Pb.UserPredictionView -> Html Msg
viewWillWontDropdown side prediction =
  if not (isSideAvailable Utils.Believer prediction) then
    Utils.b "won't"
  else if not (isSideAvailable Utils.Skeptic prediction) then
    Utils.b "will"
  else
    H.select
      [ HE.onInput willWontDropdownOnInput
      , HA.class "form-select form-select-sm d-inline-block w-auto"
      ]
      [ H.option [HA.value "won't", HA.selected <| side == Utils.Skeptic] [H.text "won't"]
      , H.option [HA.value "will", HA.selected <| side == Utils.Believer] [H.text "will"]
      ]

type Bettability
  = QueueingNecessary (Html Msg)
  | QueueingUnnecessary
viewStakeWidget : Bettability -> String -> RequestStatus -> Utils.BetSide -> Pb.UserPredictionView -> Html Msg
viewStakeWidget bettability stakeField requestStatus side prediction =
  let

    betParameters = getBetParameters side prediction
    stakeCents = case String.toFloat stakeField of
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
  H.div [HA.class "mx-lg-5 my-3"]
    [ H.text " Bet $"
    , H.input
        [ HA.style "width" "7em"
        , HA.type_"number", HA.min "0", HA.max (toFloat betParameters.maxBettorStake / 100 + epsilon |> String.fromFloat), HA.step "any"
        , HA.class "form-control form-control-sm d-inline-block"
        , HA.id "stakeField"
        , HE.onInput SetStakeField
        , HA.value stakeField
        , HA.class (if isOk stakeCents then "" else "is-invalid")
        ]
        []
    , H.text " that this "
    , viewWillWontDropdown side prediction
    , H.text <| " happen, against " ++ prediction.creator ++ "'s "
    , Utils.b (stakeCents |> Result.map (toFloat >> (*) betParameters.creatorStakeFactor >> floor >> Utils.formatCents) |> Result.withDefault "???")
    , H.text " that it "
    , H.text <| case side of
        Utils.Skeptic -> "will"
        Utils.Believer -> "won't"
    , H.text ". "
    , let
        primarity = case bettability of
          QueueingNecessary _ -> "btn-outline-secondary"
          QueueingUnnecessary -> "btn-primary"
      in
      H.button
        (HA.class ("btn btn-sm py-0 " ++ primarity) :: case stakeCents of
          Ok 0 ->
            [ HA.disabled True ]
          Ok cents ->
            [ HE.onClick <| case bettability of
                QueueingNecessary _ -> QueueStake cents
                QueueingUnnecessary -> Stake cents
            , HA.disabled (requestStatus == AwaitingResponse)
            ]
          Err _ ->
            [ HA.disabled True ]
        )
        [ H.text <| case bettability of
            QueueingNecessary _ -> "Queue, pending @" ++ prediction.creator ++ "'s approval"
            QueueingUnnecessary -> "Commit"
        ]
    , case requestStatus of
        Unstarted -> H.text ""
        AwaitingResponse -> H.text ""
        Succeeded -> Utils.greenText "Success!"
        Failed e -> Utils.redText e
    , case bettability of
        QueueingNecessary instructions ->
          H.div [HA.class "text-secondary"]
          [ H.text "Your queued bet won't take effect until "
          , Utils.renderUser prediction.creator
          , H.text " tells me they trust you. "
          , instructions
          ]
        QueueingUnnecessary -> H.text ""
    , case side of
        Utils.Skeptic ->
          if prediction.remainingStakeCentsVsSkeptics /= prediction.maximumStakeCents then
            viewReducedStakeLimitExplanation {creator=prediction.creator, maxExposure=prediction.maximumStakeCents, remaining=prediction.remainingStakeCentsVsSkeptics}
          else
            H.text ""
        Utils.Believer ->
          if prediction.remainingStakeCentsVsBelievers /= prediction.maximumStakeCents then
            viewReducedStakeLimitExplanation {creator=prediction.creator, maxExposure=prediction.maximumStakeCents, remaining=prediction.remainingStakeCentsVsBelievers}
          else
            H.text ""
    , H.div [HA.class "invalid-feedback"] [viewError stakeCents]
    ]

viewReducedStakeLimitExplanation : {creator:Username, maxExposure:Cents, remaining:Cents} -> Html Msg
viewReducedStakeLimitExplanation {creator, maxExposure, remaining} =
  H.div [HA.class "text-secondary reduced-stake-limit-explanation"]
  <|  if remaining == 0 then
        [ Utils.renderUser creator
        , H.text " has reached their limit of "
        , H.text <| Utils.formatCents maxExposure
        , H.text " on this bet, and isn't willing to risk losing any more!"
        ]
      else
        [ H.text <| "Only "
        , H.text <| Utils.formatCents remaining
        , H.text <| " of "
        , Utils.renderUser creator
        , H.text <| "'s initial stake remains, since they've already accepted some bets."
        ]


getTitleTextChunks : Time.Zone -> Pb.UserPredictionView -> List String
getTitleTextChunks timeZone prediction =
  [ "Prediction: by "
  , (Utils.dateStr timeZone <| Utils.unixtimeToTime prediction.resolvesAtUnixtime)
  , ", "
  , prediction.prediction
  ]


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
          , ( [H.text "Notes"]
            , \event -> [ H.text event.notes ]
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

viewEmbedInfo : String -> EmbeddingFields -> PredictionId -> Pb.UserPredictionView -> Html Msg
viewEmbedInfo httpOrigin fields predictionId prediction =
  let
    allFormats = [EmbedHtml, EmbedMarkdown]
    allContentTypes = [Link, Image]
    allStyles = [PlainLink, LessWrong, DarkGreen, DarkBlue, Red, Black, White]
    allFontSizes = [SixPt, EightPt, TenPt, TwelvePt, FourteenPt, EighteenPt, TwentyFourPt]

    dropdown : List (H.Attribute Msg) -> (a -> EmbeddingFields -> EmbeddingFields) -> List a -> a -> (a -> String) -> Html Msg
    dropdown attrs updateEmbedding options selected toDisplayName =
      let mustFromDisplayName s = options |> List.filter (\o -> toDisplayName o == s) |> List.head |> Utils.must ("somehow got input " ++ s) in
      options
      |> List.map (\opt -> H.option [HA.selected (opt == selected), HA.value (toDisplayName opt)] [H.text (toDisplayName opt)])
      |> H.select
          ( [ HA.class "form-select py-0 ps-0 d-inline-block w-auto"
            , HE.onInput (\s -> SetEmbedding (fields |> updateEmbedding (mustFromDisplayName s)))
            ]
            ++ attrs
          )
  in
    H.div [HA.class "embed-info"]
    [ H.div []
      [ dropdown [HA.class "embedding-format-field"] (\format embedding -> {embedding | format = format}) allFormats fields.format formatDisplayName
      , dropdown [HA.class "embedding-content-type-field"] (\contentType embedding -> {embedding | contentType = contentType}) allContentTypes fields.contentType contentTypeDisplayName
      , case fields.contentType of
          Link -> H.text ""
          Image -> dropdown [HA.class "embedding-style-field"] (\newStyle embedding -> {embedding | style = newStyle}) allStyles fields.style imageStyleDisplayName
      , case fields.contentType of
          Link -> H.text ""
          Image -> dropdown [HA.class "embedding-font-size-field"] (\newSize embedding -> {embedding | fontSize = newSize}) allFontSizes fields.fontSize imageFontSizeDisplayName
      ]
    , H.div []
      [ CopyWidget.view Copy (embeddingCode httpOrigin predictionId prediction fields)
      , H.text " renders as "
      , embeddingPreview httpOrigin predictionId prediction fields
      , case fields.contentType of
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
      , let req = {predictionId=model.predictionId, resolution=resolution, notes=model.resolveNotesField} in API.postResolve (ResolveFinished req) req
      )
    ResolveFinished req res ->
      ( { model | globals = model.globals |> Globals.handleResolveResponse req res
                , resolveStatus = case API.simplifyResolveResponse res of
                    Ok _ -> Succeeded
                    Err e -> Failed e
                , resolveNotesField = if isOk (API.simplifyResolveResponse res) then "" else model.resolveNotesField
        }
      , Cmd.none
      )
    SetCreatorTrusted ->
      ( { model | setTrustedStatus = AwaitingResponse }
      , let req = {who=(mustPrediction model).creator, trusted=True} in API.postSetTrusted (SetCreatorTrustedFinished req) req
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
          Ok _ -> navigate <| Nothing
          Err _ -> Cmd.none
      )
    Stake cents ->
      ( { model | stakeStatus = AwaitingResponse }
      , let req = {predictionId=model.predictionId, bettorIsASkeptic=Utils.betSideToIsSkeptical model.bettorSide, bettorStakeCents=cents} in API.postStake (StakeFinished req) req
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
      , let req = {predictionId=model.predictionId, bettorIsASkeptic=Utils.betSideToIsSkeptical model.bettorSide, bettorStakeCents=cents} in API.postQueueStake (QueueStakeFinished req) req
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
    SetBettorSide bettorSide ->
      ( { model | bettorSide = bettorSide , stakeStatus = Unstarted }
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
    SetResolveNotesField value ->
      ( { model | resolveNotesField = value }
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
