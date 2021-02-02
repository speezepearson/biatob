port module ViewMarketPage exposing (..)

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
import Utils

import StakeForm
import Biatob.Proto.Mvp exposing (StakeResult(..))
import Task

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
  , now : Time.Posix
  }

type Msg
  = SetStakeFormState StakeForm.State
  | Stake {bettorIsASkeptic:Bool, bettorStakeCents:Int}
  | StakeFinished (Result Http.Error Pb.StakeResponse)
  | Copy String
  | Tick Time.Posix
  | Ignore

creator : Model -> Pb.UserUserView
creator model = model.market.creator |> Utils.must "all markets must have creators"

certainty : Model -> Pb.CertaintyRange
certainty model = model.market.certainty |> Utils.must "all markets must have certainties"

setMarket : Pb.UserMarketView -> Model -> Model
setMarket market model = { model | market = market }

init : JD.Value -> (Model, Cmd Msg)
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
    , now = Time.millisToPosix 0
    }
  , Task.perform Tick Time.now
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
    SetStakeFormState newState ->
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
    Tick t ->
      ( { model | now = t } , Cmd.none )
    Ignore ->
      ( model , Cmd.none )

view : Model -> Html Msg
view model =
  let
    creator_ = creator model
    resolved = (model.market.resolution /= Pb.ResolutionNoneYet)
    expired = Time.posixToMillis model.now >= model.market.closesUnixtime*1000
    closeTimeString = model.market.closesUnixtime |> (*) 1000 |> Time.millisToPosix |> (\t -> "[TODO: " ++ Debug.toString t ++ "]")
    winCentsIfYes = model.market.yourTrades |> List.map (\t -> if t.bettorIsASkeptic then -t.bettorStakeCents else t.creatorStakeCents) |> List.sum
    winCentsIfNo = model.market.yourTrades |> List.map (\t -> if t.bettorIsASkeptic then t.creatorStakeCents else -t.bettorStakeCents) |> List.sum
  in
  H.div []
    [ H.h2 [] [H.text model.market.question]
    , case model.market.resolution of
        Pb.ResolutionYes ->
          H.div []
            [ H.text "This market has resolved YES. "
            , if creator_.isSelf then
                H.text "[TODO: show the creator how much they owe / are owed]"
              else if winCentsIfYes /= 0 then
                H.span []
                  [ H.text <| if winCentsIfYes > 0 then creator_.displayName ++ " owes you " else ("you owe " ++ creator_.displayName ++ " ")
                  , H.text <| Utils.formatCents <| abs winCentsIfYes
                  , H.text <| "."
                  ]
              else
                H.text ""
            ]
        Pb.ResolutionNo ->
          H.div []
            [ H.text "This market has resolved NO. "
            , if creator_.isSelf then
                H.text "[TODO: show the creator how much they owe / are owed]"
              else if winCentsIfNo /= 0 then
                H.span []
                  [ H.text <| if winCentsIfYes > 0 then creator_.displayName ++ " owes you " else ("you owe " ++ creator_.displayName ++ " ")
                  , H.text <| Utils.formatCents <| abs winCentsIfYes
                  , H.text <| "."
                  ]
              else
                H.text ""
            ]
        Pb.ResolutionNoneYet ->
          H.div []
            [ H.text <| "This market " ++ (if expired then "has closed, but " else "") ++ "hasn't resolved yet. "
            , if creator_.isSelf then
                H.text "[TODO: show the creator how much they will owe / be owed]"
              else
                H.span []
                  [ if winCentsIfYes /= 0 then
                      H.text <|
                        "If it resolves Yes, "
                        ++ (if winCentsIfYes > 0 then creator_.displayName ++ " will owe you " else "you will owe " ++ creator_.displayName ++ " ")
                        ++ Utils.formatCents (abs winCentsIfYes)
                        ++ ". "
                    else
                      H.text ""
                  , if winCentsIfNo /= 0 then
                      H.text <|
                        "If it resolves No, "
                        ++ (if winCentsIfNo > 0 then creator_.displayName ++ " will owe you " else "you will owe " ++ creator_.displayName ++ " ")
                        ++ Utils.formatCents (abs winCentsIfNo)
                        ++ ". "
                    else
                      H.text ""
                  ] 
            ]
        Pb.ResolutionUnrecognized_ _ ->
          H.span [HA.style "color" "red"]
            [H.text "Oh dear, something has gone very strange with this market. Please email TODO with this URL to report it!"]
    , case model.market.resolution of
        Pb.ResolutionYes ->
          H.text "This market has resolved YES."
        Pb.ResolutionNo ->
          H.text "This market has resolved NO."
        Pb.ResolutionNoneYet ->
          if expired then
            H.text <| "This market will close at " ++ closeTimeString
          else
            H.text ""
        Pb.ResolutionUnrecognized_ _ ->
          H.span [HA.style "color" "red"]
            [H.text "Oh dear, something has gone very strange with this market. Please email TODO with this URL to report it!"]
    , H.hr [] []
    , H.p []
        [ H.text "On "
        , model.market.createdUnixtime |> (*) 1000 |> Time.millisToPosix
            |> (\t -> "[TODO: " ++ Debug.toString t ++ "]")
            |> H.text
        , H.text ", "
        , H.strong [] [H.text (creator model).displayName]
        , H.text " assigned this a "
        , (certainty model).low |> (*) 100 |> round |> String.fromInt |> H.text
        , H.text "-"
        , (certainty model).high |> (*) 100 |> round |> String.fromInt |> H.text
        , H.text "% chance, and staked "
        , model.market.maximumStakeCents |> Utils.formatCents |> H.text
        , H.text "."
        ]
    , if resolved then
        H.text ""
      else if expired then
        H.text <| "This market closed at " ++ closeTimeString
      else
        StakeForm.view (stakeFormConfig model) model.stakeForm

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
            ++ String.fromInt (round <| (certainty model).low * 100)
            ++ "-"
            ++ String.fromInt (round <| (certainty model).high * 100)
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

stakeFormConfig : Model -> StakeForm.Config Msg
stakeFormConfig model =
  { setState = SetStakeFormState
  , onStake = Stake
  , nevermind = Ignore
  , disableCommit = (model.auth == Nothing || (creator model).isSelf)
  , market = model.market
  }

subscriptions : Model -> Sub Msg
subscriptions _ = Time.every 1000 Tick

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
