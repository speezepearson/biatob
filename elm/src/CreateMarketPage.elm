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

import StakeForm

port createdMarket : Int -> Cmd msg

type alias Model =
  { form : Form.State
  , preview : StakeForm.State
  , auth : Maybe Pb.AuthToken
  , working : Bool
  , createError : Maybe String
  }

type Msg
  = SetFormState Form.State
  | SetMarketPreviewState StakeForm.State
  | Create
  | CreateFinished (Result Http.Error Pb.CreateMarketResponse)
  | TodoIgnore

init : JD.Value -> (Model, Cmd msg)
init flags =
  ( { form = Form.init
    , preview =
        { now = Time.millisToPosix 0
        , believerStakeField = "0"
        , skepticStakeField = "0"
        }
    , auth = flags |> JD.decodeValue (JD.field "authTokenPbB64" JD.string)
        |> Result.map (Debug.log "init auth token")
        |> Result.mapError (Debug.log "error decoding initial auth token")
        |> Result.toMaybe
        |> Maybe.andThen (Utils.decodePbB64 Pb.authTokenDecoder)
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
    SetFormState newState ->
      ({ model | form = newState }, Cmd.none)
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

    SetMarketPreviewState newPreview ->
      ({ model | preview = newPreview }, Cmd.none)
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
        [StakeForm.view (previewConfig model) model.preview]
    ]

formConfig : Model -> Form.Config Msg
formConfig model =
  { setState = SetFormState
  , disabled = (model.auth == Nothing)
  }

previewConfig : Model -> StakeForm.Config Msg
previewConfig model =
  { setState = SetMarketPreviewState
  , onStake = (\_ -> TodoIgnore)
  , nevermind = TodoIgnore
  , disableCommit = True
  , market = (formStateToProto model.form)
  }

formStateToProto : Form.State -> Pb.UserMarketView
formStateToProto form =
  { question = Form.question form
  , certainty = Just
      { low = Form.lowP form |> Maybe.withDefault 0
      , high = Form.highP form |> Maybe.withDefault 1
      }
  , maximumStakeCents = Form.stakeCents form |> Maybe.withDefault 0
  , remainingStakeCentsVsBelievers = Form.stakeCents form |> Maybe.withDefault 0
  , remainingStakeCentsVsSkeptics = Form.stakeCents form |> Maybe.withDefault 0
  , createdUnixtime = 0 -- TODO
  , closesUnixtime = 0 + (Form.openForSeconds form |> Maybe.withDefault 0) -- TODO
  , specialRules = form.specialRulesField
  , creator = Just {displayName = "You", isSelf=True}
  , resolution = Pb.ResolutionNoneYet
  , yourTrades = []
  }

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = \_ -> Sub.none
    , view = view
    , update = update
    }
