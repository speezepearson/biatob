module MyMarketsPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Json.Decode as JD
import Dict exposing (Dict)

import Biatob.Proto.Mvp as Pb
import Utils

import Biatob.Proto.Mvp exposing (StakeResult(..))
import ViewMarketPage

type alias Model =
  { markets : Dict Int ViewMarketPage.Model
  , auth : Maybe Pb.AuthToken
  }

type Msg
  = MarketPageMsg Int ViewMarketPage.Msg

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    auth : Maybe Pb.AuthToken
    auth =  Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    markets : Dict Int Pb.UserMarketView
    markets = Utils.mustDecodePbFromFlags Pb.marketsByIdDecoder "marketsPbB64" flags |> Utils.mustMarketsById
  in
  ( { markets = markets |> Dict.map (\marketId market -> ViewMarketPage.initBase {marketId=marketId, market=market, auth=auth})
    , auth = auth
    }
  , Cmd.none
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    MarketPageMsg marketId marketPageMsg ->
      case Dict.get marketId model.markets of
        Nothing -> Debug.todo "got message for unknown market"
        Just marketPage ->
          let (newMarketPage, marketPageCmd) = ViewMarketPage.update marketPageMsg marketPage in
          ( { model | markets = model.markets |> Dict.insert marketId newMarketPage }
          , Cmd.map (MarketPageMsg marketId) marketPageCmd
          )


view : Model -> Html Msg
view model =
  H.div []
    [ H.h2 [] [H.text "My Markets"]
    , model.markets
      |> Dict.toList
      |> List.sortBy (\(id, _) -> id)
      |> List.map (\(id, m) -> H.div [HA.style "margin" "1em", HA.style "padding" "1em", HA.style "border" "1px solid black"] [ViewMarketPage.view m |> H.map (MarketPageMsg id)])
      |> List.intersperse (H.hr [] [])
      |> H.div []
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
