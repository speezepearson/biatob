module Elements.MyStakesPage exposing (..)

import Browser
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import Biatob.Proto.Mvp exposing (StakeResult(..))
import Widgets.ViewPredictionsWidget as ViewPredictionsWidget

type alias Model = ViewPredictionsWidget.Model
type alias Msg = ViewPredictionsWidget.Msg

initFromFlags : JD.Value -> (Model, Cmd Msg)
initFromFlags flags =
  ViewPredictionsWidget.init
    { auth =  Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    , predictions = Utils.mustDecodePbFromFlags Pb.predictionsByIdDecoder "predictionsPbB64" flags |> Utils.mustPredictionsById
    , httpOrigin = Utils.mustDecodeFromFlags JD.string "httpOrigin" flags
    }

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = initFromFlags
    , subscriptions = ViewPredictionsWidget.subscriptions
    , view = ViewPredictionsWidget.view
    , update = ViewPredictionsWidget.update
    }
