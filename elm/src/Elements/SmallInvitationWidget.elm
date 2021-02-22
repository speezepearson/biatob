module Elements.SmallInvitationWidget exposing (main)

import Browser
import Http
import Json.Decode as JD
import Time

import Biatob.Proto.Mvp as Pb
import Utils

import Task
import Widgets.CopyWidget as CopyWidget
import API

import Widgets.CopyWidget as CopyWidget
import Widgets.SmallInvitationWidget as Widget

type alias Model = ( Widget.Context Msg , Widget.State )
type Msg
  = WidgetEvent (Maybe Widget.Event) Widget.State
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)

init : JD.Value -> (Model, Cmd Msg)
init flags =
  ( ( { destination = JD.decodeValue (JD.field "destination" JD.string) flags |> Result.toMaybe
      , httpOrigin = Utils.mustDecodeFromFlags JD.string "httpOrigin" flags
      , handle = WidgetEvent
      }
    , Widget.init
    )
  , Cmd.none
  )

update : Msg -> Model -> ( Model, Cmd Msg )
update msg (ctx, model) =
  case msg of
    WidgetEvent event newState ->
      let
        cmd = case event of
          Just Widget.CreateInvitation -> API.postCreateInvitation CreateInvitationFinished {notes=""}
          Just (Widget.Copy s) -> CopyWidget.copy s
          Nothing -> Cmd.none
      in
        ((ctx, newState), cmd)
    CreateInvitationFinished res ->
      ( ( ctx
        , model |> Widget.handleCreateInvitationResponse res
        )
      , Cmd.none
      )

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = \_ -> Sub.none
    , view = \(ctx, model) -> Widget.view ctx model
    , update = update
    }
