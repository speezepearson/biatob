module Elements.PredictionTests exposing (..)

import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer, intRange, percentage)
import Test exposing (..)
import Time

import Biatob.Proto.Mvp as Pb
import Elements.Prediction exposing (..)
import Utils exposing (unixtimeToTime)

exampleOrigin = "https://example.com"
examplePredictionId = "my-test-prediction"
exampleFields = {color=DarkGreen, fontSize=TwelvePt, contentType=Link, format=EmbedHtml}

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
  , resolutions = []
  , yourTrades = []
  , yourQueuedTrades = []
  , resolvesAtUnixtime = 200
  , allowEmailInvitations = False
  }

exampleTrade : Pb.Trade
exampleTrade =
  { bettor = "bettor"
  , bettorIsASkeptic = False
  , bettorStakeCents = 7
  , creatorStakeCents = 13
  , transactedUnixtime = 0
  }
embeddedLinkTextTest : Test
embeddedLinkTextTest =
  describe "embeddedLinkText"
  [ test "with both low and high probs set" <|
    \() -> Expect.equal "(bet: $100 at 10-30%)"
          <| embeddedLinkText exampleOrigin examplePredictionId { mockPrediction | certainty = Just {low = 0.10 , high = 0.30} , maximumStakeCents = 10000 }
  , test "with only low prob set" <|
    \() -> Expect.equal "(bet: $100 at 10%)"
          <| embeddedLinkText exampleOrigin examplePredictionId { mockPrediction | certainty = Just {low = 0.10 , high = 1.00} , maximumStakeCents = 10000 }
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
        \() -> expectContains (">" ++ embeddedLinkText exampleOrigin examplePredictionId prediction ++ "<")
              <| embeddingCode exampleOrigin examplePredictionId prediction { exampleFields | contentType=Link, format=EmbedHtml}
      , test "links to prediction" <|
        \() -> expectContains " href=\"https://example.com/p/my-predid\""
              <| embeddingCode "https://example.com" "my-predid" prediction { exampleFields | contentType=Link, format=EmbedHtml}
      ]
    , describe "Markdown"
      [ test "contains link text" <|
        \() -> Expect.true ""
              <| String.startsWith ("[" ++ embeddedLinkText exampleOrigin examplePredictionId prediction ++ "]")
              <| embeddingCode exampleOrigin examplePredictionId prediction { exampleFields | contentType=Link, format=EmbedMarkdown}
      , test "links to prediction" <|
        \() -> expectContains "(https://example.com/p/my-predid)"
              <| embeddingCode "https://example.com" "my-predid" prediction { exampleFields | contentType=Link, format=EmbedMarkdown}
      ]
    ]
  , describe "images"
    [ describe "HTML"
      [ test "has alt link text" <|
        \() -> expectContains (" alt=\"" ++ embeddedLinkText exampleOrigin examplePredictionId prediction ++ "\"")
              <| embeddingCode exampleOrigin examplePredictionId prediction { exampleFields | contentType=Image, format=EmbedHtml}
      , test "links to prediction" <|
        \() -> expectContains " href=\"https://example.com/p/my-predid\""
              <| embeddingCode "https://example.com" "my-predid" prediction { exampleFields | contentType=Image, format=EmbedHtml}
      ]
    , describe "Markdown"
      [ test "has alt link text" <|
        \() -> expectContains ("![" ++ embeddedLinkText exampleOrigin examplePredictionId prediction ++ "]")
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
            <| getBetParameters True { mockPrediction | remainingStakeCentsVsSkeptics = 4358 }
    , test "uses VsBelievers vs believers" <|
      \() -> Expect.equal 56484
            <| .remainingCreatorStake
            <| getBetParameters False { mockPrediction | remainingStakeCentsVsBelievers = 56484 }
    ]
  , describe "creatorStakeFactor"
    [ test "computes correct ratio against skeptics" <|
      \() -> Expect.within (Expect.Absolute 0.00001) (0.80 / 0.20)
            <| .creatorStakeFactor
            <| getBetParameters True { mockPrediction | certainty = Just {low=0.80, high=1.00} }
    , test "computes correct ratio against believers" <|
      \() -> Expect.within (Expect.Absolute 0.00001) (0.20 / 0.80)
            <| .creatorStakeFactor
            <| getBetParameters False { mockPrediction | certainty = Just {low=0.50, high=0.80} }
    ]
  , describe "maxBettorStake"
    [ fuzz2 percentage (intRange 0 100) "never exceeds creator risk tolerance" <|
      \lowP remainingStake -> 
        if lowP == 0 || lowP == 1 then Expect.pass else
        Expect.atMost remainingStake
        <| (\bet -> floor (toFloat bet.maxBettorStake * bet.creatorStakeFactor))
        <| getBetParameters True { mockPrediction | certainty = Just {low=lowP, high=1.00} , remainingStakeCentsVsSkeptics = remainingStake }
    , fuzz2 percentage (intRange 0 100) "never suggests a zero-to-nonzero-stake bet" <|
      \lowP remainingStake -> 
        if lowP == 0 || lowP == 1 then Expect.pass else
        let
          bet = getBetParameters True { mockPrediction | certainty = Just {low=lowP, high=1.00} , remainingStakeCentsVsSkeptics = remainingStake }
          bettorStake = bet.maxBettorStake
          creatorStake = floor (toFloat bet.maxBettorStake * bet.creatorStakeFactor)
        in
        Expect.true "" (creatorStake > 0 || bettorStake == 0)
    ]
  ]