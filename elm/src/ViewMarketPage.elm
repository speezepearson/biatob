port module ViewMarketPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD
import Protobuf.Encode as PE
import Protobuf.Decode as PD

import Biatob.Proto.Mvp as Pb
import Utils

import StakeForm

port staked : () -> Cmd msg

type alias Model =
  { market : StakeForm.State
  , marketId : Int
  , auth : Maybe Pb.AuthToken
  , working : Bool
  , stakeError : Maybe String
  }

type Msg
  = SetMarketState StakeForm.State
  | Stake {bettorIsASkeptic:Bool, bettorStakeCents:Int}
  | StakeFinished (Result Http.Error Pb.StakeResponse)
  | Ignore

init : JD.Value -> (Model, Cmd msg)
init flags =
  ( { market = flags |> JD.decodeValue (JD.field "marketPbB64" JD.string)
        |> Result.map (Debug.log "init market")
        |> Result.mapError (Debug.log "error decoding initial market")
        |> Result.toMaybe
        |> Maybe.andThen (Utils.decodePbB64 Pb.userMarketViewDecoder)
        |> Utils.must "no/invalid market from server"
        |> StakeForm.init
    , marketId = flags |> JD.decodeValue (JD.field "marketId" JD.int)
        |> Result.map (Debug.log "init auth token")
        |> Result.mapError (Debug.log "error decoding initial auth token")
        |> Result.toMaybe
        |> Utils.must "no marketId from server"
    , auth = flags |> JD.decodeValue (JD.field "authTokenPbB64" JD.string)
        |> Result.map (Debug.log "init auth token")
        |> Result.mapError (Debug.log "error decoding initial auth token")
        |> Result.toMaybe
        |> Maybe.andThen (Utils.decodePbB64 Pb.authTokenDecoder)
    , working = False
    , stakeError = Nothing
    }
  , Cmd.none
  )

postStake : Pb.StakeRequest -> Cmd Msg
postStake req =
  Http.post
    { url = "/api/Stake"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toStakeRequestEncoder req
    , expect = PD.expectBytes StakeFinished Pb.stakeResponseDecoder }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetMarketState newState ->
      ({ model | market = newState }, Cmd.none)
    Stake {bettorIsASkeptic, bettorStakeCents} ->
      ( { model | working = True , stakeError = Nothing }
      , postStake {marketId=model.marketId, bettorIsASkeptic=bettorIsASkeptic, bettorStakeCents=bettorStakeCents}
      )
    StakeFinished (Err e) ->
      ( { model | working = False , stakeError = Just (Debug.toString e) }
      , Cmd.none
      )
    StakeFinished (Ok resp) ->
      case resp.stakeResult of
        Just (Pb.StakeResultOk _) ->
          ( model
          , staked ()
          )
        Just (Pb.StakeResultError e) ->
          ( { model | working = False , stakeError = Just (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , stakeError = Just "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )

    Ignore ->
      (model, Cmd.none)

view : Model -> Html Msg
view model =
  StakeForm.view (marketConfig model) model.market

marketConfig : Model -> StakeForm.Config Msg
marketConfig model =
  { setState = SetMarketState
  , onStake = Stake
  , nevermind = Ignore
  , disableCommit = (model.auth == Nothing)
  }

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = \_ -> Sub.none
    , view = view
    , update = update
    }
