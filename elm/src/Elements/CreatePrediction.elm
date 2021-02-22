port module Elements.CreatePrediction exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD
import Time
import Bytes.Encode
import Time
import Task

import Biatob.Proto.Mvp as Pb
import Widgets.CreatePredictionWidget as Form
import Utils

import Widgets.PredictionWidget as PredictionWidget
import API
import Utils

port createdPrediction : Int -> Cmd msg

type alias Model =
  { form : Form.State
  , auth : Maybe Pb.AuthToken
  , working : Bool
  , createError : Maybe String
  , now : Time.Posix
  }

type Msg
  = FormEvent (Maybe Form.Event) Form.State
  | Create
  | CreateFinished (Result Http.Error Pb.CreatePredictionResponse)
  | Tick Time.Posix
  | Ignore

authName : Maybe Pb.AuthToken -> String
authName auth =
  auth
  |> Maybe.map Utils.mustTokenOwner
  |> Maybe.map Utils.renderUserPlain
  |> Maybe.withDefault "[Creator]"

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    auth : Maybe Pb.AuthToken
    auth =  Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
  in
  ( { form = Form.init
    , auth = auth
    , working = False
    , createError = Nothing
    , now = Utils.unixtimeToTime 0
    }
  , Task.perform Tick Time.now
  )

formCtx : Model -> Form.Context Msg
formCtx model =
  { handle = FormEvent
  , now = model.now
  , disabled = (model.auth == Nothing)
  }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    FormEvent event newState ->
      (case event of
        Nothing ->     ( model , Cmd.none )
        Just Form.Ignore -> ( model , Cmd.none )
      ) |> Tuple.mapFirst (\m -> { m | form = newState })
    Create ->
      case Form.toCreateRequest (formCtx model) model.form of
        Just req ->
          ( { model | working = True , createError = Nothing }
          , API.postCreate CreateFinished req
          )
        Nothing ->
          ( { model | createError = Just "bad form" } -- TODO: improve error message
          , Cmd.none
          )
    CreateFinished (Err e) ->
      ( { model | working = False , createError = Just (Debug.toString e) }
      , Cmd.none
      )
    CreateFinished (Ok resp) ->
      case resp.createPredictionResult of
        Just (Pb.CreatePredictionResultNewPredictionId id) ->
          ( model
          , createdPrediction id
          )
        Just (Pb.CreatePredictionResultError e) ->
          ( { model | working = False , createError = Just (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , createError = Just "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )
    Tick t ->
      ( { model | now = t } , Cmd.none )
    Ignore ->
      (model, Cmd.none)

view : Model -> Html Msg
view model =
  H.div []
    [ H.h2 [] [H.text "New Prediction"]
    , case model.auth of
       Just _ -> H.text ""
       Nothing ->
        H.div []
          [ H.span [HA.style "color" "red"] [H.text "You need to log in to create a new prediction!"]
          , H.hr [] []
          ]
    , Form.view (formCtx model) model.form
    , H.div [HA.style "text-align" "center", HA.style "margin-bottom" "2em"]
        [ H.button
            [ HE.onClick Create
            , HA.disabled (model.auth == Nothing || Form.toCreateRequest (formCtx model) model.form == Nothing || model.working)
            ]
            [ H.text <| if model.auth == Nothing then "Log in to create" else "Create" ]
        ]
    , case model.createError of
        Just e -> H.div [HA.style "color" "red"] [H.text e]
        Nothing -> H.text ""
    , H.hr [] []
    , H.text "Preview:"
    , H.div [HA.style "border" "1px solid black", HA.style "padding" "1em", HA.style "margin" "1em"]
        [ case Form.toCreateRequest (formCtx model) model.form of
            Just req ->
              previewPrediction {request=req, creatorName=authName model.auth, createdAt=model.now}
              |> (\prediction -> PredictionWidget.view
                    {prediction=prediction, predictionId=12345, auth=model.auth, now=model.now, httpOrigin="http://dummy", handle = \_ _ -> Ignore}
                    PredictionWidget.init)
            Nothing ->
              H.span [HA.style "color" "red"] [H.text "(invalid prediction)"]
        ]
    ]

previewPrediction : {request:Pb.CreatePredictionRequest, creatorName:String, createdAt:Time.Posix} -> Pb.UserPredictionView
previewPrediction {request, creatorName, createdAt} =
  { prediction = request.prediction
  , certainty = request.certainty
  , maximumStakeCents = request.maximumStakeCents
  , remainingStakeCentsVsBelievers = request.maximumStakeCents
  , remainingStakeCentsVsSkeptics = request.maximumStakeCents
  , createdUnixtime = Utils.timeToUnixtime createdAt
  , closesUnixtime = Utils.timeToUnixtime createdAt + toFloat request.openSeconds
  , specialRules = request.specialRules
  , creator = Just {displayName = creatorName, isSelf=False, trustsYou=True, isTrusted=True}
  , resolutions = []
  , yourTrades = []
  , resolvesAtUnixtime = request.resolvesAtUnixtime
  }

subscriptions : Model -> Sub Msg
subscriptions model =
  Time.every 1000 Tick

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
