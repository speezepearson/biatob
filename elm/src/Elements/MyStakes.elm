module Elements.MyStakes exposing (main)

import Html as H
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import Biatob.Proto.Mvp exposing (StakeResult(..))
import Widgets.ViewPredictionsWidget as ViewPredictionsWidget
import Page
import Page.Program

type alias Model = ViewPredictionsWidget.Model
type alias Msg = ViewPredictionsWidget.Msg

init : JD.Value -> (Model, Page.Command Msg)
init flags =
  ( ViewPredictionsWidget.init <| Utils.mustPredictionsById <| Utils.mustDecodePbFromFlags Pb.predictionsByIdDecoder "predictionsPbB64" flags
  , Page.NoCmd
  )

pagedef : Page.Element Model Msg
pagedef =
  { init = init
  , view = \g m -> {title="My stakes", body=[H.h2 [] [H.text "My Stakes"], H.main_ [] [ViewPredictionsWidget.view g m]]}
  , update = ViewPredictionsWidget.update
  , subscriptions = ViewPredictionsWidget.subscriptions
  }

main = Page.Program.page pagedef
