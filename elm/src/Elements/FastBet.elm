module Elements.FastBet exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode exposing (field)

type alias Name = String
type alias Model =
  { aliceNameField : String
  , alicePField : String
  , bobNameField : String
  , bobPField : String
  , exposureField : String
  }

type Msg
  = SetAliceNameField String
  | SetAlicePField String
  | SetBobNameField String
  | SetBobPField String
  | SetExposureField String

init : () -> ( Model , Cmd never )
init () =
  ( { aliceNameField = ""
    , alicePField = "0"
    , bobNameField = ""
    , bobPField = "100"
    , exposureField = "10"
    }
  , Cmd.none
  )

parseName : Name -> String -> Name
parseName default field =
  if field == "" then default else field

parsePctProb : String -> Result String Float
parsePctProb s =
  case String.toFloat s of
    Nothing -> Err "must be a number 0-100"
    Just pct ->
      if pct < 0 || pct > 100 then
        Err "must be a number 0-100"
      else
        Ok (pct/100)

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
  if dollars < 0 then "-" ++ formatDollars (-dollars) else
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
    alice = { name = parseName "Alice" model.aliceNameField , p = parsePctProb model.alicePField }
    bob = { name = parseName "Bob" model.bobNameField , p = parsePctProb model.bobPField }
    bet = case (alice.p, bob.p, parseExposure model) of
      (Ok pA, Ok pB, Ok exposure) ->
        let
          impliedProbability = (pA + pB) / 2
          payoutRatioYesOverNo = (1 - impliedProbability) / impliedProbability
          highPaysLowIfNo = exposure / (max 1 payoutRatioYesOverNo)
          lowPaysHighIfYes = highPaysLowIfNo * payoutRatioYesOverNo
          (aliceWinningsIfYes, aliceWinningsIfNo) =
            if pA > pB then
              (lowPaysHighIfYes, -highPaysLowIfNo)
            else
              (-lowPaysHighIfYes, highPaysLowIfNo)
        in
          Just {impliedProbability=impliedProbability, aliceWinningsIfYes=aliceWinningsIfYes, aliceWinningsIfNo=aliceWinningsIfNo}
      _ -> Nothing
  in
  { title = "Fast Bet"
  , body =
    [ H.main_ [HA.class "container"]
      [ H.h2 [HA.class "my-4 text-center"] [H.text "Make a fast bet"]
      , H.div [HA.class "row mb-3"]
        [ H.text <|
            "This page helps you craft a quick bet on a yes/no proposition!"
            ++ " If you and a friend disagree on how likely something is, just enter the probabilities you assign to it below."
        ]
      , H.div [HA.class "row"]
        [ H.div [HA.class "align-text-top mb-3"]
          [ H.input
              [ HA.class "form-control form-control-sm py-0 d-inline-block"
              , HA.style "max-width" "13em"
              , HA.value model.aliceNameField
              , HA.placeholder "Alice"
              , HE.onInput SetAliceNameField
              ] []
          , H.text " assigns this probability "
          , H.div [HA.class "d-inline-block align-text-top", HA.style "margin-top" "-0.3em"]
            [ H.input
              [ HA.class "form-control form-control-sm py-0 d-inline-block"
              , HA.class (if model.alicePField == "" || isOk alice.p then "" else "is-invalid")
              , HA.type_ "number", HA.min "0", HA.max "100"
              , HA.style "max-width" "7em"
              , HA.value model.alicePField
              , HE.onInput SetAlicePField
              ] []
            , H.text "%"
            , H.div [HA.style "height" "1.5em"]
              [ if model.alicePField == "" then H.text "" else
                case alice.p of
                  Err e -> H.span [HA.style "color" "red"] [H.text e]
                  Ok p -> case rationalApprox {x=p, tolerance=0.13 * min p (1-p)} of
                    Nothing -> H.text ""
                    Just (n,d) -> if n==0 || n==d then H.text "" else H.div [HA.class "text-secondary"] [H.text <| "i.e. about " ++ String.fromInt n ++ " out of " ++ String.fromInt d]
              ]
            ]
          ]
        , H.div [HA.class "mb-3"]
          [ H.input
              [ HA.class "form-control form-control-sm py-0 d-inline-block"
              , HA.style "max-width" "13em"
              , HA.value model.bobNameField
              , HA.placeholder "Bob"
              , HE.onInput SetBobNameField
              ] []
          , H.text " assigns it probability "
          , H.div [HA.class "d-inline-block align-text-top", HA.style "margin-top" "-0.3em"]
            [ H.input
                [ HA.class "form-control form-control-sm py-0 d-inline-block"
                , HA.class (if model.bobPField == "" || isOk bob.p then "" else "is-invalid")
                , HA.type_ "number", HA.min "0", HA.max "100"
                , HA.style "max-width" "7em"
                , HA.value model.bobPField
                , HE.onInput SetBobPField
                ] []
            , H.text "%"
            , H.div [HA.style "height" "1.5em"]
              [ if model.bobPField == "" then H.text "" else
                case bob.p of
                  Err e -> H.span [HA.style "color" "red"] [H.text e]
                  Ok p -> case rationalApprox {x=p, tolerance=0.13 * min p (1-p)} of
                    Nothing -> H.text ""
                    Just (n,d) -> if n==0 || n==d then H.text "" else H.div [HA.class "text-secondary"] [H.text <| "i.e. about " ++ String.fromInt n ++ " out of " ++ String.fromInt d]
              ]
            ]
          ]
        , let exposure = parseExposure model in
          H.div [HA.class "mb-3"]
          [ H.text "How much money are you two willing to stake on this? $"
          , H.div [HA.class "d-inline-block align-text-top", HA.style "margin-top" "-0.3em"]
          [ H.input
              [ HA.class "form-control form-control-sm py-0 d-inline-block"
              , HA.class (if isOk exposure then "" else "is-invalid")
              , HA.type_ "number", HA.min "0"
              , HA.style "max-width" "7em"
              , HA.value model.exposureField
              , HE.onInput SetExposureField
              ] []
            , H.div [HA.class "invalid-feedback"] [viewError exposure]
            ]
          ]
        , H.hr [HA.class "my-2"] []
        , H.h3 [HA.class "text-center mb-2"] [H.text "The bet you should make:"]
        , H.div []
          [ H.text "If the thing ", b "happens:", H.text " "
          , case bet of
              Nothing -> b "???"
              Just details ->
                if details.aliceWinningsIfYes < 0 then
                  H.span [] [ H.text <| alice.name ++ " pays " ++ bob.name ++ " ", b <| formatDollars (-details.aliceWinningsIfYes) ]
                else
                  H.span [] [ H.text <| bob.name ++ " pays " ++ alice.name ++ " ", b <| formatDollars details.aliceWinningsIfYes ]
          ]
        , H.div []
          [ H.text "If it ", b "doesn't happen:", H.text " "
          , case bet of
              Nothing -> b "???"
              Just details ->
                if details.aliceWinningsIfNo < 0 then
                  H.span [] [ H.text <| alice.name ++ " pays " ++ bob.name ++ " ", b <| formatDollars (-details.aliceWinningsIfNo) ]
                else
                  H.span [] [ H.text <| bob.name ++ " pays " ++ alice.name ++ " ", b <| formatDollars details.aliceWinningsIfNo ]
          ]
        , H.details [HA.class "m-3 text-secondary"]
          [ H.text <| "You're effectively betting at " ++ (bet |> Maybe.map (.impliedProbability >> (*) 100 >> round >> String.fromInt) |> Maybe.withDefault "???") ++ "% odds. Your expected winnings are:"
          , H.p []
            [ H.ul []
              [ H.li []
                [ H.strong [] [H.text <| alice.name ++ ": "]
                , case (alice.p, bet) of
                    (Ok p, Just payouts) ->
                      H.text <|
                        (formatDollars <| p * payouts.aliceWinningsIfYes + (1-p)*payouts.aliceWinningsIfNo) ++ " = "
                        ++ formatProbabilityAsPct p ++ " * " ++ formatDollars payouts.aliceWinningsIfYes ++ " + " ++ formatProbabilityAsPct (1-p) ++ " * " ++ formatDollars payouts.aliceWinningsIfNo
                    _ -> H.text "???"
                ]
              , H.li []
                [ H.strong [] [H.text <| bob.name ++ ": "]
                , case (bob.p, bet) of
                    (Ok p, Just payouts) ->
                      H.text <|
                        (formatDollars <| p * (-payouts.aliceWinningsIfYes) + (1-p)*(-payouts.aliceWinningsIfNo)) ++ " = "
                        ++ formatProbabilityAsPct p ++ " * " ++ formatDollars (-payouts.aliceWinningsIfYes) ++ " + " ++ formatProbabilityAsPct (1-p) ++ " * " ++ formatDollars (-payouts.aliceWinningsIfNo)
                    _ -> H.text "???"
                ]
              ]
            ]
          ]
        ]
      ]
    ]
  }

rationalApprox : {x: Float, tolerance: Float} -> Maybe (Int, Int)
rationalApprox {x, tolerance} =
  let
    denominators = [2, 3, 4, 5, 6, 10, 15, 20]

    bestNumerator : Int -> Int
    bestNumerator denominator = round (x * toFloat denominator)

    error : Int -> Float
    error denominator =
      abs <| x - toFloat (bestNumerator denominator) / toFloat denominator

  in
    denominators
    |> List.map (\d -> (error d, bestNumerator d, d))
    |> List.filter (\(err, _, _) -> err <= tolerance)
    |> List.minimum
    |> Maybe.map (\(_, n, d) -> (n, d))

update : Msg -> Model -> ( Model , Cmd never )
update msg model =
  ( case msg of
      SetAliceNameField value -> { model | aliceNameField = value }
      SetAlicePField value -> { model | alicePField = value }
      SetBobNameField value -> { model | bobNameField = value }
      SetBobPField value -> { model | bobPField = value }
      SetExposureField value -> { model | exposureField = value }
  , Cmd.none
  )

main = Browser.document { init=init, update=update, view=view, subscriptions=\_ -> Sub.none }
