port module CreatePredictionPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD
import Protobuf.Encode as PE
import Protobuf.Decode as PD
import Time
import Bytes.Encode
import Time
import Task

import Biatob.Proto.Mvp as Pb
import CreatePredictionForm as Form
import Utils

import ViewPredictionPage
import Http exposing (request)

port createdPrediction : Int -> Cmd msg

type alias Model =
  { form : Form.Model
  , auth : Maybe Pb.AuthToken
  , working : Bool
  , createError : Maybe String
  , now : Time.Posix
  }

type Msg
  = FormMsg Form.Msg
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

dummyAuthToken : Pb.AuthToken
dummyAuthToken =
  { owner = Just {kind = Just (Pb.KindUsername "testuser")}
  , mintedUnixtime=0
  , expiresUnixtime=99999999999
  , hmacOfRest=Bytes.Encode.encode <| Bytes.Encode.string ""
  }

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    auth : Maybe Pb.AuthToken
    auth =  Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    (form, formCmd) = Form.init ()
  in
  ( { form = form |> if auth == Nothing then Form.disable else Form.enable
    , auth = auth
    , working = False
    , createError = Nothing
    , now = Time.millisToPosix 0
    }
  , Cmd.batch [Task.perform Tick Time.now, Cmd.map FormMsg formCmd]
  )

postCreate : Pb.CreatePredictionRequest -> Cmd Msg
postCreate req =
  Http.post
    { url = "/api/CreatePrediction"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toCreatePredictionRequestEncoder req
    , expect = PD.expectBytes CreateFinished Pb.createPredictionResponseDecoder }


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    FormMsg formMsg ->
      let (newForm, formCmd) = Form.update formMsg model.form in
      ({ model | form = newForm }, Cmd.map FormMsg formCmd)
    Create ->
      case Form.toCreateRequest model.form of
        Just req ->
          ( { model | working = True , createError = Nothing }
          , postCreate req
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
    , Form.view model.form |> H.map FormMsg
    , H.div [HA.style "text-align" "center", HA.style "margin-bottom" "2em"]
        [ H.button
            [ HE.onClick Create
            , HA.disabled (model.auth == Nothing || Form.toCreateRequest model.form == Nothing || model.working)
            ]
            [ H.text <| if model.auth == Nothing then "Log in to create" else "Create" ]
        ]
    , case model.createError of
        Just e -> H.div [HA.style "color" "red"] [H.text e]
        Nothing -> H.text ""
    , H.hr [] []
    , H.text "Preview:"
    , H.div [HA.style "border" "1px solid black", HA.style "padding" "1em", HA.style "margin" "1em"]
        [ case Form.toCreateRequest model.form of
            Just req ->
              previewPrediction {request=req, creatorName=authName model.auth, createdAt=model.now}
              |> (\prediction -> ViewPredictionPage.initBase {prediction=prediction, predictionId=12345, auth=model.auth, now=model.now})
              |> Tuple.first
              |> ViewPredictionPage.view
              |> H.map (always Ignore)
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
  , createdUnixtime = Time.posixToMillis createdAt // 1000
  , closesUnixtime = Time.posixToMillis createdAt // 1000 + request.openSeconds
  , specialRules = request.specialRules
  , creator = Just {displayName = creatorName, isSelf=False, trustsYou=True, isTrusted=True}
  , resolutions = []
  , yourTrades = []
  , resolvesAtUnixtime = request.resolvesAtUnixtime
  }

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ Time.every 1000 Tick
    , Form.subscriptions model.form |> Sub.map FormMsg
    ]

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
