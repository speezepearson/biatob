module CreateMarketPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Time

import Biatob.Proto.Mvp as Pb
import CreateMarketForm as Form
import Market

type alias Model =
  { form : Form.State
  , preview : Market.State
  }

type Msg
  = SetFormState Form.State
  | SetMarketPreviewState Market.State
  | Create
  | TodoIgnore

initForDemo : Model
initForDemo =
  { form = Form.initStateForDemo
  , preview =
      { now = Time.millisToPosix 0
      , stakeYesField = "0"
      , stakeNoField = "0"
      , market = formStateToProto Form.initStateForDemo
      , userPosition = { winCentsIfYes = 0 , winCentsIfNo = 0 }
      }
  }


update : Msg -> Model -> Model
update msg model =
  case msg of
    SetFormState newState ->
      { model | form = newState , preview = model.preview |> (\p -> { p | market = formStateToProto newState }) }
    Create ->
      Debug.log "would have created market" model
    SetMarketPreviewState newPreview ->
      { model | preview = newPreview }
    TodoIgnore ->
      model

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
  , remainingYesStakeCents = Form.stakeCents form |> Maybe.withDefault 0
  , remainingNoStakeCents = Form.stakeCents form |> Maybe.withDefault 0
  , createdUnixtime = 0 -- TODO
  , closesUnixtime = 0 + (Form.openForSeconds form |> Maybe.withDefault 0) -- TODO
  , specialRules = form.specialRulesField
  , creator = Just {displayName = "Spencer" , pronouns = Pb.HeHim} -- TODO
  , resolution = Pb.ResolutionNoneYet
  }

main : Program () Model Msg
main =
  Browser.sandbox
    { init = initForDemo
    , view = view
    , update = update
    }
