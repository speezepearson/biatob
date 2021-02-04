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
import Dict as D exposing (Dict)

import Biatob.Proto.Mvp as Pb
import Utils

import StakeForm
import Biatob.Proto.Mvp exposing (StakeResult(..))
import Task

port changed : () -> Cmd msg
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
  , resolutionNotes : String
  }

type Msg
  = SetStakeFormState StakeForm.State
  | Stake {bettorIsASkeptic:Bool, bettorStakeCents:Int}
  | StakeFinished (Result Http.Error Pb.StakeResponse)
  | SetResolutionNotes String
  | Resolve Pb.Resolution
  | ResolveFinished (Result Http.Error Pb.ResolveResponse)
  | Copy String
  | Tick Time.Posix
  | Ignore

setMarket : Pb.UserMarketView -> Model -> Model
setMarket market model = { model | market = market }

init : JD.Value -> (Model, Cmd Msg)
init flags =
  ( { stakeForm = StakeForm.init
    , linkToAuthority = Utils.mustDecodeFromFlags JD.string "linkToAuthority" flags
    , market = Utils.mustDecodePbFromFlags Pb.userMarketViewDecoder "marketPbB64" flags
    , marketId = Utils.mustDecodeFromFlags JD.int "marketId" flags
    , auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    , working = False
    , stakeError = Nothing
    , now = Time.millisToPosix 0
    , resolutionNotes = ""
    }
  , Task.perform Tick Time.now
  )

postStake : Pb.StakeRequest -> Cmd Msg
postStake req =
  Http.post
    { url = "/api/Stake"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toStakeRequestEncoder req
    , expect = PD.expectBytes StakeFinished Pb.stakeResponseDecoder }

postResolve : Pb.ResolveRequest -> Cmd Msg
postResolve req =
  Http.post
    { url = "/api/Resolve"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toResolveRequestEncoder req
    , expect = PD.expectBytes ResolveFinished Pb.resolveResponseDecoder }

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
          , changed ()
          )
        Just (Pb.StakeResultError e) ->
          ( { model | working = False , stakeError = Just (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , stakeError = Just "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )
    SetResolutionNotes s ->
      ( { model | resolutionNotes = s } , Cmd.none )
    Resolve resolution ->
      ( { model | working = True , stakeError = Nothing }
      , postResolve {marketId=model.marketId, resolution=resolution, notes = ""}
      )
    ResolveFinished (Err e) ->
      ( { model | working = False , stakeError = Just (Debug.toString e) }
      , Cmd.none
      )
    ResolveFinished (Ok resp) ->
      case resp.resolveResult of
        Just (Pb.ResolveResultOk _) ->
          ( model
          , changed ()
          )
        Just (Pb.ResolveResultError e) ->
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

viewStakeFormOrExcuse : Model -> Html Msg
viewStakeFormOrExcuse model =
  let creator = Utils.mustMarketCreator model.market in
  if Utils.resolutionIsTerminal (Utils.currentResolution model.market) then
    H.text "This market has resolved, so cannot be bet in."
  else if Utils.secondsToClose model.now model.market <= 0 then
    H.text <| "This market closed on " ++ Utils.dateStr Time.utc (Utils.marketClosesTime model.market) ++ " (UTC)."
  else case model.auth of
    Nothing ->
      H.div []
        [ H.text "You must be logged in to participate in this market!"
        , StakeForm.view (stakeFormConfig model) model.stakeForm
        ]
    Just auth_ ->
      if creator.isSelf then
        H.text ""
      else if not creator.trustsYou then
        let
          userPagePath =
            auth_
            |> Utils.mustTokenOwner
            |> Utils.mustUserKind
            |> (\k -> case k of
                Pb.KindUsername username -> "/username/" ++ username
                )
          userPageUrl = model.linkToAuthority ++ userPagePath
        in
          H.span []
            [ H.text <|
                "The market creator doesn't trust you!"
                ++ " If you think that they *do* trust you in real life, then send them this link to your user page,"
                ++ " and ask them to mark you as trusted: "
            , H.a [HA.href userPageUrl] [H.text userPageUrl]
            ]
      else if not creator.isTrusted then
        H.text <|
          "You don't trust the market creator!"
          ++ " If you think that you *do* trust them in real life, ask them for a link to their user page,"
          ++ " and mark them as trusted."
      else
        StakeForm.view (stakeFormConfig model) model.stakeForm

creatorWinningsByBettor : Bool -> List Pb.Trade -> Dict String Int -- TODO: avoid key serialization collisions
creatorWinningsByBettor resolvedYes trades =
  trades
  |> List.foldl (\t d -> D.update (Utils.renderUser <| Utils.mustTradeBettor t) (Maybe.withDefault 0 >> ((+) (if xor resolvedYes t.bettorIsASkeptic then -t.creatorStakeCents else t.bettorStakeCents)) >> Just) d) D.empty

stateWinnings : Int -> String -> String
stateWinnings win counterparty =
  (if win > 0 then counterparty ++ " owes you" else "You owe " ++ counterparty) ++ " " ++ Utils.formatCents (abs win) ++ "."

enumerateWinnings : Dict String Int -> Html Msg
enumerateWinnings winningsByUser =
  H.ul [] <| (
    winningsByUser
    |> D.toList
    |> List.sortBy (\(b, win) -> b)
    |> List.map (\(b, win) -> H.li [] [H.text <| stateWinnings win b])
    )

viewDefiniteResolution : Pb.UserMarketView -> Bool -> Html Msg
viewDefiniteResolution market resolvedYes =
  let
    creator = Utils.mustMarketCreator market
  in
    H.div []
      [ H.text <| "This market has resolved " ++ (if resolvedYes then "YES" else "NO") ++ ". "
      , if creator.isSelf then
          enumerateWinnings (creatorWinningsByBettor resolvedYes market.yourTrades)
        else if List.length market.yourTrades > 0 then
          let bettorWinnings = -(List.sum <| D.values <| creatorWinningsByBettor resolvedYes market.yourTrades) in
          H.text <| stateWinnings bettorWinnings creator.displayName
        else
          H.text ""
      ]

view : Model -> Html Msg
view model =
  let
    creator = Utils.mustMarketCreator model.market
    certainty = Utils.mustMarketCertainty model.market
    secondsToClose = model.market.closesUnixtime - Time.posixToMillis model.now // 1000
    openTime = model.market.createdUnixtime |> (*) 1000 |> Time.millisToPosix
    closeTime = model.market.closesUnixtime |> (*) 1000 |> Time.millisToPosix
  in
  H.div []
    [ H.h2 [] [H.text model.market.question]
    , case Utils.currentResolution model.market of
        Pb.ResolutionYes ->
          viewDefiniteResolution model.market True
        Pb.ResolutionNo ->
          viewDefiniteResolution model.market False
        Pb.ResolutionNoneYet ->
          H.div []
            [ if secondsToClose <= 0 then
                H.text <| "This market closed on " ++ Utils.dateStr Time.utc closeTime ++ ", but hasn't yet resolved."
              else
                H.text <| "This market will close on "
                  ++ Utils.dateStr Time.utc closeTime ++ " UTC, in "
                  ++ Utils.renderIntervalSeconds secondsToClose
                  ++ ". "
            , H.br [] []
            , if creator.isSelf then
                H.div []
                  [ H.button [HE.onClick (Resolve Pb.ResolutionYes)] [H.text "Resolve YES"]
                  , H.button [HE.onClick (Resolve Pb.ResolutionNo)] [H.text "Resolve NO"]
                  -- , H.button [HE.onClick (Resolve Pb.ResolutionInvalid)] [H.text "Resolve INVALID"]
                  , if List.length model.market.yourTrades /= 0 then
                      H.div []
                        [ H.text "If this market resolves Yes, "
                        , enumerateWinnings (creatorWinningsByBettor True model.market.yourTrades)
                        , H.text "If this market resolves No, "
                        , enumerateWinnings (creatorWinningsByBettor False model.market.yourTrades)
                        ]
                    else
                      H.text ""
                  ]
              else if List.length model.market.yourTrades /= 0 then
                H.span []
                  [ H.text <| "If it resolves Yes: " ++ stateWinnings (List.sum <| List.map (\t -> if t.bettorIsASkeptic then -t.bettorStakeCents else t.creatorStakeCents) model.market.yourTrades) creator.displayName
                  , H.br [] []
                  , H.text <| "If it resolves No: "  ++ stateWinnings (List.sum <| List.map (\t -> if t.bettorIsASkeptic then t.creatorStakeCents else -t.bettorStakeCents) model.market.yourTrades) creator.displayName
                  ]
              else
                H.text ""
            ]
        Pb.ResolutionUnrecognized_ _ ->
          H.span [HA.style "color" "red"]
            [H.text "Oh dear, something has gone very strange with this market. Please email TODO with this URL to report it!"]
    , H.hr [] []
    , H.p []
        [ H.text <| "On " ++ Utils.dateStr Time.utc openTime ++ " UTC, "
        , H.strong [] [H.text creator.displayName]
        , H.text " assigned this a "
        , certainty.low |> (*) 100 |> round |> String.fromInt |> H.text
        , H.text "-"
        , certainty.high |> (*) 100 |> round |> String.fromInt |> H.text
        , H.text "% chance, and staked "
        , model.market.maximumStakeCents |> Utils.formatCents |> H.text
        , H.text "."
        ]
    , viewStakeFormOrExcuse model
    , case model.stakeError of
        Just e -> H.div [HA.style "color" "red"] [H.text e]
        Nothing -> H.text ""
    , if creator.isSelf then
        H.div []
          [ H.hr [] []
          , H.text "As the creator of this market, you might want to link to it in your writing! Here are some snippets of HTML you could copy-paste."
          , viewEmbedInfo model
          ]
      else
        H.text ""
    ]

viewEmbedInfo : Model -> Html Msg
viewEmbedInfo model =
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
      ++ String.fromInt (round <| (Utils.mustMarketCertainty model.market).low * 100)
      ++ "-"
      ++ String.fromInt (round <| (Utils.mustMarketCertainty model.market).high * 100)
      ++ "%]"
    linkCode =
      "<a style=\"" ++ (linkStyles |> List.map (\(k,v) -> k++":"++v) |> String.join ";") ++ "\" href=\"" ++ linkUrl ++ "\">" ++ linkText ++ "</a>"
  in
    H.ul []
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

stakeFormConfig : Model -> StakeForm.Config Msg
stakeFormConfig model =
  { setState = SetStakeFormState
  , onStake = Stake
  , nevermind = Ignore
  , disableCommit = (model.auth == Nothing || (Utils.mustMarketCreator model.market).isSelf)
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
