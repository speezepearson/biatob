module Elements.MyStakesTests exposing (..)

import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer, int, list, string)
import Test exposing (..)
import Time

import Biatob.Proto.Mvp as Pb
import Elements.MyStakes exposing (..)
import Utils exposing (unixtimeToTime)

mockPrediction : Pb.UserPredictionView
mockPrediction =
  { prediction = "a thing will happen"
  , certainty = Just {low = 0.10 , high = 0.90}
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
  }
exampleResolutionEvent : Pb.ResolutionEvent
exampleResolutionEvent =
  { resolution = Pb.ResolutionYes
  , unixtime = 1
  , notes = ""
  , priorRevision = Pb.ResolutionEventPriorRevision Nothing
  }
filterMatchesTest : Test
filterMatchesTest =
  let
    prediction = { mockPrediction | creator = "creator" , closesUnixtime = 100 }
  in
  describe "filterMatches"
  [ describe "phase"
    [ test "match -> match" <|
      \() -> Expect.true  "" <| filterMatches (unixtimeToTime <| prediction.closesUnixtime - 1) "self" {own=Nothing, phase=Just Open} prediction
    , test "no match -> no match" <|
      \() -> Expect.false "" <| filterMatches (unixtimeToTime <| prediction.closesUnixtime + 1) "self" {own=Nothing, phase=Just Open} prediction
    ]
  , describe "own"
    [ describe "True"
      [ test "matches own predictions" <|
        \() -> Expect.true  "" <| filterMatches (unixtimeToTime 0) "creator" {own=Just True, phase=Nothing} prediction
      , test "does not match not-own predictions" <|
        \() -> Expect.false "" <| filterMatches (unixtimeToTime 0) "rando"   {own=Just True, phase=Nothing} prediction
      ]
    , describe "False"
      [ test "does not match own predictions" <|
        \() -> Expect.false "" <| filterMatches (unixtimeToTime 0) "creator" {own=Just False, phase=Nothing} prediction
      , test "matches not-own predictions" <|
        \() -> Expect.true  "" <| filterMatches (unixtimeToTime 0) "rando"   {own=Just False, phase=Nothing} prediction
      ]
    , describe "Nothing"
      [ test "matches own predictions" <|
        \() -> Expect.true "" <| filterMatches (unixtimeToTime 0) "creator" {own=Nothing, phase=Nothing} prediction
      , test "matches not-own predictions" <|
        \() -> Expect.true "" <| filterMatches (unixtimeToTime 0) "rando"   {own=Nothing, phase=Nothing} prediction
      ]
    ]
  ]

phaseMatchTest : Test
phaseMatchTest =
  let
    preCloseTime = unixtimeToTime 50
    closesUnixtime = 100
    preResolveTime = unixtimeToTime 150
    resolvesAtUnixtime = 200
    postResolveTime = unixtimeToTime 250
    prediction = { mockPrediction | closesUnixtime = closesUnixtime , resolvesAtUnixtime = resolvesAtUnixtime }
  in
  describe "phaseMatches"
  [ describe "Open"
    [ test "matches before closesUnixtime" <|
      \() -> Expect.true "" <| phaseMatches preCloseTime Open prediction
    , test "does not match after closesUnixtime" <|
      \() -> Expect.false "" <| phaseMatches preResolveTime Open prediction
    , test "does not match resolved prediction" <|
      \() -> Expect.false "" <| phaseMatches preCloseTime Open {prediction | resolution = Just exampleResolutionEvent}
    ]
  , describe "Closed"
    [ test "does not match before closesUnixtime" <|
      \() -> Expect.false "" <| phaseMatches preCloseTime Closed prediction
    , test "matches after closesUnixtime" <|
      \() -> Expect.true "" <| phaseMatches preResolveTime Closed prediction
    , test "does not match after resolvesAtUnixtime" <|
      \() -> Expect.false "" <| phaseMatches postResolveTime Closed prediction
    , test "does not match resolved prediction" <|
      \() -> Expect.false "" <| phaseMatches preResolveTime Closed {prediction | resolution = Just exampleResolutionEvent}
    ]
  , describe "NeedsResolution"
    [ describe "before scheduled resolution time"
      [ test "should not match" <|
        \() -> Expect.false "" <| phaseMatches preResolveTime NeedsResolution { prediction | resolution = Nothing }
      ]
    , describe "after scheduled resolution time"
      [ test "matches if there no resolutions" <|
        \() -> Expect.true "" <| phaseMatches postResolveTime NeedsResolution { prediction | resolution = Nothing }
      , test "matches if resolution is NoneYet" <|
        \() -> Expect.true "" <| phaseMatches postResolveTime NeedsResolution { prediction | resolution = Just {exampleResolutionEvent | resolution=Pb.ResolutionNoneYet} }
      , test "does not match if resolved" <|
        \() -> Expect.false "" <| phaseMatches postResolveTime NeedsResolution { prediction | resolution = Just {exampleResolutionEvent | resolution=Pb.ResolutionYes} }
      ]
    ]
  , describe "Resolved"
    [ describe "before scheduled resolution time"
      [ test "matches if resolved" <|
        \() -> Expect.true "" <| phaseMatches preCloseTime Resolved { prediction | resolution = Just {exampleResolutionEvent | resolution=Pb.ResolutionYes} }
      , test "does not match if resolution is NoneYet" <|
        \() -> Expect.false "" <| phaseMatches preCloseTime Resolved { prediction | resolution = Just {exampleResolutionEvent | resolution=Pb.ResolutionNoneYet} }
      ]
    , describe "after scheduled resolution time"
      [ test "matches if resolved" <|
        \() -> Expect.true "" <| phaseMatches postResolveTime Resolved { prediction | resolution = Just {exampleResolutionEvent | resolution=Pb.ResolutionYes} }
      , test "does not match if resolution is NoneYet" <|
        \() -> Expect.false "" <| phaseMatches postResolveTime Resolved { prediction | resolution = Just {exampleResolutionEvent | resolution=Pb.ResolutionNoneYet} }
      ]
    ]
  ]

