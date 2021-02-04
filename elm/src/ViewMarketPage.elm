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
    , linkToAuthority = Utils.mustDecodeFromFlags JD.string "linkToAuthority" flags
    , market = Utils.mustDecodePbFromFlags Pb.userMarketViewDecoder "marketPbB64" flags
    , marketId = Utils.mustDecodeFromFlags JD.int "marketId" flags
    , auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
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

dateStr : Time.Zone -> Time.Posix -> String
dateStr zone t =
  String.fromInt (Time.toYear zone t)
  ++ "-"
  ++ String.padLeft 2 '0' (String.fromInt (case Time.toMonth zone t of
      Time.Jan -> 1
      Time.Feb -> 2
      Time.Mar -> 3
      Time.Apr -> 4
      Time.May -> 5
      Time.Jun -> 6
      Time.Jul -> 7
      Time.Aug -> 8
      Time.Sep -> 9
      Time.Oct -> 10
      Time.Nov -> 11
      Time.Dec -> 12
     ))
  ++ "-"
  ++ String.padLeft 2 '0' (String.fromInt (Time.toDay zone t))

view : Model -> Html Msg
view model =
  let
    creator_ = creator model
    secondsToClose = model.market.closesUnixtime - Time.posixToMillis model.now // 1000
    resolved = (model.market.resolution /= Pb.ResolutionNoneYet)
    expired = secondsToClose <= 0
    openTime = model.market.createdUnixtime |> (*) 1000 |> Time.millisToPosix
    closeTime = model.market.closesUnixtime |> (*) 1000 |> Time.millisToPosix
    winCentsIfYes = model.market.yourTrades |> List.map (\t -> if t.bettorIsASkeptic then -t.bettorStakeCents else t.creatorStakeCents) |> List.sum |> (*) (if creator_.isSelf then -1 else 1)
    winCentsIfNo = model.market.yourTrades |> List.map (\t -> if t.bettorIsASkeptic then t.creatorStakeCents else -t.bettorStakeCents) |> List.sum |> (*) (if creator_.isSelf then -1 else 1)
  in
  H.div []
    [ H.h2 [] [H.text model.market.question]
    , case model.market.resolution of
        Pb.ResolutionYes ->
          H.div []
            [ H.text "This market has resolved YES. "
            , if creator_.isSelf then
                H.ul [] <| (
                  model.market.yourTrades
                  |> Debug.log "trades"
                  -- TODO: avoid key collisions on Utils.renderUser
                  |> List.foldl (\t d -> D.update (Utils.renderUser <| Utils.must "trades must have bettors" t.bettor) (Maybe.withDefault 0 >> ((+) (if t.bettorIsASkeptic then t.bettorStakeCents else -t.creatorStakeCents)) >> Just) d) D.empty
                  |> D.toList
                  |> List.sortBy (\(b, win) -> b)
                  |> List.map (\(b, win) -> H.li [] [H.text <| (if win > 0 then b ++ " owes you" else "You owe " ++ b) ++ " " ++ Utils.formatCents win ++ "."])
                  )
              else if winCentsIfYes /= 0 then
                H.span []
                  [ H.text <| if winCentsIfYes > 0 then creator_.displayName ++ " owes you " else ("You owe " ++ creator_.displayName ++ " ")
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
                H.ul [] <| (
                  model.market.yourTrades
                  |> Debug.log "trades"
                  -- TODO: avoid key collisions on Utils.renderUser
                  |> List.foldl (\t d -> D.update (Utils.renderUser <| Utils.must "trades must have bettors" t.bettor) (Maybe.withDefault 0 >> ((+) (if t.bettorIsASkeptic then -t.bettorStakeCents else t.creatorStakeCents)) >> Just) d) D.empty
                  |> D.toList
                  |> List.sortBy (\(b, win) -> b)
                  |> List.map (\(b, win) -> H.li [] [H.text <| (if win > 0 then b ++ " owes you" else "You owe " ++ b) ++ " " ++ Utils.formatCents win ++ "."])
                  )
              else if winCentsIfNo /= 0 then
                H.span []
                  [ H.text <| if winCentsIfYes > 0 then creator_.displayName ++ " owes you " else ("You owe " ++ creator_.displayName ++ " ")
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
          H.text "This market has resolved YES." --  TODO: this is a duplicate
        Pb.ResolutionNo ->
          H.text "This market has resolved NO."
        Pb.ResolutionNoneYet ->
          if expired then
            H.text <| "This market closed on " ++ dateStr Time.utc closeTime ++ ", but hasn't yet resolved."
          else
            let
              divmod : Int -> Int -> (Int, Int)
              divmod n div = (n // div , n |> modBy div)
              t0 = secondsToClose
              (w,t1) = divmod t0 (60*60*24*7)
              (d,t2) = divmod t1 (60*60*24)
              (h,t3) = divmod t2 (60*60)
              (m,s) = divmod t3 (60)
            in
            H.text <| "This market will close on "
              ++ dateStr Time.utc closeTime ++ " UTC, in "
              ++ (
                if w /= 0 then String.fromInt w ++ "w " ++ String.fromInt d ++ "d" else
                if d /= 0 then String.fromInt d ++ "d " ++ String.fromInt h ++ "h" else
                if h /= 0 then String.fromInt h ++ "h " ++ String.fromInt m ++ "m" else
                if m /= 0 then String.fromInt m ++ "m " ++ String.fromInt s ++ "s" else
                String.fromInt s ++ "s"
                )
              ++ "."
        Pb.ResolutionUnrecognized_ _ ->
          H.span [HA.style "color" "red"]
            [H.text "Oh dear, something has gone very strange with this market. Please email TODO with this URL to report it!"]
    , H.hr [] []
    , H.p []
        [ H.text <| "On " ++ dateStr Time.utc openTime ++ " UTC, "
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
        H.text <| "This market closed on " ++ dateStr Time.utc closeTime ++ " UTC."
      else case model.auth of
        Nothing ->
          H.div []
            [ H.text "You must be logged in to participate in this market!"
            , StakeForm.view (stakeFormConfig model) model.stakeForm
            ]
        Just auth_ ->
          if creator_.isSelf then
            H.text ""
          else if not creator_.trustsYou then
            let
              userPagePath =
                auth_.owner
                |> Maybe.andThen .kind
                |> Maybe.map (\k -> case k of
                    Pb.KindUsername username -> "/username/" ++ username
                    )
                |> Utils.must "auths must have owners; users must have kinds"
              userPageUrl = model.linkToAuthority ++ userPagePath
            in
              H.span []
                [ H.text <|
                    "The market creator doesn't trust you!"
                    ++ " If you think that they *do* trust you in real life, then send them this link to your user page,"
                    ++ " and ask them to mark you as trusted: "
                , H.a [HA.href userPageUrl] [H.text userPageUrl]
                ]
          else if not creator_.isTrusted then
            H.text <|
              "You don't trust the market creator!"
              ++ " If you think that you *do* trust them in real life, ask them for a link to their user page,"
              ++ " and mark them as trusted."
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
