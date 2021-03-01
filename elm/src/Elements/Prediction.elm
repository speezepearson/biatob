module Elements.Prediction exposing (main)

import Browser
import Html as H exposing (Html)
import Http
import Json.Decode as JD
import Time

import Biatob.Proto.Mvp as Pb
import Utils

import Task
import Widgets.CopyWidget as CopyWidget
import API
import Widgets.PredictionWidget as Widget
import Widgets.StakeWidget as StakeWidget
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Page

type alias Model = ( Widget.Context , Widget.Model )
type Msg
  = WidgetMsg Widget.Msg

init : JD.Value -> Model
init flags =
  let predictionId = Utils.mustDecodeFromFlags JD.int "predictionId" flags in
  ( { prediction = Utils.mustDecodePbFromFlags Pb.userPredictionViewDecoder "predictionPbB64" flags
    , predictionId = predictionId
    , shouldLinkTitle = False
    }
  , Widget.init predictionId
  )

update : Msg -> Model -> ( Model, Page.Command Msg )
update msg (ctx, widget) =
  case msg of
    WidgetMsg widgetMsg ->
      let
        (newWidget, innerCmd) = Widget.update widgetMsg widget
        newPrediction = case widgetMsg of
          Widget.StakeMsg (StakeWidget.StakeFinished _) -> Debug.todo ""
          Widget.ResolveFinished _ -> Debug.todo ""
          _ -> Nothing
      in
      ( ( ctx , newWidget )
      , Page.mapCmd WidgetMsg innerCmd
      )

pagedef : Page.Element Model Msg
pagedef =
  { init = \flags -> (init flags, Page.NoCmd)
  , view = \globals (ctx, widget) ->
      { title = ""
      , body = [H.main_ [] [Widget.view ctx globals widget |> H.map WidgetMsg]]
      }
  , update = update
  , subscriptions = \_ -> Sub.none
  }

main = Page.page pagedef
