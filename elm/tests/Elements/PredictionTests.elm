module Elements.PredictionTests exposing (..)

import Expect
import Fuzz exposing (intRange, percentage)
import Html as H
import Html.Attributes as HA
import Time
import Test exposing (..)
import Test.Html.Event as HEM
import Test.Html.Query as HQ
import Test.Html.Selector as HS

import Globals
import Biatob.Proto.Mvp as Pb
import Elements.Prediction exposing (..)
import TestUtils as TU exposing (exampleGlobals)
import Elements.MyStakesTests exposing (exampleResolutionEvent)
import Utils
import Widgets.CopyWidget as CopyWidget
import Dict

exampleOrigin = "https://example.com"
examplePredictionId = "my-test-prediction"
exampleFields = {style=PlainLink, fontSize=TwelvePt, contentType=Link, format=EmbedHtml}

mockPrediction : Pb.UserPredictionView
mockPrediction =
  { prediction = "a thing will happen"
  , certainty = Just {low = 0.10 , high = 0.70}
  , maximumStakeCents = 10000
  , remainingStakeCentsVsBelievers = 10000
  , remainingStakeCentsVsSkeptics = 10000
  , createdUnixtime = 0
  , closesUnixtime = 100
  , specialRules = ""
  , creator = "creator"
  , resolution = Nothing
  , yourTrades = []
  , resolvesAtUnixtime = 200
  , yourFollowingStatus = Pb.PredictionFollowingNotFollowing
  }

exampleTrade : Pb.Trade
exampleTrade =
  { bettor = "bettor"
  , bettorIsASkeptic = False
  , bettorStakeCents = 7
  , creatorStakeCents = 13
  , transactedUnixtime = 0
  , state = Pb.TradeStateActive
  , updatedUnixtime = 0
  , notes = ""
  }
embeddedLinkTextTest : Test
embeddedLinkTextTest =
  describe "embeddedLinkText"
  [ test "with both low and high probs set" <|
    \() -> Expect.equal "(bet: $100 at 10-30%)"
          <| embeddedLinkText { mockPrediction | certainty = Just {low = 0.10 , high = 0.30} , maximumStakeCents = 10000 }
  , test "with only low prob set" <|
    \() -> Expect.equal "(bet: $100 at 10%)"
          <| embeddedLinkText { mockPrediction | certainty = Just {low = 0.10 , high = 1.00} , maximumStakeCents = 10000 }
  ]

embeddedImageUrlTest : Test
embeddedImageUrlTest =
  test "embeddedImageUrl" <|
  \() -> Expect.equal "https://example.com/p/my-test-prediction/embed-darkgreen-12pt.png"
        <| embeddedImageUrl "https://example.com" "my-test-prediction" DarkGreen TwelvePt

expectContains : String -> String -> Expect.Expectation
expectContains q s =
  Expect.true ("expected '" ++ s ++ "' to contain '" ++ q ++ "'")
  <| String.contains q s

embeddingCodeTest : Test
embeddingCodeTest =
  let
    prediction = { mockPrediction | certainty = Just {low = 0.10 , high = 1.00} , maximumStakeCents = 10000 }
  in
  describe "embeddingCode"
  [ describe "links"
    [ describe "HTML"
      [ test "contains link text" <|
        \() -> expectContains (">" ++ embeddedLinkText prediction ++ "<")
              <| embeddingCode exampleOrigin examplePredictionId prediction { exampleFields | contentType=Link, format=EmbedHtml}
      , test "links to prediction" <|
        \() -> expectContains " href=\"https://example.com/p/my-predid\""
              <| embeddingCode "https://example.com" "my-predid" prediction { exampleFields | contentType=Link, format=EmbedHtml}
      ]
    , describe "Markdown"
      [ test "contains link text" <|
        \() -> Expect.true ""
              <| String.startsWith ("[" ++ embeddedLinkText prediction ++ "]")
              <| embeddingCode exampleOrigin examplePredictionId prediction { exampleFields | contentType=Link, format=EmbedMarkdown}
      , test "links to prediction" <|
        \() -> expectContains "(https://example.com/p/my-predid)"
              <| embeddingCode "https://example.com" "my-predid" prediction { exampleFields | contentType=Link, format=EmbedMarkdown}
      ]
    ]
  , describe "images"
    [ describe "HTML"
      [ test "has alt link text" <|
        \() -> expectContains (" alt=\"" ++ embeddedLinkText prediction ++ "\"")
              <| embeddingCode exampleOrigin examplePredictionId prediction { exampleFields | contentType=Image, format=EmbedHtml}
      , test "links to prediction" <|
        \() -> expectContains " href=\"https://example.com/p/my-predid\""
              <| embeddingCode "https://example.com" "my-predid" prediction { exampleFields | contentType=Image, format=EmbedHtml}
      ]
    , describe "Markdown"
      [ test "has alt link text" <|
        \() -> expectContains ("![" ++ embeddedLinkText prediction ++ "]")
              <| embeddingCode exampleOrigin examplePredictionId prediction { exampleFields | contentType=Image, format=EmbedMarkdown}
      , test "links to prediction" <|
        \() -> expectContains "(https://example.com/p/my-predid)"
              <| embeddingCode "https://example.com" "my-predid" prediction { exampleFields | contentType=Image, format=EmbedMarkdown}
      ]
    ]
  ]

getBetParametersTest : Test
getBetParametersTest =
  describe "getBetParameters"
  [ describe "remainingCreatorStake"
    [ test "uses VsSkeptics vs skeptics" <|
      \() -> Expect.equal 4358
            <| .remainingCreatorStake
            <| getBetParameters Utils.Skeptic { mockPrediction | remainingStakeCentsVsSkeptics = 4358 }
    , test "uses VsBelievers vs believers" <|
      \() -> Expect.equal 56484
            <| .remainingCreatorStake
            <| getBetParameters Utils.Believer { mockPrediction | remainingStakeCentsVsBelievers = 56484 }
    ]
  , describe "creatorStakeFactor"
    [ test "computes correct ratio against skeptics" <|
      \() -> Expect.within (Expect.Absolute 0.00001) (0.80 / 0.20)
            <| .creatorStakeFactor
            <| getBetParameters Utils.Skeptic { mockPrediction | certainty = Just {low=0.80, high=1.00} }
    , test "computes correct ratio against believers" <|
      \() -> Expect.within (Expect.Absolute 0.00001) (0.20 / 0.80)
            <| .creatorStakeFactor
            <| getBetParameters Utils.Believer { mockPrediction | certainty = Just {low=0.50, high=0.80} }
    ]
  , describe "maxBettorStake"
    [ fuzz2 percentage (intRange 0 100) "never exceeds creator risk tolerance" <|
      \lowP remainingStake ->
        if lowP == 0 || lowP == 1 then Expect.pass else
        Expect.atMost remainingStake
        <| (\bet -> floor (toFloat bet.maxBettorStake * bet.creatorStakeFactor))
        <| getBetParameters Utils.Skeptic { mockPrediction | certainty = Just {low=lowP, high=1.00} , remainingStakeCentsVsSkeptics = remainingStake }
    , fuzz2 percentage (intRange 0 100) "never suggests a zero-to-nonzero-stake bet" <|
      \lowP remainingStake ->
        if lowP == 0 || lowP == 1 then Expect.pass else
        let
          bet = getBetParameters Utils.Skeptic { mockPrediction | certainty = Just {low=lowP, high=1.00} , remainingStakeCentsVsSkeptics = remainingStake }
          bettorStake = bet.maxBettorStake
          creatorStake = floor (toFloat bet.maxBettorStake * bet.creatorStakeFactor)
        in
        Expect.true "" (creatorStake > 0 || bettorStake == 0)
    ]
  ]

getTotalCreatorWinningsTest : Test
getTotalCreatorWinningsTest =
  describe "getTotalCreatorWinnings"
  [ fuzz Fuzz.bool "is 0 when no trades" <|
    \resolvedYes -> getTotalCreatorWinnings resolvedYes []
      |> Expect.equal 0
  , fuzz2 Fuzz.bool (Fuzz.intRange 1 3) "uses bettor-stake when bettor was wrong" <|
    \resolvedYes bettorStake ->
      getTotalCreatorWinnings resolvedYes [{ exampleTrade | bettorIsASkeptic = resolvedYes , bettorStakeCents = bettorStake }]
      |> Expect.equal bettorStake
  , fuzz2 Fuzz.bool (Fuzz.intRange 1 3) "uses creator-stake when creator was wrong" <|
    \resolvedYes creatorStake ->
      getTotalCreatorWinnings resolvedYes [{ exampleTrade | bettorIsASkeptic = not resolvedYes , creatorStakeCents = creatorStake }]
      |> Expect.equal (-creatorStake)
  , test "ignores queued trades" <|
    \() -> getTotalCreatorWinnings True [{ exampleTrade | state = Pb.TradeStateQueued }]
      |> Expect.equal 0
  , test "ignores aborted trades" <|
    \() -> getTotalCreatorWinnings True [{ exampleTrade | state = Pb.TradeStateDequeueFailed }]
      |> Expect.equal 0
  ]

makeModel : Globals.Globals -> Pb.UserPredictionView -> Model
makeModel globals prediction =
  initInternal (globals |> TU.addPrediction "my-predid" prediction) "my-predid"

viewModelForTest : Model -> HQ.Single Msg
viewModelForTest =
  view >> .body >> H.div [] >> HQ.fromHtml

buttonSelector : String -> HS.Selector
buttonSelector text =
  HS.all [HS.tag "button", HS.containing [HS.text text]]

findButton : String -> HQ.Single msg -> HQ.Single msg
findButton text =
  HQ.find [buttonSelector text]

fuzzFinalResolutions : Fuzz.Fuzzer Pb.Resolution
fuzzFinalResolutions =
  Fuzz.oneOf
  <| List.map Fuzz.constant
  <| [ Pb.ResolutionYes
     , Pb.ResolutionNoneYet
     , Pb.ResolutionInvalid
     ]
fuzzResolutions : Fuzz.Fuzzer Pb.Resolution
fuzzResolutions =
  Fuzz.oneOf
  <| List.map Fuzz.constant
  <| [ Pb.ResolutionNoneYet
     , Pb.ResolutionYes
     , Pb.ResolutionNoneYet
     , Pb.ResolutionInvalid
     ]

fuzzRequestStatus : Fuzz.Fuzzer RequestStatus
fuzzRequestStatus =
  Fuzz.oneOf
  <| [ Fuzz.constant Unstarted
     , Fuzz.constant AwaitingResponse
     , Fuzz.constant Succeeded
     , Fuzz.map Failed Fuzz.string
     ]

viewResolutionFormTest : Test
viewResolutionFormTest =
  let
    yesButtonText = "It happened!"
    noButtonText = "It didn't happen!"
    invalidButtonText = "Invalid prediction / impossible to resolve"
    unresolveButtonText = "un-resolve it."
  in
  describe "viewResolutionForm"
  [ describe "unresolved"
    [ test "has buttons for yes/no/invalid" <|
      \() -> viewResolutionForm "" Unstarted Pb.ResolutionNoneYet
              |> HQ.fromHtml
              |> Expect.all
                  [ findButton yesButtonText     >> HEM.simulate HEM.click >> HEM.expect (Resolve Pb.ResolutionYes)
                  , findButton noButtonText      >> HEM.simulate HEM.click >> HEM.expect (Resolve Pb.ResolutionNo)
                  , findButton invalidButtonText >> HEM.simulate HEM.click >> HEM.expect (Resolve Pb.ResolutionInvalid)
                  ]
    , test "has no button for un-resolving" <|
      \() -> viewResolutionForm "" Unstarted Pb.ResolutionNoneYet
              |> HQ.fromHtml
              |> HQ.hasNot [buttonSelector unresolveButtonText]
    ]
  , describe "resolved"
    [ test "has button for un-resolving" <|
      \() -> viewResolutionForm "" Unstarted Pb.ResolutionYes
              |> HQ.fromHtml
              |> findButton unresolveButtonText
              |> HEM.simulate HEM.click
              |> HEM.expect (Resolve Pb.ResolutionNoneYet)
    , test "has no buttons for yes/no/invalid" <|
      \() -> viewResolutionForm "" Unstarted Pb.ResolutionYes
              |> HQ.fromHtml
              |> Expect.all
                  [ HQ.hasNot [HS.containing [buttonSelector yesButtonText]]
                  , HQ.hasNot [HS.containing [buttonSelector noButtonText]]
                  , HQ.hasNot [HS.containing [buttonSelector invalidButtonText]]
                  ]
    ]
  , describe "notes field"
    [ fuzz2 fuzzResolutions Fuzz.string "value is notes field" <| \res val ->
        viewResolutionForm val Unstarted res
        |> HQ.fromHtml
        |> HQ.find [HS.tag "textarea"]
        |> HQ.has [HS.attribute (HA.value val)]
    , fuzz fuzzResolutions "sets notes field on input" <| \res ->
        viewResolutionForm "old val" Unstarted res
        |> HQ.fromHtml
        |> HQ.find [HS.tag "textarea"]
        |> HEM.simulate (HEM.input "new val!")
        |> HEM.expect (SetResolveNotesField "new val!")
    , fuzz2 fuzzRequestStatus fuzzResolutions "buttons are disabled (only) when awaiting response" <| \status res ->
        if status == AwaitingResponse then Expect.pass else
        viewResolutionForm "old val" status res
        |> HQ.fromHtml
        |> HQ.findAll [HS.tag "button"]
        |> HQ.each (HQ.has [HS.disabled (status == AwaitingResponse)])
    ]
  ]

fuzzBettability : Fuzz.Fuzzer Bettability
fuzzBettability =
  fuzzConstants
  [ QueueingUnnecessary
  , (QueueingNecessary (H.text "blah blah fuzz testing bettability"))
  ]
fuzzSide : Fuzz.Fuzzer Utils.BetSide
fuzzSide =
  fuzzConstants
  [ Utils.Skeptic
  , Utils.Believer
  ]

fuzzConstants : List a -> Fuzz.Fuzzer a
fuzzConstants xs =
  Fuzz.oneOf <| List.map Fuzz.constant xs

variantTests : String -> (a -> b) -> List (a, b -> Expect.Expectation) -> Test
variantTests title f inputExpects =
  describe title
  <| List.map (\(input, expect) -> test (Debug.toString input) (\() -> expect (f input))) inputExpects

expectMapEqual : (a -> b) -> a -> a -> Expect.Expectation
expectMapEqual f x y =
  Expect.equal (f x) (f y)

viewStakeWidgetTest : Test
viewStakeWidgetTest =
  let
    expectButtonHas : List (HS.Selector) -> H.Html Msg -> Expect.Expectation
    expectButtonHas selectors html =
      html |> HQ.fromHtml
      |> Expect.all
          [ HQ.find [HS.tag "button"] >> HQ.has selectors
          ]
    expectValid : H.Html Msg -> Expect.Expectation 
    expectValid html =
      html |> HQ.fromHtml
      |> Expect.all
          [ HQ.find [HS.tag "button"] >> HQ.has [HS.disabled False]
          , HQ.hasNot [HS.containing [HS.class "is-invalid"]]
          ]
    expectInvalid : String -> H.Html Msg -> Expect.Expectation
    expectInvalid text html =
      html
      |> HQ.fromHtml
      |> Expect.all
          [ HQ.find [HS.tag "button"] >> HQ.has [HS.disabled True]
          , HQ.has [HS.containing [HS.class "is-invalid"]]
          , HQ.find [HS.class "invalid-feedback"] >> HQ.has [HS.containing [HS.text text]]
          ]
  in
  describe "viewStakeWidget"
  [ fuzz2 fuzzBettability fuzzRequestStatus "button is disabled when awaiting response" <|
    \bettability status ->
      viewStakeWidget bettability "1" status Utils.Skeptic { mockPrediction | certainty = Just { low = 0.50 , high = 1.00 } }
      |> expectButtonHas [HS.disabled (status == AwaitingResponse)]
  , let
      prediction = { mockPrediction | certainty = Just { low = 0.50 , high = 0.75 }, maximumStakeCents = 1000, remainingStakeCentsVsSkeptics = 1000, remainingStakeCentsVsBelievers = 40 }
    in
    describe "validity testing"
    [ fuzz (intRange 1 100) "invalid if intended bet would exhaust creator stake" <|
      \val -> viewStakeWidget QueueingUnnecessary (String.fromInt val) Unstarted Utils.Skeptic prediction
        |>  if 100*val <= prediction.maximumStakeCents then
              expectValid
            else
              expectInvalid "must be between $0 and $10"
    , variantTests "invalid if intended bet is negative"
      (\field -> viewStakeWidget QueueingUnnecessary field Unstarted Utils.Skeptic prediction)
      [ ("1", expectValid)
      , ("-1", expectInvalid "must be between $0 and $10")
      ]
    , variantTests "validity test/feedback uses data from correct side"
      (\side -> viewStakeWidget QueueingUnnecessary "10" Unstarted side prediction)
      [ (Utils.Skeptic, expectValid)
      , (Utils.Believer, expectInvalid "must be between $0 and $1.20")
      ]
    , variantTests "invalid if field input is nonsensical"
      (\field -> viewStakeWidget QueueingUnnecessary field Unstarted Utils.Skeptic prediction)
      [ ("1", expectValid)
      , ("foo", expectInvalid "must be a number")
      ]
    ]
  , variantTests "button disabled if stake is 0"
    (\field -> viewStakeWidget QueueingUnnecessary field Unstarted Utils.Skeptic mockPrediction |> HQ.fromHtml |> HQ.find [HS.tag "button"])
    [ ("1", HQ.has [HS.disabled False])
    , ("0", HQ.has [HS.disabled True])
    ]
  , variantTests "explains reduced creator stake"
    (\remain -> viewStakeWidget QueueingUnnecessary "0" Unstarted Utils.Skeptic { mockPrediction | maximumStakeCents = 10 , remainingStakeCentsVsSkeptics = remain} |> HQ.fromHtml)
    [ (10, HQ.hasNot [HS.containing [HS.class "reduced-stake-limit-explanation"]])
    , ( 8, HQ.has [HS.containing [HS.class "reduced-stake-limit-explanation"]])
    , ( 0, HQ.has [HS.containing [HS.class "reduced-stake-limit-explanation"]])
    ]
  , variantTests "queues stakes depending on bettability"
    (\bettability -> viewStakeWidget bettability "1" Unstarted Utils.Skeptic {mockPrediction | creator = "creator"} |> HQ.fromHtml)
    [ ( QueueingNecessary (H.text "florbagorp")
      , Expect.all
        [ HQ.find [HS.tag "button"] >> HQ.has [HS.containing [HS.text "Queue, pending @creator's approval"]]
        , HQ.find [HS.tag "button"] >> HEM.simulate HEM.click >> HEM.expect (Stake 100)
        , HQ.contains [H.text "florbagorp"]
        ]
      )
    , ( QueueingUnnecessary
      , Expect.all
        [ HQ.find [HS.tag "button"] >> HQ.has [HS.containing [HS.text "Commit"]]
        , HQ.find [HS.tag "button"] >> HEM.simulate HEM.click >> HEM.expect (Stake 100)
        ]
      )
     ]
  ]

fuzzContentType : Fuzz.Fuzzer EmbeddingContentType
fuzzContentType =
  Fuzz.oneOf
  [ Fuzz.constant Image
  , Fuzz.constant Link
  ]
fuzzFormat : Fuzz.Fuzzer EmbeddingFormat
fuzzFormat =
  Fuzz.oneOf
  [ Fuzz.constant EmbedHtml
  , Fuzz.constant EmbedMarkdown
  ]
fuzzFontSize : Fuzz.Fuzzer EmbeddedImageFontSize
fuzzFontSize =
  Fuzz.oneOf
  [ Fuzz.constant SixPt
  , Fuzz.constant EightPt
  , Fuzz.constant TenPt
  , Fuzz.constant TwelvePt
  , Fuzz.constant FourteenPt
  , Fuzz.constant EighteenPt
  , Fuzz.constant TwentyFourPt
  ]
fuzzImageStyle : Fuzz.Fuzzer EmbeddedImageStyle
fuzzImageStyle =
  Fuzz.oneOf
  [ Fuzz.constant PlainLink
  , Fuzz.constant LessWrong
  , Fuzz.constant Red
  , Fuzz.constant DarkGreen
  , Fuzz.constant DarkBlue
  , Fuzz.constant Black
  , Fuzz.constant White
  ]

embeddingPreviewTest : Test
embeddingPreviewTest =
  describe "embeddingPreview"
  [ describe "Image"
    [ variantTests "uses selected style"
      (\style -> embeddingPreview "https://example.com" "my-predid" mockPrediction {format=EmbedHtml, style=style, contentType=Image, fontSize=TwelvePt} |> HQ.fromHtml |> HQ.find [HS.tag "img"])
      [ (PlainLink, HQ.has [HS.attribute (HA.src "https://example.com/p/my-predid/embed-plainlink-12pt.png")])
      , (LessWrong, HQ.has [HS.attribute (HA.src "https://example.com/p/my-predid/embed-lesswrong-12pt.png")])
      ]
    , variantTests "uses selected font size"
      (\size -> embeddingPreview "https://example.com" "my-predid" mockPrediction {format=EmbedHtml, style=PlainLink, contentType=Image, fontSize=size} |> HQ.fromHtml |> HQ.find [HS.tag "img"])
      [ (SixPt, HQ.has [HS.attribute (HA.src "https://example.com/p/my-predid/embed-plainlink-6pt.png")])
      , (TenPt, HQ.has [HS.attribute (HA.src "https://example.com/p/my-predid/embed-plainlink-10pt.png")])
      ]
    ]
  , describe "Link"
    [ test "links to the prediction page" <|
      \() -> embeddingPreview "https://example.com" "my-predid" mockPrediction {format=EmbedMarkdown, style=PlainLink, contentType=Link, fontSize=TwelvePt}
        |> HQ.fromHtml
        |> HQ.has [HS.tag "a", HS.attribute (HA.href "https://example.com/p/my-predid")]
    , test "has the appropriate link-text" <|
      \() -> embeddingPreview exampleOrigin examplePredictionId mockPrediction {format=EmbedMarkdown, style=PlainLink, contentType=Link, fontSize=TwelvePt}
        |> HQ.fromHtml
        |> HQ.contains [H.text <| embeddedLinkText mockPrediction]
    , fuzz fuzzFormat "ignores style" <|
      \format ->
        expectMapEqual (\style -> embeddingPreview exampleOrigin examplePredictionId mockPrediction {format=format, style=style, contentType=Link, fontSize=TwelvePt})
          PlainLink
          LessWrong
    , fuzz fuzzFormat "ignores font size" <|
      \format ->
        expectMapEqual (\size -> (embeddingPreview exampleOrigin examplePredictionId mockPrediction {format=format, style=PlainLink, contentType=Link, fontSize=size}))
          SixPt
          TwelvePt
    ]
  , fuzz2 fuzzImageStyle fuzzContentType "ignores embedding format" <|
    \style ctype ->
      expectMapEqual (\format -> embeddingPreview exampleOrigin examplePredictionId mockPrediction {format=format, style=style, contentType=ctype, fontSize=SixPt})
        EmbedHtml
        EmbedMarkdown
  ]

viewEmbedInfoTest : Test
viewEmbedInfoTest =
  describe "viewEmbedInfo"
  [ fuzz3 fuzzContentType fuzzFormat fuzzImageStyle "shows style dropdown for image only" <|
    \ctype format style ->
      viewEmbedInfo "https://example.com" {format=format, style=style, contentType=ctype, fontSize=TwelvePt} "my-predid" mockPrediction
      |> HQ.fromHtml
      |>  case ctype of
            Image -> HQ.has [HS.tag "option", HS.containing [HS.text "plain link"]]
            Link -> HQ.hasNot [HS.tag "option", HS.containing [HS.text "plain link"]]
  , fuzz3 fuzzContentType fuzzFormat fuzzImageStyle "shows font-size dropdown for image only" <|
    \ctype format style ->
      viewEmbedInfo "https://example.com" {format=format, style=style, contentType=ctype, fontSize=TwelvePt} "my-predid" mockPrediction
      |> HQ.fromHtml
      |>  case ctype of
            Image -> HQ.has [HS.tag "option", HS.containing [HS.text "12pt"]]
            Link -> HQ.hasNot [HS.tag "option", HS.containing [HS.text "12pt"]]
  , fuzz3 fuzzContentType fuzzFormat fuzzImageStyle "copy widget has appropriate code" <|
    \ctype format style ->
      let fields = {format=format, style=style, contentType=ctype, fontSize=TwelvePt} in
      viewEmbedInfo "https://example.com" fields "my-predid" mockPrediction
      |> HQ.fromHtml
      |> HQ.contains [CopyWidget.view Copy (embeddingCode "https://example.com" "my-predid" mockPrediction fields)]
  , fuzz3 fuzzContentType fuzzFormat fuzzImageStyle "contains preview" <|
    \ctype format style ->
      let fields = {format=format, style=style, contentType=ctype, fontSize=TwelvePt} in
      viewEmbedInfo "https://example.com" fields "my-predid" mockPrediction
      |> HQ.fromHtml
      |> HQ.contains [embeddingPreview "https://example.com" "my-predid" mockPrediction fields]
  ]

viewYourStakeTest : Test
viewYourStakeTest =
  describe "viewYourStake"
  [ describe "as bettor"
    [ fuzz (intRange 0 3) "includes one row per trade" <|
      \nTrades -> viewYourStake (Just "me") Time.utc {mockPrediction | yourTrades = List.repeat nTrades exampleTrade}
        |> HQ.fromHtml
        |>  if nTrades == 0 then
              HQ.hasNot [HS.containing [HS.tag "table"]]
            else
              HQ.find [HS.tag "tbody"]
              >> HQ.findAll [HS.tag "tr"]
              >> HQ.count (Expect.equal nTrades)
    ]
  ]

viewAsFriendTest : Test
viewAsFriendTest =
  let
    creator = "creator"
    predictionId = "my-predid"
    prediction = { mockPrediction | creator = creator }
    exampleSettings = TU.exampleSettings
    globals =
      exampleGlobals
      |> TU.logInAs "friend"
          { exampleSettings
          | relationships = exampleSettings.relationships |> Dict.insert creator (Just {trustsYou = True , trustedByYou = True})
          }
      |> (\g -> { g | now = Utils.unixtimeToTime prediction.createdUnixtime })
      |> TU.addPrediction predictionId prediction
  in
  describe "view as friend"
  [ test "has stake widget" <|
    \() -> initInternal globals predictionId
      |> viewModelForTest
      |> HQ.contains [viewStakeWidget QueueingUnnecessary "10" Unstarted Utils.Skeptic prediction]
  ]

creatorViewTest : Test
creatorViewTest =
  let
    creator = "creator"
    predictionId = "my-predid"
    prediction = { mockPrediction | creator = creator }
    globals = exampleGlobals |> TU.logInAs creator TU.exampleSettings |> TU.addPrediction predictionId prediction
  in
  describe "view for creator"
  [ test "displays title" <|
    \() -> initInternal globals predictionId
            |> viewModelForTest
            |> HQ.find [HS.id "prediction-title"]
            |> HQ.has [HS.tag "h2", HS.containing [HS.text "Prediction: by "], HS.containing [HS.text prediction.prediction]]
  , test "contains embed info" <|
    \() -> let m = initInternal globals predictionId in
            m
            |> viewModelForTest
            |> HQ.contains [embeddingPreview exampleGlobals.httpOrigin predictionId prediction m.shareEmbedding]
  , test "contains resolution form" <|
    \() -> initInternal globals predictionId
            |> (\m -> { m | resolveNotesField = "potato"})
            |> viewModelForTest
            |> HQ.contains [viewResolutionForm "potato" Unstarted Pb.ResolutionNoneYet]
  ]

viewTest : Test
viewTest =
  let
    titleSelector : HS.Selector
    titleSelector = HS.all [HS.id "prediction-title", HS.tag "h2"]
    testHasTitle : Globals.Globals -> Pb.UserPredictionView -> Test
    testHasTitle globals prediction =
      test "has title" <|
      \() -> makeModel globals prediction
              |> viewModelForTest
              |> HQ.find [titleSelector]
              |> HQ.has [HS.containing [HS.text "Prediction: by "], HS.containing [HS.text prediction.prediction]]
  in
  describe "view"
  [ describe "logged out"
    [ testHasTitle (exampleGlobals |> TU.logOut) mockPrediction
    ]

  , describe "rando"
    [ testHasTitle (exampleGlobals |> TU.logInAs "rando" TU.exampleSettings) mockPrediction
    ]

  , describe "betting section"
    [ test "absent for creator" <|
      \() -> makeModel (exampleGlobals |> TU.logInAs mockPrediction.creator TU.exampleSettings) mockPrediction
              |> viewModelForTest
              |> HQ.hasNot [HS.id "h4", HS.containing [HS.text "Make a bet"]]
    , test "present for non-creator" <|
      \() -> makeModel (exampleGlobals |> TU.logInAs ("not"++mockPrediction.creator) TU.exampleSettings) mockPrediction
              |> viewModelForTest
              |> HQ.has [HS.tag "h4", HS.containing [HS.text "Make a bet"]]
    , describe "logged out"
      [ test "is present" <|
        \() -> makeModel (exampleGlobals |> TU.logOut) mockPrediction
                |> viewModelForTest
                |> HQ.has [HS.tag "h4", HS.containing [HS.text "Make a bet"]]
      , test "encourages logging in" <|
        \() -> makeModel (exampleGlobals |> TU.logOut) mockPrediction
                |> viewModelForTest
                |> HQ.has [HS.tag "main", HS.containing [HS.tag "button", HS.containing [HS.text "Log in"]]]
      ]
    ]

  , describe "resolution section"
    [ test "present for creator" <|
      \() -> makeModel (exampleGlobals |> TU.logInAs mockPrediction.creator TU.exampleSettings) mockPrediction
              |> viewModelForTest
              |> HQ.has [HS.tag "h4", HS.containing [HS.text "Resolve this prediction"]]
    , test "absent for non-creator" <|
      \() -> makeModel (exampleGlobals |> TU.logInAs ("not"++mockPrediction.creator) TU.exampleSettings) mockPrediction
              |> viewModelForTest
              |> HQ.hasNot [HS.tag "h4", HS.containing [HS.text "Resolve this prediction"]]
    ]
  ]
