module Utils exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as JD
import Json.Encode as JE
import OpenApi.Common
import Set
import Time

import Iso8601
import Dict exposing (Dict)

import Api.Types as Pb
import Api.Json
import Parser exposing ((|.), (|=))

type alias Username = String
type alias Password = String
type alias EmailAddress = String
type alias Cents = Int
type alias PredictionId = String
type alias InvitationNonce = String

type BetSide = Skeptic | Believer
betSideToIsSkeptical : BetSide -> Bool
betSideToIsSkeptical side = case side of
  Skeptic -> True
  Believer -> False
betSideFromIsSkeptical : Bool -> BetSide
betSideFromIsSkeptical isSkeptical =
  if isSkeptical then Skeptic else Believer

maxLegalStakeCents = 500000

illegalUsernameCharacters : String -> Set.Set Char
illegalUsernameCharacters s =
  let
    okayChars = ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" |> String.toList |> Set.fromList)
    presentChars = s |> String.toList |> Set.fromList
  in
    Set.diff presentChars okayChars

type UsernameProblem
  = TooShort
  | IllegalCharacters (Set.Set Char)
minUsernameLength = 3
usernameProblemToString : UsernameProblem -> String
usernameProblemToString problem =
  case problem of
    TooShort -> "must be at least " ++ String.fromInt minUsernameLength ++ "characters"
    IllegalCharacters chars -> "illegal characters: " ++ Debug.toString chars
parseUsername : String -> Result (List UsernameProblem) Username
parseUsername s =
  if String.length s < 3 then
    Err [TooShort]
  else let badChars = illegalUsernameCharacters s in
  if not (Set.isEmpty badChars) then
    Err [IllegalCharacters badChars]
  else
    Ok s

parsePassword : String -> Result String Password
parsePassword s =
  if s=="" then
    Err ""
  else if String.length s > 256 then
    Err "must not be over 256 characters, good grief"
  else
    Ok s

isOk : Result e x -> Bool
isOk res =
  case res of
    Ok _ -> True
    Err _ -> False
isErr : Result e x -> Bool
isErr res = not (isOk res)

resultToErr : Result e x -> Maybe e
resultToErr res =
  case res of
    Err e -> Just e
    Ok _ -> Nothing

formatCents : Cents -> String
formatCents n =
  if n < 0 then "-" ++ formatCents (-n) else
  let
    fullDollars = n // 100
    centsOnly = n |> modBy 100
  in
    "$"
    ++ (String.fromInt fullDollars)
    ++ if centsOnly == 0 then "" else ("." ++ (centsOnly |> String.fromInt |> String.padLeft 2 '0'))

must : String -> Maybe a -> a
must errmsg mx =
  case mx of
    Just x -> x
    Nothing -> Debug.todo errmsg

renderUser : Username -> H.Html msg
renderUser user =
  H.a [HA.class "p-0", HA.href <| pathToUserPage user] [H.text user]

outlineIfInvalid : Bool -> H.Attribute msg
outlineIfInvalid isInvalid =
  HA.style "outline" (if isInvalid then "2px solid red" else "none")

encodeToString : JE.Value -> String
encodeToString v = JE.encode 0 v

mustResult : String -> Result e x -> x
mustResult reason res =
  case res of
    Ok x -> x
    Err e -> Debug.todo (reason ++ " -- " ++ Debug.toString e)
decodeFromFlags : JD.Decoder a -> String -> JD.Value -> Maybe a
decodeFromFlags dec field val =
  JD.decodeValue (JD.field field dec) val
  |> Result.toMaybe

mustDecodeFromFlags : JD.Decoder a -> String -> JD.Value -> a
mustDecodeFromFlags dec field val =
  JD.decodeValue (JD.field field dec) val
  |> mustResult field

mustPredictionCertainty : Pb.UserPredictionView -> Pb.CertaintyRange
mustPredictionCertainty {certainty} = certainty



mustPredictionsById : Pb.PredictionsById -> Dict PredictionId Pb.UserPredictionView
mustPredictionsById {predictions} = predictions

mustMapValues : Dict comparable (Maybe v) -> Dict comparable v
mustMapValues d = d |> Dict.map (\_ v -> must "no null values are allowed in a map" v)

mustAuthSuccessUserInfo : Pb.AuthSuccess -> Pb.GenericUserInfo
mustAuthSuccessUserInfo {userInfo} = userInfo

nullableToMaybe : OpenApi.Common.Nullable a -> Maybe a
nullableToMaybe n =
  case n of
    OpenApi.Common.Null -> Nothing
    OpenApi.Common.Present a -> Just a

{-| The prediction's resolution event, or Nothing if unresolved. Collapses the
generated `Maybe (Nullable ResolutionEvent)` to a plain `Maybe`. -}
resolutionEventOf : Pb.UserPredictionView -> Maybe Pb.ResolutionEvent
resolutionEventOf prediction = prediction.resolution |> Maybe.andThen nullableToMaybe

resolutionEventFields (Pb.ResolutionEvent r) = r

priorRevisionOf : Pb.ResolutionEvent -> Maybe Pb.ResolutionEvent
priorRevisionOf event = (resolutionEventFields event).priorRevision |> Maybe.andThen nullableToMaybe

currentResolution : Pb.UserPredictionView -> Pb.Resolution
currentResolution prediction =
  case resolutionEventOf prediction of
    Nothing -> Pb.Resolution__RESOLUTIONNONEYET
    Just event -> (resolutionEventFields event).resolution

resolutionIsTerminal : Pb.Resolution -> Bool
resolutionIsTerminal res =
  case res of
    Pb.Resolution__RESOLUTIONYES -> True
    Pb.Resolution__RESOLUTIONNO -> True
    Pb.Resolution__RESOLUTIONNONEYET -> False
    Pb.Resolution__RESOLUTIONINVALID -> True

invitationPath : InvitationNonce -> String
invitationPath nonce =
  "/invitation/" ++ nonce

unixtimeToTime : Float -> Time.Posix
unixtimeToTime n = Time.millisToPosix <| round <| n*1000
timeToUnixtime : Time.Posix -> Float
timeToUnixtime t = toFloat (Time.posixToMillis t) / 1000

monthNum : Time.Month -> Int
monthNum month =
  case month of
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

monthName : Time.Month -> String
monthName m = case m of
  Time.Jan -> "Jan"
  Time.Feb -> "Feb"
  Time.Mar -> "Mar"
  Time.Apr -> "Apr"
  Time.May -> "May"
  Time.Jun -> "Jun"
  Time.Jul -> "Jul"
  Time.Aug -> "Aug"
  Time.Sep -> "Sep"
  Time.Oct -> "Oct"
  Time.Nov -> "Nov"
  Time.Dec -> "Dec"
yearMonthDayHourMinuteStr : Time.Zone -> Time.Posix -> String
yearMonthDayHourMinuteStr zone t =
  String.fromInt (Time.toYear zone t)
  ++ " "
  ++ monthName (Time.toMonth zone t)
  ++ " "
  ++ String.padLeft 2 '0' (String.fromInt (Time.toDay zone t))
  ++ " "
  ++ String.padLeft 2 '0' (String.fromInt (Time.toHour zone t))
  ++ ":"
  ++ String.padLeft 2 '0' (String.fromInt (Time.toMinute zone t))

yearMonthDayStr : Time.Zone -> Time.Posix -> String
yearMonthDayStr zone t =
  String.fromInt (Time.toYear zone t)
  ++ " " ++ monthName (Time.toMonth zone t)
  ++ " " ++ String.fromInt (Time.toDay zone t)

addMillis : Int -> Time.Posix -> Time.Posix
addMillis n t =
  t |> Time.posixToMillis |> (+) n |> Time.millisToPosix

renderIntervalSeconds : Float -> String
renderIntervalSeconds seconds =
  let
    divmod : Int -> Int -> (Int, Int)
    divmod n div = (n // div , n |> modBy div)
    (minutes,s) = divmod (round seconds) 60
    (hours,m) = divmod minutes 60
    (days,h) = divmod hours 24
    (years,d) = divmod days 365
    y = years
  in
    if y /= 0 then String.fromInt y ++ "y " ++ String.fromInt d ++ "d" else
    if d /= 0 then String.fromInt d ++ "d " ++ String.fromInt h ++ "h" else
    if h /= 0 then String.fromInt h ++ "h " ++ String.fromInt m ++ "m" else
    if m /= 0 then String.fromInt m ++ "m " ++ String.fromInt s ++ "s" else
    String.fromInt s ++ "s"

predictionCreatedTime : Pb.UserPredictionView -> Time.Posix
predictionCreatedTime prediction = unixtimeToTime prediction.createdUnixtime

predictionClosesTime : Pb.UserPredictionView -> Time.Posix
predictionClosesTime prediction = unixtimeToTime prediction.closesUnixtime

pathToPrediction : PredictionId -> String
pathToPrediction predictionId =
  "/p/" ++ predictionId

pathToUserPage : Username -> String
pathToUserPage user =
  "/" ++ user

greenText : String -> Html msg
greenText s = H.span [HA.style "color" "green"] [H.text s]
redText : String -> Html msg
redText s = H.span [HA.style "color" "red"] [H.text s]

i : String -> Html msg
i s = H.i [] [H.text s]

b : String -> Html msg
b s = H.strong [] [H.text s]

onEnter : msg -> msg -> H.Attribute msg
onEnter msg nevermind =
  HE.on "keydown" <|
    JD.map (\keyCode -> if keyCode == 13 then msg else nevermind) HE.keyCode

viewError : Result String x -> Html msg
viewError res =
  case res of
    Ok _ -> H.text ""
    Err e -> redText e

type RequestStatus = Unstarted | AwaitingResponse | Succeeded | Failed String

stupidIsoStrToTime : Time.Zone -> String -> Result (List Parser.DeadEnd) Time.Posix
stupidIsoStrToTime zone str =
  let
    t0 = Time.millisToPosix 0
    timeZoneMinuteOffset : Int
    timeZoneMinuteOffset =
      Time.toMinute zone t0 - Time.toMinute Time.utc t0
      + 60 * (Time.toHour zone t0 - Time.toHour Time.utc t0)
  in
  Iso8601.toTime str
  |> Result.map (addMillis (1000*60*timeZoneMinuteOffset))

invert : (a -> b) -> List a -> b -> Maybe a
invert f xs fx =
  xs
  |> List.filter (\x -> f x == fx)
  |> List.head

{-|
  "Why this funny DropdownBuilder thing?"
  Ugh. https://github.com/eeue56/elm-html-test/issues/50
  For ease of testing, we need the `onInput` handler to have _referential equality_ between the actual Html and the expected Html.
  The best way I've thought of achieving that is by currying in this funny way, and making a slight imposition on client code.
  For example, client code might look like:

      fooDropdown : DropdownBuilder Foo Msg
      fooDropdown = Utils.dropdown SetFoo Ignore [...]

      viewFoo : Model -> Html Msg
      viewFoo model =
        H.div []
        [ fooDropdown model.foo []
        ]

  If the client code does this, then `fooDropdown` is a static global singleton,
    with its `onInput` handler in that singleton's closure, rather than constructed anew for each `H.select` element it churns out.

  And the test:

      test "view contains the dropdown" <|
      \() -> view testModel |> HQ.fromHtml |> HQ.contains (viewFoo testModel)
-}
type alias DropdownBuilder a msg = a -> List (H.Attribute msg) -> Html msg
dropdown : (a -> msg) -> msg -> List (a, String) -> DropdownBuilder a msg
dropdown toMsg ignore options =
  let
    onInput : String -> msg
    onInput s =
      options
      |> List.filter (\(_, displayName) -> displayName == s)
      |> List.head
      |> Maybe.map (Tuple.first >> toMsg)
      |> Maybe.withDefault ignore
    builder : DropdownBuilder a msg
    builder selected attrs =
      options
      |> List.map (\(opt, displayName) -> H.option [HA.selected (opt == selected), HA.value displayName] [H.text displayName])
      |> H.select
          ( [ HA.class "form-select py-0 ps-0 d-inline-block w-auto"
            , HE.onInput onInput
            ]
            ++ attrs
          )
  in
  builder




emailParser : Parser.Parser EmailAddress
emailParser =
  let
    validNameChars = Set.fromList <| String.toList "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-+."
    validDomainChars = Set.fromList <| String.toList "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-+."
  in
  Parser.succeed (\s1 s2 -> s1 ++ "@" ++ s2)
    |= Parser.variable {start=\c -> Set.member c validNameChars, inner=\c -> Set.member c validNameChars, reserved=Set.empty}
    |. Parser.symbol "@"
    |= Parser.variable {start=\c -> Set.member c validDomainChars, inner=\c -> Set.member c validDomainChars, reserved=Set.empty}
    |. Parser.end

parseEmailAddress : String -> Result String EmailAddress
parseEmailAddress field =
  case Parser.run emailParser field of
    Ok s -> Ok s
    Err _ -> Err "doesn't look valid, sorry"
