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
import StakeForm
import Task

port createdMarket : Int -> Cmd msg

type alias Model =
  { form : Form.State
  , preview : ViewMarketPage.Model
  , auth : Maybe Pb.AuthToken
  , working : Bool
  , createError : Maybe String
  , now : Time.Posix
  }

type Msg
  = SetFormState Form.State
  | PreviewMsg ViewMarketPage.Msg
  | Create
  | CreateFinished (Result Http.Error Pb.CreateMarketResponse)
  | Tick Time.Posix
  | TodoIgnore

epoch = Time.millisToPosix 0

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
    previewModel : ViewMarketPage.Model
    previewModel =
      { stakeForm = StakeForm.init
      , market = formStateToProto {now=epoch, form=Form.init, creatorName=authName auth}
      , marketId = 12345
      , auth = Just dummyAuthToken
      , working = False
      , stakeError = Nothing
      , resolveError = Nothing
      , now = epoch
      , resolutionNotes = ""
      }
  in
  ( { form = Form.init
    , preview = previewModel
    , auth = auth
    , working = False
    , createError = Nothing
    , now = Time.millisToPosix 0
    }
  , Task.perform Tick Time.now
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
    SetFormState newState ->
      ({ model | form = newState , preview = model.preview |> ViewMarketPage.setMarket (formStateToProto {now=model.now, form=newState, creatorName=authName model.auth}) }, Cmd.none)
    Create ->
      case (Form.lowP model.form, Form.highP model.form, Form.stakeCents model.form) of
        (Just lowP, Just highP, Just stakeCents) ->
          ( { model | working = True , createError = Nothing }
          , postCreate
              { question = Form.question model.form
              , privacy = Nothing  -- TODO: delete this field
              , certainty = Just { low=lowP, high=highP }
              , maximumStakeCents = stakeCents
              , openSeconds = Maybe.withDefault 0 <| Form.openForSeconds model.form
              , specialRules = model.form.specialRulesField
              }
          )
        _ ->
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

    PreviewMsg previewMsg ->
      let (newPreview, cmd) = ViewMarketPage.update previewMsg model.preview in
      ( { model | preview = newPreview }, Cmd.map PreviewMsg cmd)

    Tick t ->
      if model.now == epoch then
        ( { model | now = t } |> update (SetFormState model.form) |> Tuple.first
        , Cmd.none
        )
      else
        let (newPreview, cmd) = ViewMarketPage.update (ViewMarketPage.Tick t) model.preview in
        ( { model | now = t, preview = newPreview } , Cmd.map PreviewMsg cmd )

    TodoIgnore ->
      (model, Cmd.none)

view : Model -> Html Msg
view model =
  H.div []
    [ Form.view (formConfig model) model.form
    , H.br [] []
    , H.button
        [ HE.onClick Create
        , HA.disabled (model.auth == Nothing || Form.isInvalid model.form || model.working)
        ]
        [ H.text <| if model.auth == Nothing then "Log in to create" else "Create" ]
    , case model.createError of
        Just e -> H.div [HA.style "color" "red"] [H.text e]
        Nothing -> H.text ""
    , H.hr [] []
    , H.text "Preview:"
    , H.div [HA.style "border" "1px solid black", HA.style "padding" "1em", HA.style "margin" "1em"]
        [H.map PreviewMsg (ViewMarketPage.view model.preview)]
    ]

formConfig : Model -> Form.Config Msg
formConfig model =
  { setState = SetFormState
  , disabled = (model.auth == Nothing)
  }

formStateToProto : {now:Time.Posix, form:Form.State, creatorName:String} -> Pb.UserMarketView
formStateToProto {now, form, creatorName} =
  { question = Form.question form
  , certainty = Just
      { low = Form.lowP form |> Maybe.withDefault 0
      , high = Form.highP form |> Maybe.withDefault 1
      }
  , maximumStakeCents = Form.stakeCents form |> Maybe.withDefault 0
  , remainingStakeCentsVsBelievers = Form.stakeCents form |> Maybe.withDefault 0
  , remainingStakeCentsVsSkeptics = Form.stakeCents form |> Maybe.withDefault 0
  , createdUnixtime = Time.posixToMillis now // 1000 -- TODO
  , closesUnixtime = Time.posixToMillis now // 1000 + (Form.openForSeconds form |> Maybe.withDefault 0) -- TODO
  , specialRules = form.specialRulesField
  , creator = Just {displayName = creatorName, isSelf=False, trustsYou=True, isTrusted=True}
  , resolutions = []
  , yourTrades = []
  }

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ Time.every 1000 Tick
    , Sub.map PreviewMsg <| ViewMarketPage.subscriptions model.preview
    ]

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
