module Widgets.StakeWidget exposing (..)

import Browser
import Dict
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Time
import Http

import Biatob.Proto.Mvp as Pb
import Utils exposing (b, PredictionId)

import Field exposing (Field)
import Page

epsilon = 0.0000001 -- 🎵 I hate floating-point arithmetic 🎶

type Msg
  = SetBelieverStakeField String
  | SetSkepticStakeField String
  | Stake {bettorIsASkeptic : Bool, stakeCents : Int}
  | StakeFinished (Result Http.Error Pb.StakeResponse)

type alias Model =
  { believerStakeField : Field {max : Int} Int
  , skepticStakeField : Field {max : Int} Int
  , working : Bool
  , notification : Html Never
  , disableCommit : Bool
  , predictionId : PredictionId
  }

update : Msg -> Model -> ( Model , Page.Command Msg )
update msg model =
  case msg of
    SetBelieverStakeField s -> ( { model | believerStakeField = model.believerStakeField |> Field.setStr s } , Page.NoCmd)
    SetSkepticStakeField s -> ( { model | skepticStakeField = model.skepticStakeField |> Field.setStr s } , Page.NoCmd)
    Stake {bettorIsASkeptic, stakeCents} ->
      ( { model | working = True , notification = H.text "" }
      , Page.RequestCmd <| Page.StakeRequest StakeFinished {predictionId=model.predictionId, bettorIsASkeptic=bettorIsASkeptic, bettorStakeCents=stakeCents}
      )
    StakeFinished res ->
      case res of
        Err e ->
          ( { model | working = False , notification = Utils.redText (Debug.toString e) } , Page.NoCmd )
        Ok resp ->
          case resp.stakeResult of
            Just (Pb.StakeResultOk newPrediction) ->
              ( { model | working = False
                        , notification = Utils.greenText "Committed!"
                        , believerStakeField = model.believerStakeField |> Field.setStr "0"
                        , skepticStakeField = model.skepticStakeField |> Field.setStr "0"
                        }
              , Page.NoCmd
              )
            Just (Pb.StakeResultError e) ->
              ( { model | working = False , notification = Utils.redText (Debug.toString e) } , Page.NoCmd )
            Nothing ->
              ( { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" } , Page.NoCmd )


view : Page.Globals -> Model -> Html Msg
view globals model =
  let
    prediction = globals.serverState.predictions |> Dict.get model.predictionId |> Utils.must "prediction for StakeWidget is not loaded"
    creator = prediction.creator
    certainty = Utils.mustPredictionCertainty prediction

    isClosed = Utils.timeToUnixtime globals.now > prediction.closesUnixtime
    disableInputs = isClosed || Utils.resolutionIsTerminal (Utils.currentResolution prediction)
    creatorStakeFactorVsBelievers = (1 - certainty.high) / certainty.high
    creatorStakeFactorVsSkeptics = certainty.low / (1 - certainty.low)
    maxBelieverStakeCents = if creatorStakeFactorVsBelievers == 0 then 0 else toFloat prediction.remainingStakeCentsVsBelievers / creatorStakeFactorVsBelievers + 0.001 |> floor
    maxSkepticStakeCents = if creatorStakeFactorVsSkeptics == 0 then 0 else toFloat prediction.remainingStakeCentsVsSkeptics / creatorStakeFactorVsSkeptics + 0.001 |> floor
  in
  H.div []
    [ if certainty.low == 0 then H.text "" else
      H.p []
      [ H.text "Do you ", b "strongly doubt", H.text " that this will happen? Then stake $"
      , Field.inputFor SetSkepticStakeField {max=maxSkepticStakeCents} model.skepticStakeField
          H.input
          [ HA.style "width" "5em"
          , HA.type_"number", HA.min "0", HA.max (toFloat maxSkepticStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
          , HA.disabled disableInputs
          ]
          []
      , H.text " that it won't, against ", Utils.renderUser creator, H.text "'s "
      , Utils.b (Field.parse {max=maxSkepticStakeCents} model.skepticStakeField |> Result.map (toFloat >> (*) creatorStakeFactorVsSkeptics >> round >> Utils.formatCents) |> Result.withDefault "???")
      , H.text ". "
      , H.button
          (case Field.parse {max=maxSkepticStakeCents} model.skepticStakeField of
            Ok stake ->
              [ HE.onClick (Stake {bettorIsASkeptic=True, stakeCents=stake}) ]
            Err _ ->
              [ HA.disabled True ]
          )
          [H.text "Commit"]
      ]
    , if certainty.high == 1 then H.text "" else
      H.p []
      [ H.text "Do you ", b "strongly believe", H.text " that this will happen? Then stake $"
      , Field.inputFor SetBelieverStakeField {max=maxBelieverStakeCents} model.believerStakeField
          H.input
          [ HA.style "width" "5em"
          , HA.type_"number", HA.min "0", HA.max (toFloat maxBelieverStakeCents / 100 + epsilon |> String.fromFloat), HA.step "any"
          , HA.disabled disableInputs
          ]
          []
      , H.text " that it will, against ", Utils.renderUser creator, H.text "'s "
      , Utils.b (Field.parse {max=maxBelieverStakeCents} model.believerStakeField |> Result.map (toFloat >> (*) creatorStakeFactorVsBelievers >> round >> Utils.formatCents) |> Result.withDefault "???")
      , H.text ". "
      , H.button
          (case Field.parse {max=maxBelieverStakeCents} model.believerStakeField of
            Ok stake ->
              [ HE.onClick (Stake {bettorIsASkeptic=False, stakeCents=stake}) ]
            Err _ ->
              [ HA.disabled True ]
          )
          [H.text "Commit"]
      ]
    , model.notification |> H.map never
    ]

init : PredictionId -> Model
init predictionId =
  let
    parseCents : {max:Int} -> String -> Result String Int
    parseCents {max} s =
      case String.toFloat s of
        Nothing -> Err "must be a number"
        Just dollars ->
          let n = round (100*dollars) in
          if n < 0 || n > max then Err ("must be between $0 and " ++ Utils.formatCents max) else Ok n
  in
  { believerStakeField = Field.init "0" parseCents
  , skepticStakeField = Field.init "0" parseCents
  , working = False
  , notification = H.text ""
  , disableCommit = False
  , predictionId = predictionId
  }
setDisableCommit : Bool -> Model -> Model
setDisableCommit disableCommit model =
  { model | disableCommit = disableCommit }

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
