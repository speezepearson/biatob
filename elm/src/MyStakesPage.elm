module MyStakesPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as JD
import Dict exposing (Dict)
import Time

import Biatob.Proto.Mvp as Pb
import Utils

import Biatob.Proto.Mvp exposing (StakeResult(..))
import ViewPredictionsWidget
import Task

type alias Model = ViewPredictionsWidget.Model
type alias Msg = ViewPredictionsWidget.Msg

initFromFlags : JD.Value -> (Model, Cmd Msg)
initFromFlags flags =
  ViewPredictionsWidget.init
    { auth =  Utils.mustDecodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    , predictions = Utils.mustDecodePbFromFlags Pb.predictionsByIdDecoder "predictionsPbB64" flags |> Utils.mustPredictionsById
    , linkToAuthority = Utils.mustDecodeFromFlags JD.string "linkToAuthority" flags
    }

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = initFromFlags
    , subscriptions = ViewPredictionsWidget.subscriptions
    , view = ViewPredictionsWidget.view
    , update = ViewPredictionsWidget.update
    }
