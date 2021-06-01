module Utils exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as JD
import Set
import Time

import Base64
import Protobuf.Decode as PD
import Dict exposing (Dict)

import Biatob.Proto.Mvp as Pb

type alias Username = String
type alias Password = String
type alias EmailAddress = String
type alias Cents = Int
type alias PredictionId = String
type alias InvitationNonce = String

illegalUsernameCharacters : String -> Set.Set Char
illegalUsernameCharacters s =
  let
    okayChars = ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" |> String.toList |> Set.fromList)
    presentChars = s |> String.toList |> Set.fromList
  in
    Set.diff presentChars okayChars

parseUsername : String -> Result String Username
parseUsername s =
  if s=="" then
    Err ""
  else let badChars = illegalUsernameCharacters s in
  if not (Set.isEmpty badChars) then
    Err ("bad characters: " ++ Debug.toString (Set.toList badChars))
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
appendValidationError : Maybe String -> Html msg -> Html msg
appendValidationError err elem =
  case err of
    Just e ->
      H.span [HA.style "outline" "1px solid red"]
        [ elem
        , H.span [HA.style "color" "red"] [H.text e]
        ]
    Nothing -> H.span [] [elem] -- the extra span is necessary for Elm to realize the input is the same, to keep focus on it

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
  H.a [HA.href <| pathToUserPage user] [H.text user]

outlineIfInvalid : Bool -> H.Attribute msg
outlineIfInvalid isInvalid =
  HA.style "outline" (if isInvalid then "2px solid red" else "none")

pbB64Decoder : PD.Decoder a -> JD.Decoder a
pbB64Decoder dec =
  JD.string
  |> JD.andThen (\s ->
      case s |> Base64.toBytes |> Maybe.andThen (PD.decode dec) of
        Just a -> JD.succeed a
        Nothing -> JD.fail "invalid b64 protobuf"
      )

mustResult : String -> Result e x -> x
mustResult reason res =
  case res of
    Ok x -> x
    Err e -> Debug.todo (reason ++ " -- " ++ Debug.toString e)
decodePbFromFlags : PD.Decoder a -> String -> JD.Value -> Maybe a
decodePbFromFlags dec field val =
  JD.decodeValue (JD.field field (pbB64Decoder dec)) val
  |> Debug.log ("init " ++ field)
  |> Result.toMaybe

mustDecodePbFromFlags : PD.Decoder a -> String -> JD.Value -> a
mustDecodePbFromFlags dec field val =
  decodePbFromFlags dec field val
  |> must field

mustDecodeFromFlags : JD.Decoder a -> String -> JD.Value -> a
mustDecodeFromFlags dec field val =
  JD.decodeValue (JD.field field dec) val
  |> mustResult field

mustPredictionCertainty : Pb.UserPredictionView -> Pb.CertaintyRange
mustPredictionCertainty {certainty} = must "all predictions must have certainties" certainty

mustUsernameGenericInfo : Pb.UsernameInfo -> Pb.GenericUserInfo
mustUsernameGenericInfo {info} = must "all UserInfos must have GenericUserInfos" info

mustUserInfoEmail : Pb.GenericUserInfo -> Pb.EmailFlowState
mustUserInfoEmail {email} = email |> Maybe.withDefault {emailFlowStateKind=Just (Pb.EmailFlowStateKindUnstarted Pb.Void)}

mustEmailFlowStateKind : Pb.EmailFlowState -> Pb.EmailFlowStateKind
mustEmailFlowStateKind {emailFlowStateKind} = must "all EmailFlowStates must have kinds" emailFlowStateKind

mustGetSettingsResult : Pb.GetSettingsResponse -> Pb.GetSettingsResult
mustGetSettingsResult {getSettingsResult} = must "all GetSettingsResponses must have results" getSettingsResult

mustPredictionsById : Pb.PredictionsById -> Dict PredictionId Pb.UserPredictionView
mustPredictionsById {predictions} = predictions |> Dict.map (\_ v -> must "no null values are allowed in a PredictionsById" v)

mustMapValues : Dict comparable (Maybe v) -> Dict comparable v
mustMapValues d = d |> Dict.map (\_ v -> must "no null values are allowed in a map" v)

mustAuthSuccessToken : Pb.AuthSuccess -> Pb.AuthToken
mustAuthSuccessToken {token} = must "all AuthSuccesses must have tokens" token

mustAuthSuccessUserInfo : Pb.AuthSuccess -> Pb.GenericUserInfo
mustAuthSuccessUserInfo {userInfo} = must "all AuthSuccesses must have user_infos" userInfo

currentResolution : Pb.UserPredictionView -> Pb.Resolution
currentResolution prediction =
  List.head (List.reverse prediction.resolutions)
  |> Maybe.map .resolution
  |> Maybe.withDefault Pb.ResolutionNoneYet

resolutionIsTerminal : Pb.Resolution -> Bool
resolutionIsTerminal res =
  case res of
    Pb.ResolutionYes -> True
    Pb.ResolutionNo -> True
    Pb.ResolutionNoneYet -> False
    Pb.ResolutionInvalid -> True
    Pb.ResolutionUnrecognized_ _ -> Debug.todo "unrecognized resolution"

invitationPath : InvitationNonce -> String
invitationPath nonce =
  "/invitation/" ++ nonce

unixtimeToTime : Float -> Time.Posix
unixtimeToTime n = Time.millisToPosix <| round <| n*1000
timeToUnixtime : Time.Posix -> Float
timeToUnixtime t = toFloat (Time.posixToMillis t) / 1000

monthNum_ : Time.Month -> Int
monthNum_ month =
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

isoStr : Time.Zone -> Time.Posix -> String
isoStr zone t =
  String.fromInt (Time.toYear zone t)
  ++ "-"
  ++ String.padLeft 2 '0' (String.fromInt (monthNum_ <| Time.toMonth zone t))
  ++ "-"
  ++ String.padLeft 2 '0' (String.fromInt (Time.toDay zone t))
  ++ "T"
  ++ String.padLeft 2 '0' (String.fromInt (Time.toHour zone t))
  ++ ":"
  ++ String.padLeft 2 '0' (String.fromInt (Time.toMinute zone t))
  ++ ":"
  ++ String.padLeft 2 '0' (String.fromInt (Time.toSecond zone t))

dateStr : Time.Zone -> Time.Posix -> String
dateStr zone t =
  isoStr zone t |> String.left (4+1+2+1+2)

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
  "/username/" ++ user

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
