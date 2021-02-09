module MyPredictionsPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Json.Decode as JD
import Dict exposing (Dict)
import Time

import Biatob.Proto.Mvp as Pb
import Utils

import Biatob.Proto.Mvp exposing (StakeResult(..))
import ViewPredictionPage

type alias Model =
  { predictions : Dict Int ViewPredictionPage.Model
  , auth : Maybe Pb.AuthToken
  }

type Msg
  = PredictionPageMsg Int ViewPredictionPage.Msg

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    auth : Maybe Pb.AuthToken
    auth =  Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    predictions : Dict Int Pb.UserPredictionView
    predictions = Utils.mustDecodePbFromFlags Pb.predictionsByIdDecoder "predictionsPbB64" flags |> Utils.mustPredictionsById

    subinits : Dict Int (ViewPredictionPage.Model, Cmd ViewPredictionPage.Msg)
    subinits =
      Dict.map
        (\id m ->
          let (submodel, subcmd) = ViewPredictionPage.initBase {predictionId=id, prediction=m, auth=auth, now=Time.millisToPosix 0} in
          (submodel, subcmd)
        )
        predictions
  in
  ( { predictions = Dict.map (\_ (submodel, _) -> submodel) subinits
    , auth = auth
    }
  , Cmd.batch <| List.map (\(id, (_, subcmd)) -> Cmd.map (PredictionPageMsg id) subcmd) <| Dict.toList subinits
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    PredictionPageMsg predictionId predictionPageMsg ->
      case Dict.get predictionId model.predictions of
        Nothing -> Debug.todo "got message for unknown prediction"
        Just predictionPage ->
          let (newPredictionPage, predictionPageCmd) = ViewPredictionPage.update predictionPageMsg predictionPage in
          ( { model | predictions = model.predictions |> Dict.insert predictionId newPredictionPage }
          , Cmd.map (PredictionPageMsg predictionId) predictionPageCmd
          )


view : Model -> Html Msg
view model =
  H.div []
    [ H.h2 [] [H.text "My Predictions"]
    , if model.auth == Nothing then
        H.text "You're not logged in, so I don't know what predictions to show you!"
      else if Dict.isEmpty model.predictions then
        H.div []
          [ H.text "You haven't participated in any predictions yet!"
          , H.br [] []
          , H.text "Maybe you want to "
          , H.a [HA.href "/new"] [H.text "create one"]
          , H.text "?"
          ]
      else
        model.predictions
        |> Dict.toList
        |> List.sortBy (\(id, _) -> id)
        |> List.map (\(id, m) -> H.div [HA.style "margin" "1em", HA.style "padding" "1em", HA.style "border" "1px solid black"] [ViewPredictionPage.view m |> H.map (PredictionPageMsg id)])
        |> List.intersperse (H.hr [] [])
        |> H.div []
    ]

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
  <| List.map (\(id, m) -> ViewPredictionPage.subscriptions m |> Sub.map (PredictionPageMsg id))
  <| Dict.toList model.predictions

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
