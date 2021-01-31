module CreateMarketPage exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Protobuf.Encode as PE
import Protobuf.Decode as PD
import Time

import Biatob.Proto.Mvp as Pb
import CreateMarketForm as Form
import Utils

import Market
import Maybe

type alias Model =
  { form : Form.State
  , preview : Market.State
  }

type Msg
  = SetFormState Form.State
  | SetMarketPreviewState Market.State
  | Create
  | TodoIgnore

initForDemo : () -> (Model, Cmd msg)
initForDemo _ =
  ({ form = Form.initStateForDemo
  , preview =
      { now = Time.millisToPosix 0
      , believerStakeField = "0"
      , skepticStakeField = "0"
      , market = formStateToProto Form.initStateForDemo
      }
  }
  , Cmd.none)


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetFormState newState ->
      ({ model | form = newState , preview = model.preview |> (\p -> { p | market = formStateToProto newState }) }, Cmd.none)
    Create ->
      ( model, Http.post { url = "/api/create_market"
      , body = Http.bytesBody "application/octet-stream"
        <| PE.encode
        <| Pb.toCreateMarketRequestEncoder
        { question = Form.question model.form
        , privacy = Nothing  -- TODO: delete this field
        , certainty = Just {
          low = Utils.must "can't parse lowP" <| Form.lowP model.form
          , high = Utils.must "can't parse highP" <| Form.highP model.form
        }
        , maximumStakeCents = Utils.must "can't parse stake" <| Form.stakeCents model.form
        , openSeconds = Maybe.withDefault 0 <| Form.openForSeconds model.form
        , specialRules = model.form.specialRulesField
        }
      , expect = PD.expectBytes (always TodoIgnore) Pb.getMarketResponseDecoder } )
    SetMarketPreviewState newPreview ->
      ({ model | preview = newPreview }, Cmd.none)
    TodoIgnore ->
      (model, Cmd.none)

view : Model -> Html Msg
view model =
  H.div []
    [ Form.view formConfig model.form
    , H.br [] []
    , H.button
        [ HE.onClick Create ]
        [ H.text "Create" ]
    , H.hr [] []
    , H.text "Preview:"
    , H.div [HA.style "border" "1px solid black", HA.style "padding" "1em", HA.style "margin" "1em"]
        [Market.view previewConfig model.preview]
    ]

formConfig : Form.Config Msg
formConfig =
  { setState = SetFormState
  }

previewConfig : Market.Config Msg
previewConfig =
  { setState = SetMarketPreviewState
  , onStake = (\_ _ -> TodoIgnore)
  , nevermind = TodoIgnore
  }

formStateToProto : Form.State -> Pb.GetMarketResponseMarket
formStateToProto form =
  { question = Form.question form
  , certainty = Just {low = Form.lowP form |> Maybe.withDefault 0, high = Form.highP form |> Maybe.withDefault 1}
  , maximumStakeCents = Form.stakeCents form |> Maybe.withDefault 0
  , remainingStakeCentsVsBelievers = Form.stakeCents form |> Maybe.withDefault 0
  , remainingStakeCentsVsSkeptics = Form.stakeCents form |> Maybe.withDefault 0
  , createdUnixtime = 0 -- TODO
  , closesUnixtime = 0 + (Form.openForSeconds form |> Maybe.withDefault 0) -- TODO
  , specialRules = form.specialRulesField
  , creator = Just {displayName = "Spencer"} -- TODO
  , resolution = Pb.ResolutionNoneYet
  , yourTrades = []
  }

main : Program () Model Msg
main =
  Browser.element
    { init = initForDemo
    , subscriptions = \_ -> Sub.none
    , view = view
    , update = update
    }
