module Elements.FastBet exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE

type alias Model =
  { lowField : String
  , highField : String
  , exposureField : String
  }

type Msg
  = SetLowField String
  | SetHighField String
  | SetExposureField String

init : () -> ( Model , Cmd never )
init () =
  ( { lowField = "0"
    , highField = "100"
    , exposureField = "10"
    }
  , Cmd.none
  )

parsePLow : Model -> Result String Float
parsePLow model =
  case String.toFloat model.lowField of
    Nothing -> Err "must be a number 0-100"
    Just pct ->
      if pct < 0 || pct > 100 then
        Err "must be a number 0-100"
      else
        Ok (pct/100)

parsePHigh : Model -> Result String Float
parsePHigh model =
  case String.toFloat model.highField of
    Nothing -> Err "must be a number 0-100"
    Just pct ->
      if pct < 0 || pct > 100 then
        Err "must be a number 0-100"
      else let pHigh = pct/100 in
        case parsePLow model of
          Err _ -> Ok pHigh
          Ok pLow ->
            if pHigh < pLow then
              Err "can't be less than the skeptic's probability"
            else
              Ok pHigh

parseExposure : Model -> Result String Float
parseExposure model =
  case String.toFloat model.exposureField of
    Nothing -> Err "must be a positive number"
    Just stake ->
      if stake <= 0 then
        Err "must be a positive number"
      else
        Ok stake

formatDollars : Float -> String
formatDollars dollars =
  let
    cents = round (100 * dollars)
    wholeDollars = cents // 100
    remainingCents = cents - 100*wholeDollars
  in
    "$" ++ String.fromInt wholeDollars ++ "." ++ String.pad 2 '0' (String.fromInt remainingCents)

formatProbabilityAsPct : Float -> String
formatProbabilityAsPct p =
  String.fromInt (round (p*100)) ++ "%"

b : String -> Html a
b text = H.strong  [] [H.text text]

isOk : Result e x -> Bool
isOk res = case res of
  Ok _ -> True
  Err _ -> False
viewError : Result String x -> Html a
viewError res = case res of
  Err s -> H.text s
  Ok _ -> H.text ""

view : Model -> Browser.Document Msg
view model =
  let
    bet = case (parsePLow model, parsePHigh model, parseExposure model) of
      (Ok pLow, Ok pHigh, Ok exposure) ->
        let
          impliedProbability = (pLow + pHigh) / 2
          payoutRatioYesOverNo = (1 - impliedProbability) / impliedProbability
          highPaysLowIfNo = exposure / (max 1 payoutRatioYesOverNo)
          lowPaysHighIfYes = highPaysLowIfNo * payoutRatioYesOverNo
        in
          Just {impliedProbability=impliedProbability, lowPaysHighIfYes=lowPaysHighIfYes, highPaysLowIfNo=highPaysLowIfNo}
      _ -> Nothing
  in
  { title = "Fast Bet"
  , body =
    [ H.main_ [HA.class "container"]
      [ H.h2 [HA.class "my-4 text-center"] [H.text "Make a fast bet"]
      , H.div [HA.class "row mb-3"]
        [ H.text "This page helps you craft a quick bet on a yes/no proposition! If you and a friend disagree on how likely something is, just enter the probabilities you assign to it below."
        ]
      , H.div [HA.class "row"]
        [ let pLow = parsePLow model in
          H.div [HA.class "mb-3"]
          [ H.text "What probability does the ", b "skeptic", H.text " assign to the thing in question? "
          , H.div [HA.class "input-group"]
            [ H.input
              [ HA.class "form-control form-control-sm py-0 w-auto"
              , HA.class (if isOk pLow then "" else "is-invalid")
              , HA.style "max-width" "20em"
              , HA.value model.lowField
              , HE.onInput SetLowField
              ] []
            , H.div [HA.class "input-group-append"] [H.div [HA.class "input-group-text"] [H.text "%"]]
            , H.div [HA.class "invalid-feedback"] [viewError pLow]
            ]
          ]
        , let pHigh = parsePHigh model in
          H.div [HA.class "mb-3"]
          [ H.text "What probability does the ", H.strong [] [H.text "believer"], H.text " assign to the thing in question? "
          , H.div [HA.class "input-group"]
            [ H.input
              [ HA.class "form-control form-control-sm py-0 w-auto"
              , HA.class (if isOk pHigh then "" else "is-invalid")
              , HA.style "max-width" "20em"
              , HA.value model.highField
              , HE.onInput SetHighField
              ] []
            , H.div [HA.class "input-group-append"] [H.div [HA.class "input-group-text"] [H.text "%"]]
            , H.div [HA.class "invalid-feedback"] [viewError pHigh]
            ]
          ]
        , let exposure = parseExposure model in
          H.div [HA.class "mb-3"]
          [ H.text "How much money are you two willing to stake on this?"
          , H.div [HA.class "input-group"]
            [ H.div [HA.class "input-group-prepend"] [H.div [HA.class "input-group-text"] [H.text "$"]]
            , H.input
              [ HA.class "form-control form-control-sm py-0 w-auto"
              , HA.class (if isOk exposure then "" else "is-invalid")
              , HA.style "max-width" "20em"
              , HA.value model.exposureField
              , HE.onInput SetExposureField
              ] []
            , H.div [HA.class "invalid-feedback"] [viewError exposure]
            ]
          ]
        , H.hr [HA.class "my-2"] []
        , H.h3 [HA.class "text-center mb-2"] [H.text "The bet you should make:"]
        , H.table []
          [ H.tr []
            [ H.th [HA.class "pe-3", HA.scope "row"] [H.text "If the thing happens,"]
            , H.td [HA.class "pe-3" ] [ H.text " the ", b "skeptic", H.text " should pay the ", b "believer" ]
            , H.td [HA.class "pe-3" ] [ H.text (bet |> Maybe.map (.lowPaysHighIfYes >> formatDollars) |> Maybe.withDefault "???") ]
            ]
          , H.tr []
            [ H.th [HA.scope "row"] [H.text "Otherwise,"]
            , H.td [] [ H.text " the ", b "believer", H.text " should pay the ", b "skeptic", H.text " " ]
            , H.td [] [ H.text (bet |> Maybe.map (.highPaysLowIfNo >> formatDollars) |> Maybe.withDefault "???") ]
            ]
          ]
        , H.details [HA.class "m-3 text-secondary"]
          [ H.text <| "You're effectively betting at " ++ (bet |> Maybe.map (.impliedProbability >> (*) 100 >> round >> String.fromInt) |> Maybe.withDefault "???") ++ "% odds. Your expected winnings are:"
          , H.p []
            [ H.ul []
              [ H.li []
                [ H.strong [] [H.text "Doubter: "]
                , case (parsePLow model, bet) of
                    (Ok pLow, Just payouts) ->
                      H.text <|
                        (formatDollars <| pLow * (-payouts.lowPaysHighIfYes) + (1-pLow)*payouts.highPaysLowIfNo) ++ " = "
                        ++ formatProbabilityAsPct pLow ++ " * -" ++ formatDollars payouts.lowPaysHighIfYes ++ " + " ++ formatProbabilityAsPct (1-pLow) ++ " * " ++ formatDollars payouts.highPaysLowIfNo
                    _ -> H.text "???"
                ]
              , H.li []
                [ H.strong [] [H.text "Believer: "]
                , case (parsePHigh model, bet) of
                    (Ok pHigh, Just payouts) ->
                      H.text <|
                        (formatDollars <| pHigh * payouts.lowPaysHighIfYes + (1-pHigh)*(-payouts.highPaysLowIfNo)) ++ " = "
                        ++ formatProbabilityAsPct pHigh ++ " * " ++ formatDollars payouts.lowPaysHighIfYes ++ " + " ++ formatProbabilityAsPct (1-pHigh) ++ " * -" ++ formatDollars payouts.highPaysLowIfNo
                    _ -> H.text "???"
                ]
              ]
            ]
          ]
        ]
      ]
    ]
  }

update : Msg -> Model -> ( Model , Cmd never )
update msg model =
  ( case msg of
      SetLowField value -> { model | lowField = value }
      SetHighField value -> { model | highField = value }
      SetExposureField value -> { model | exposureField = value }
  , Cmd.none
  )

main = Browser.document { init=init, update=update, view=view, subscriptions=\_ -> Sub.none }
