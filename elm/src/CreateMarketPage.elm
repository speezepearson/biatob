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

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    previewModel : ViewMarketPage.Model
    previewModel =
      { stakeForm = StakeForm.init
      , linkToAuthority = "http://example.com"
      , market = formStateToProto epoch Form.init
      , marketId = 12345
      , auth = Nothing
      , working = False
      , stakeError = Nothing
      , now = epoch
      }
  in
  ( { form = Form.init
    , preview = previewModel
    , auth = flags |> JD.decodeValue (JD.field "authTokenPbB64" JD.string)
        |> Debug.log "init auth token"
        |> Result.toMaybe
        |> Maybe.andThen (Utils.decodePbB64 Pb.authTokenDecoder)
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
      ({ model | form = newState , preview = model.preview |> ViewMarketPage.setMarket (formStateToProto model.now newState) }, Cmd.none)
    Create ->
      ( { model | working = True , createError = Nothing }
      , postCreate
          { question = Form.question model.form
          , privacy = Nothing  -- TODO: delete this field
          , certainty = Just
              { low = Utils.must "can't parse lowP" <| Form.lowP model.form
              , high = Utils.must "can't parse highP" <| Form.highP model.form
              }
          , maximumStakeCents = Utils.must "can't parse stake" <| Form.stakeCents model.form
          , openSeconds = Maybe.withDefault 0 <| Form.openForSeconds model.form
          , specialRules = model.form.specialRulesField
          }
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
        Just e -> H.div [HA.style "color" "red"] [H.text <| Debug.toString e]
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

formStateToProto : Time.Posix -> Form.State -> Pb.UserMarketView
formStateToProto now form =
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
  , creator = Just {displayName = "[TODO]", isSelf=False, trustsYou=True, isTrusted=True}
  , resolution = Pb.ResolutionNoneYet
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
