module Elements.PredictionTests exposing (..)

import  Bytes.Encode
import Json.Decode as JD
import Json.Encode as JE
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer, intRange, percentage)
import Html as H
import Html.Attributes as HA
import Test exposing (..)
import Test.Html.Event as HEM
import Test.Html.Query as HQ
import Test.Html.Selector as HS

import Globals
import Biatob.Proto.Mvp as Pb
import Widgets.AuthWidget as AuthWidget
import Widgets.EmailSettingsWidget as EmailSettingsWidget
import Elements.Prediction exposing (..)
import Utils exposing (unixtimeToTime)
import Time
import Dict
import Utils exposing (Username)
import TestUtils as TU exposing (exampleGlobals)
import Elements.MyStakesTests exposing (exampleResolutionEvent)

exampleOrigin = "https://example.com"
examplePredictionId = "my-test-prediction"
exampleFields = {style=PlainLink, fontSize=TwelvePt, contentType=Link, format=EmbedHtml}

mockPrediction : Pb.UserPredictionView
mockPrediction =
  { prediction = "a thing will happen"
  , certainty = Just {low = 0.10 , high = 0.70}
  , stakeDenomination = Pb.CurrencyUsCents
  , maximumStake = 10000
  , remainingStakeVsBelievers = 10000
  , remainingStakeVsSkeptics = 10000
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
  , bettorStake = 7
  , creatorStake = 13
  , transactedUnixtime = 0
  }
embeddedLinkTextTest : Test
embeddedLinkTextTest =
  describe "embeddedLinkText"
  [ test "with both low and high probs set" <|
    \() -> Expect.equal "(bet: $100 at 10-30%)"
          <| embeddedLinkText exampleOrigin examplePredictionId { mockPrediction | certainty = Just {low = 0.10 , high = 0.30} , maximumStake = 10000 }
  , test "with only low prob set" <|
    \() -> Expect.equal "(bet: $100 at 10%)"
          <| embeddedLinkText exampleOrigin examplePredictionId { mockPrediction | certainty = Just {low = 0.10 , high = 1.00} , maximumStake = 10000 }
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
    prediction = { mockPrediction | certainty = Just {low = 0.10 , high = 1.00} , maximumStake = 10000 }
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
            <| getBetParameters True { mockPrediction | remainingStakeVsSkeptics = 4358 }
    , test "uses VsBelievers vs believers" <|
      \() -> Expect.equal 56484
            <| .remainingCreatorStake
            <| getBetParameters False { mockPrediction | remainingStakeVsBelievers = 56484 }
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
        <| getBetParameters True { mockPrediction | certainty = Just {low=lowP, high=1.00} , remainingStakeVsSkeptics = remainingStake }
    , fuzz2 percentage (intRange 0 100) "never suggests a zero-to-nonzero-stake bet" <|
      \lowP remainingStake ->
        if lowP == 0 || lowP == 1 then Expect.pass else
        let
          bet = getBetParameters True { mockPrediction | certainty = Just {low=lowP, high=1.00} , remainingStakeVsSkeptics = remainingStake }
          bettorStake = bet.maxBettorStake
          creatorStake = floor (toFloat bet.maxBettorStake * bet.creatorStakeFactor)
        in
        Expect.true "" (creatorStake > 0 || bettorStake == 0)
    ]
  ]

makeModel : Globals.Globals -> Pb.UserPredictionView -> Model
makeModel globals prediction =
  initInternal (globals |> TU.addPrediction "my-predid" prediction) "my-predid"

viewModelForTest : Model -> HQ.Single Msg
viewModelForTest model =
  HQ.fromHtml <| H.div [] <| .body <| view model

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

    resolveSectionSelector : HS.Selector
    resolveSectionSelector = HS.all [HS.id "resolve-section", HS.containing [HS.tag "h4", HS.containing [HS.text "Resolve this prediction"]]]
    yesButtonSelector : HS.Selector
    yesButtonSelector = HS.all [HS.tag "button", HS.containing [HS.text "It happened!"]]
    noButtonSelector : HS.Selector
    noButtonSelector = HS.all [HS.tag "button", HS.containing [HS.text "It didn't happen!"]]
    invalidButtonSelector : HS.Selector
    invalidButtonSelector = HS.all [HS.tag "button", HS.containing [HS.text "Invalid prediction / impossible to resolve"]]
    unresolveButtonSelector : HS.Selector
    unresolveButtonSelector = HS.all [HS.tag "button", HS.containing [HS.text "un-resolve it."]]

    stakeButtonSelector : HS.Selector
    stakeButtonSelector = HS.all [HS.tag "button", HS.containing [HS.text "Stake"]]
    queueStakeButtonSelector : HS.Selector
    queueStakeButtonSelector = HS.all [HS.tag "button", HS.containing [HS.text "Queue"]]
  in
  describe "view"
  [ describe "logged out"
    [ testHasTitle (exampleGlobals |> TU.logOut) mockPrediction
    ]

  , let globals = exampleGlobals |> TU.logInAs mockPrediction.creator TU.exampleSettings in
    describe "creator"
    [ testHasTitle globals mockPrediction
    , describe "resolution section"
      [ let section = makeModel globals {mockPrediction | resolutions = []} |> viewModelForTest |> HQ.find [resolveSectionSelector] in
        describe "never-resolved prediction"
        [ test "section exists" <| \() -> HQ.has [] section
        , test "yes/no/invalid buttons send appropriate Msgs" <|
          \() -> Expect.all
                  [ HQ.find [yesButtonSelector] >> HEM.simulate HEM.click >> HEM.expect (Resolve Pb.ResolutionYes)
                  , HQ.find [noButtonSelector] >> HEM.simulate HEM.click >> HEM.expect (Resolve Pb.ResolutionNo)
                  , HQ.find [invalidButtonSelector] >> HEM.simulate HEM.click >> HEM.expect (Resolve Pb.ResolutionInvalid)
                  ]
                  section
        , test "section has no unresolve button" <| \() -> HQ.hasNot [HS.containing [unresolveButtonSelector]] section
        ]
      , let section = makeModel globals {mockPrediction | resolutions = [{exampleResolutionEvent | resolution = Pb.ResolutionNoneYet}]} |> viewModelForTest |> HQ.find [HS.id "resolve-section"] in
        describe "prediction explicitly resolved to NoneYet"
        [ test "section exists" <| \() -> HQ.has [] section
        , test "yes/no/invalid buttons send appropriate Msgs" <|
          \() -> Expect.all
                  [ HQ.find [yesButtonSelector] >> HEM.simulate HEM.click >> HEM.expect (Resolve Pb.ResolutionYes)
                  , HQ.find [noButtonSelector] >> HEM.simulate HEM.click >> HEM.expect (Resolve Pb.ResolutionNo)
                  , HQ.find [invalidButtonSelector] >> HEM.simulate HEM.click >> HEM.expect (Resolve Pb.ResolutionInvalid)
                  ]
                  section
        , test "section has no unresolve button" <| \() -> HQ.hasNot [HS.containing [unresolveButtonSelector]] section
        ]
      , let section = makeModel globals {mockPrediction | resolutions = [{exampleResolutionEvent | resolution = Pb.ResolutionYes}]} |> viewModelForTest |> HQ.find [HS.id "resolve-section"] in
        describe "conclusively resolved prediction"
        [ test "section exists" <| \() -> HQ.has [] section
        , test "yes/no/invalid buttons send appropriate Msgs" <|
          \() -> section |> HQ.find [unresolveButtonSelector] |> HEM.simulate HEM.click |> HEM.expect (Resolve Pb.ResolutionNoneYet)
        ]
      ]
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
