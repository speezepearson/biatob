module Elements.Prediction exposing (main)

import Html as H
import Json.Decode as JD

import Utils

import Widgets.PredictionWidget as Widget
import Page
import Page.Program

type alias Model = Widget.Model
type Msg
  = WidgetMsg Widget.Msg

init : JD.Value -> Model
init flags =
  let predictionId = Utils.mustDecodeFromFlags JD.int "predictionId" flags in
  Widget.init predictionId

update : Msg -> Model -> ( Model, Page.Command Msg )
update msg widget =
  case msg of
    WidgetMsg widgetMsg ->
      let
        (newWidget, innerCmd) = Widget.update widgetMsg widget
      in
      ( newWidget
      , Page.mapCmd WidgetMsg innerCmd
      )

pagedef : Page.Element Model Msg
pagedef =
  { init = \flags -> (init flags, Page.NoCmd)
  , view = \globals widget ->
      { title = ""
      , body = [H.main_ [] [Widget.view globals widget |> H.map WidgetMsg]]
      }
  , update = update
  , subscriptions = \_ -> Sub.none
  }

main = Page.Program.page pagedef
