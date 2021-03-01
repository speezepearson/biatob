module Elements.CreatePrediction exposing (main)

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
import Utils
import Page
import Page.Program

type alias Model =
  { form : Form.Model
  , working : Bool
  , createError : Maybe String
  }

type Msg
  = FormMsg Form.Msg
  | Create Time.Posix Time.Zone
  | CreateFinished (Result Http.Error Pb.CreatePredictionResponse)
  | Ignore

authName : Maybe Pb.AuthToken -> String
authName auth =
  auth
  |> Maybe.map Utils.mustTokenOwner
  |> Maybe.map Utils.renderUserPlain
  |> Maybe.withDefault "[Creator]"

init : Model
init =
  { form = Form.init
  , working = False
  , createError = Nothing
  }

update : Msg -> Model -> (Model, Page.Command Msg)
update msg model =
  case msg of
    FormMsg widgetMsg ->
      let (newWidget, innerCmd) = Form.update widgetMsg model.form in
      ( { model | form = newWidget } , Page.mapCmd FormMsg innerCmd )
    Create now zone ->
      case Form.toCreateRequest now zone model.form of
        Just req ->
          ( { model | working = True , createError = Nothing }
          , Page.RequestCmd <| Page.CreatePredictionRequest CreateFinished req
          )
        Nothing ->
          ( { model | createError = Just "bad form" } -- TODO: improve error message
          , Page.NoCmd
          )
    CreateFinished (Err e) ->
      ( { model | working = False , createError = Just (Debug.toString e) }
      , Page.NoCmd
      )
    CreateFinished (Ok resp) ->
      case resp.createPredictionResult of
        Just (Pb.CreatePredictionResultNewPredictionId id) ->
          ( model
          , Page.NavigateCmd <| Just <| "/p/" ++ String.fromInt id
          )
        Just (Pb.CreatePredictionResultError e) ->
          ( { model | working = False , createError = Just (Debug.toString e) }
          , Page.NoCmd
          )
        Nothing ->
          ( { model | working = False , createError = Just "Invalid server response (neither Ok nor Error in protobuf)" }
          , Page.NoCmd
          )
    Ignore ->
      (model, Page.NoCmd)

view : Page.Globals -> Model -> Browser.Document Msg
view globals model =
  {title="New prediction", body = [H.main_ [HA.id "main", HA.style "text-align" "justify"]
    [ H.h2 [] [H.text "New Prediction"]
    , case Page.getAuth globals of
       Just _ -> H.text ""
       Nothing ->
        H.div []
          [ H.span [HA.style "color" "red"] [H.text "You need to log in to create a new prediction!"]
          , H.hr [] []
          ]
    , Form.view globals model.form |> H.map FormMsg
    , H.div [HA.style "text-align" "center", HA.style "margin-bottom" "2em"]
        [ H.button
            [ HE.onClick (Create globals.now globals.timeZone)
            , HA.disabled (not (Page.isLoggedIn globals) || Form.toCreateRequest globals.now globals.timeZone model.form == Nothing || model.working)
            ]
            [ H.text <| if Page.isLoggedIn globals then "Create" else "Log in to create" ]
        ]
    , case model.createError of
        Just e -> H.div [HA.style "color" "red"] [H.text e]
        Nothing -> H.text ""
    , H.hr [] []
    , H.text "Preview:"
    , H.div [HA.style "border" "1px solid black", HA.style "padding" "1em", HA.style "margin" "1em"]
        [ case Form.toCreateRequest globals.now globals.timeZone model.form of
            Just req ->
              previewPrediction {request=req, creatorName=Page.getAuth globals |> authName, createdAt=globals.now}
              |> (\prediction -> PredictionWidget.view
                    {prediction=prediction, predictionId=12345, shouldLinkTitle = False}
                    globals
                    (PredictionWidget.init 12345)
                    |> H.map (always Ignore))
            Nothing ->
              H.span [HA.style "color" "red"] [H.text "(invalid prediction)"]
        ]
    ]]}

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
subscriptions _ = Sub.none

pagedef : Page.Element Model Msg
pagedef = {init=\_ -> (init, Page.NoCmd), view=view, update=update, subscriptions=subscriptions}

main = Page.Program.page pagedef
