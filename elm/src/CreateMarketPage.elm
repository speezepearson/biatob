port module CreateMarketPage exposing (..)

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

import Biatob.Proto.Mvp as Pb
import CreateMarketForm as Form
import Utils

import ViewMarketPage
import Http exposing (request)

port createdMarket : Int -> Cmd msg

type alias Model =
  { form : Form.Model
  , auth : Maybe Pb.AuthToken
  , working : Bool
  , createError : Maybe String
  }

type Msg
  = FormMsg Form.Msg
  | Create
  | CreateFinished (Result Http.Error Pb.CreateMarketResponse)
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
  in
  ( { form = Form.init |> if auth == Nothing then Form.disable else Form.enable
    , auth = auth
    , working = False
    , createError = Nothing
    }
  , Cmd.none
  )

postCreate : Pb.CreateMarketRequest -> Cmd Msg
postCreate req =
  Http.post
    { url = "/api/CreateMarket"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toCreateMarketRequestEncoder req
    , expect = PD.expectBytes CreateFinished Pb.createMarketResponseDecoder }


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    FormMsg formMsg ->
      ({ model | form = model.form |> Form.update formMsg }, Cmd.none)
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
      case resp.createMarketResult of
        Just (Pb.CreateMarketResultNewMarketId id) ->
          ( model
          , createdMarket id
          )
        Just (Pb.CreateMarketResultError e) ->
          ( { model | working = False , createError = Just (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , createError = Just "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )

    Ignore ->
      (model, Cmd.none)

view : Model -> Html Msg
view model =
  H.div []
    [ case model.auth of
       Just _ -> H.text ""
       Nothing ->
        H.div []
          [ H.span [HA.style "color" "red"] [H.text "You need to log in to create a market!"]
          , H.hr [] []
          ]
    , Form.view model.form |> H.map FormMsg
    , H.br [] []
    , H.button
        [ HE.onClick Create
        , HA.disabled (model.auth == Nothing || Form.toCreateRequest model.form == Nothing || model.working)
        ]
        [ H.text <| if model.auth == Nothing then "Log in to create" else "Create" ]
    , case model.createError of
        Just e -> H.div [HA.style "color" "red"] [H.text e]
        Nothing -> H.text ""
    , H.hr [] []
    , H.text "Preview:"
    , H.div [HA.style "border" "1px solid black", HA.style "padding" "1em", HA.style "margin" "1em"]
        [ case Form.toCreateRequest model.form of
            Just req ->
              previewMarket {request=req, creatorName=authName model.auth}
              |> (\market -> ViewMarketPage.initBase {market=market, marketId=12345, auth=model.auth})
              |> Tuple.first
              |> ViewMarketPage.view
              |> H.map (always Ignore)
            Nothing ->
              H.span [HA.style "color" "red"] [H.text "(invalid market)"]
        ]
    ]

previewMarket : {request:Pb.CreateMarketRequest, creatorName:String} -> Pb.UserMarketView
previewMarket {request, creatorName} =
  { question = request.question
  , certainty = request.certainty
  , maximumStakeCents = request.maximumStakeCents
  , remainingStakeCentsVsBelievers = request.maximumStakeCents
  , remainingStakeCentsVsSkeptics = request.maximumStakeCents
  , createdUnixtime = 0
  , closesUnixtime = request.openSeconds
  , specialRules = request.specialRules
  , creator = Just {displayName = creatorName, isSelf=False, trustsYou=True, isTrusted=True}
  , resolutions = []
  , yourTrades = []
  }

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
