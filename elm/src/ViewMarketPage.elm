port module ViewMarketPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD
import Protobuf.Encode as PE
import Protobuf.Decode as PD

import Biatob.Proto.Mvp as Pb
import Utils

import StakeForm
import Biatob.Proto.Mvp exposing (StakeResult(..))

port staked : () -> Cmd msg
port copy : String -> Cmd msg

type alias Model =
  { stakeForm : StakeForm.State
  , linkToAuthority : String
  , market : Pb.UserMarketView
  , marketId : Int
  , auth : Maybe Pb.AuthToken
  , working : Bool
  , stakeError : Maybe String
  }

type Msg
  = SetMarketState StakeForm.State
  | Stake {bettorIsASkeptic:Bool, bettorStakeCents:Int}
  | StakeFinished (Result Http.Error Pb.StakeResponse)
  | Copy String
  | Ignore

creator : Model -> Pb.UserUserView
creator model = model.market.creator |> Utils.must "all markets must have creators"

init : JD.Value -> (Model, Cmd msg)
init flags =
  ( { stakeForm = StakeForm.init
    , linkToAuthority = flags |> JD.decodeValue (JD.field "linkToAuthority" JD.string)
        |> Debug.log "linkToAuthority"
        |> Result.withDefault "http://example.com"
    , market = flags |> JD.decodeValue (JD.field "marketPbB64" JD.string)
        |> Debug.log "init market"
        |> Result.toMaybe
        |> Maybe.andThen (Utils.decodePbB64 Pb.userMarketViewDecoder)
        |> Utils.must "no/invalid market from server"
    , marketId = flags |> JD.decodeValue (JD.field "marketId" JD.int)
        |> Debug.log "init auth token"
        |> Result.toMaybe
        |> Utils.must "no marketId from server"
    , auth = flags |> JD.decodeValue (JD.field "authTokenPbB64" JD.string)
        |> Debug.log "init auth token"
        |> Result.toMaybe
        |> Maybe.andThen (Utils.decodePbB64 Pb.authTokenDecoder)
    , working = False
    , stakeError = Nothing
    }
  , Cmd.none
  )

postStake : Pb.StakeRequest -> Cmd Msg
postStake req =
  Http.post
    { url = "/api/Stake"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toStakeRequestEncoder req
    , expect = PD.expectBytes StakeFinished Pb.stakeResponseDecoder }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetMarketState newState ->
      ({ model | stakeForm = newState }, Cmd.none)
    Stake {bettorIsASkeptic, bettorStakeCents} ->
      ( { model | working = True , stakeError = Nothing }
      , postStake {marketId=model.marketId, bettorIsASkeptic=bettorIsASkeptic, bettorStakeCents=bettorStakeCents}
      )
    StakeFinished (Err e) ->
      ( { model | working = False , stakeError = Just (Debug.toString e) }
      , Cmd.none
      )
    StakeFinished (Ok resp) ->
      case resp.stakeResult of
        Just (Pb.StakeResultOk _) ->
          ( model
          , staked ()
          )
        Just (Pb.StakeResultError e) ->
          ( { model | working = False , stakeError = Just (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , stakeError = Just "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )
    Copy id ->
      ( model , copy id )
    Ignore ->
      ( model , Cmd.none )

view : Model -> Html Msg
view model =
  H.div []
    [ StakeForm.view (marketConfig model) model.stakeForm
    , case model.stakeError of
        Just e -> H.div [HA.style "color" "red"] [H.text e]
        Nothing -> H.text ""
    , if (creator model).isSelf then
        let
          linkUrl = model.linkToAuthority ++ "/market/" ++ String.fromInt model.marketId
          imgUrl = model.linkToAuthority ++ "/market/" ++ String.fromInt model.marketId ++ "/embed.png"
          imgStyles = [("max-height","1.5ex"), ("border-bottom","1px solid #008800")]
          imgCode =
            "<a href=\"" ++ linkUrl ++ "\">"
            ++ "<img style=\"" ++ (imgStyles |> List.map (\(k,v) -> k++":"++v) |> String.join ";") ++ "\" src=\"" ++ imgUrl ++ "\" /></a>"
          linkStyles = [("max-height","1.5ex")]
          linkText =
            "["
            ++ Utils.formatCents (model.market.maximumStakeCents // 100 * 100)
            ++ " @ "
            ++ String.fromInt (round <| (model.market.certainty |> Utils.must "TODO").low * 100)
            ++ "-"
            ++ String.fromInt (round <| (model.market.certainty |> Utils.must "TODO").high * 100)
            ++ "%]"
          linkCode =
            "<a style=\"" ++ (linkStyles |> List.map (\(k,v) -> k++":"++v) |> String.join ";") ++ "\" href=\"" ++ linkUrl ++ "\">" ++ linkText ++ "</a>"
        in
        H.div []
          [ H.hr [] []
          , H.text "As the creator of this market, you might want to link to it in your writing! Here are some snippets of HTML you could copy-paste."
          , H.ul []
            [ H.li [] <|
              [ H.text "A linked inline image: "
              , H.input [HA.id "imgCopypasta", HA.style "font" "monospace", HA.value imgCode] []
              , H.button [HE.onClick (Copy "imgCopypasta")] [H.text "Copy"]
              , H.br [] []
              , H.text "This would render as: "
              , H.a [HA.href linkUrl]
                [ H.img (HA.src imgUrl :: (imgStyles |> List.map (\(k,v) -> HA.style k v))) []]
              ]
            , H.li [] <|
              [ H.text "A boring old link: "
              , H.input [HA.id "linkCopypasta", HA.style "font" "monospace", HA.value linkCode] []
              , H.button [HE.onClick (Copy "linkCopypasta")] [H.text "Copy"]
              , H.br [] []
              , H.text "This would render as: "
              , H.a (HA.href linkUrl :: (linkStyles |> List.map (\(k,v) -> HA.style k v))) [H.text linkText]
              ]
            ]
          ]
      else
        H.text ""
    ]

marketConfig : Model -> StakeForm.Config Msg
marketConfig model =
  { setState = SetMarketState
  , onStake = Stake
  , nevermind = Ignore
  , disableCommit = (model.auth == Nothing || (creator model).isSelf)
  , market = model.market
  }

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = \_ -> Sub.none
    , view = view
    , update = update
    }
