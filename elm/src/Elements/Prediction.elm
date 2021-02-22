module Elements.Prediction exposing (main)

import Browser
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

type alias Model = ( Widget.Context Msg , Widget.State )
type Msg
  = WidgetEvent (Maybe Widget.Event) Widget.State
  | Tick Time.Posix
  | StakeFinished (Result Http.Error Pb.StakeResponse)
  | ResolveFinished (Result Http.Error Pb.ResolveResponse)
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)

init : JD.Value -> (Model, Cmd Msg)
init flags =
  ( ( { prediction = Utils.mustDecodePbFromFlags Pb.userPredictionViewDecoder "predictionPbB64" flags
      , predictionId = Utils.mustDecodeFromFlags JD.int "predictionId" flags
      , auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
      , now = Utils.unixtimeToTime 0
      , httpOrigin = Utils.mustDecodeFromFlags JD.string "httpOrigin" flags
      , handle = WidgetEvent
      }
    , Widget.init
    )
  , Task.perform Tick Time.now
  )

update : Msg -> Model -> ( Model, Cmd Msg )
update msg (ctx, model) =
  case msg of
    WidgetEvent event newState ->
      let
        cmd = case event of
          Nothing -> Cmd.none
          Just (Widget.Copy s) -> CopyWidget.copy s
          Just (Widget.InvitationEvent (SmallInvitationWidget.Copy s)) -> CopyWidget.copy s
          Just (Widget.InvitationEvent SmallInvitationWidget.CreateInvitation) -> API.postCreateInvitation CreateInvitationFinished {notes=""}
          Just (Widget.StakeEvent (StakeWidget.Staked {bettorIsASkeptic, bettorStakeCents})) -> API.postStake StakeFinished {predictionId=ctx.predictionId, bettorIsASkeptic=bettorIsASkeptic, bettorStakeCents=bettorStakeCents}
          Just (Widget.Resolve resolution) -> API.postResolve ResolveFinished {predictionId=ctx.predictionId, resolution=resolution, notes = ""}
      in
        ((ctx, newState), cmd)
    Tick now -> (({ctx | now = now}, model), Cmd.none)
    CreateInvitationFinished res ->
      ( ( ctx
        , model |> Widget.handleCreateInvitationResponse res
        )
      , Cmd.none
      )
    StakeFinished res ->
      ( ( { ctx | prediction = case res |> Result.toMaybe |> Maybe.andThen .stakeResult of
                    Just (Pb.StakeResultOk pred) -> pred
                    _ -> ctx.prediction
          }
        , model |> Widget.handleStakeResponse res
        )
      , Cmd.none
      )
    ResolveFinished res ->
      ( ( { ctx | prediction = case res |> Result.toMaybe |> Maybe.andThen .resolveResult of
                    Just (Pb.ResolveResultOk pred) -> pred
                    _ -> ctx.prediction
          }
        , model |> Widget.handleResolveResponse res
        )
      , Cmd.none
      )

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = \_ -> Time.every 1000 Tick
    , view = \(ctx, model) -> Widget.view ctx model
    , update = update
    }
