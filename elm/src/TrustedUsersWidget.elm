module TrustedUsersWidget exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Protobuf.Encode as PE
import Protobuf.Decode as PD

import Biatob.Proto.Mvp as Pb
import Utils

import Field exposing (Field)

type alias Model =
  { trustedUsers : List Pb.UserId
  , working : Bool
  , notification : Html Msg
  }

type Msg
  = RemoveTrust Pb.UserId
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)

init : List Pb.UserId -> ( Model , Cmd Msg )
init trustedUsers =
  ( { trustedUsers = trustedUsers
    , working = False
    , notification = H.text ""
    }
  , Cmd.none
  )

postSetTrusted : Pb.SetTrustedRequest -> Cmd Msg
postSetTrusted req =
  Http.post
    { url = "/api/SetTrusted"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toSetTrustedRequestEncoder req
    , expect = PD.expectBytes SetTrustedFinished Pb.setTrustedResponseDecoder }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    RemoveTrust victim ->
      if List.member victim model.trustedUsers then
        ( { model | trustedUsers = model.trustedUsers |> List.filter ((/=) victim)
                  , working = True
                  , notification = H.text ""
          }
        , postSetTrusted {who=Just victim, trusted=False}
        )
      else
        ( model , Cmd.none )
    SetTrustedFinished (Err e) ->
      ( { model | working = False , notification = Utils.redText (Debug.toString e) }
      , Cmd.none
      )
    SetTrustedFinished (Ok resp) ->
      case resp.setTrustedResult of
        Just (Pb.SetTrustedResultOk _) ->
          ( { model | working = False } , Cmd.none )
        Just (Pb.SetTrustedResultError e) ->
          ( { model | working = False , notification = Utils.redText (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )

view : Model -> Html Msg
view model =
  if List.isEmpty model.trustedUsers then
    H.text "You don't trust anybody yet!"
  else
    H.ul []
    <| List.map (\u -> H.li [] [Utils.renderUser u, H.text " ", H.button [HE.onClick (RemoveTrust u)] [H.text "Remove trust"]])
    <| model.trustedUsers

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
