module Utils exposing (..)

import Html as H
import Html.Attributes as HA
import Json.Decode as JD
import Time

import Base64
import Protobuf.Decode as PD
import Protobuf.Encode as PE
import Dict exposing (Dict)

import Biatob.Proto.Mvp as Pb

formatCents : Int -> String
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

renderUserPlain : Pb.UserId -> String
renderUserPlain user =
  case mustUserKind user of
    Pb.KindUsername username -> username

renderUser : Pb.UserId -> H.Html msg
renderUser user =
  H.a [HA.href <| pathToUserPage user] [H.text <| renderUserPlain user]

outlineIfInvalid : Bool -> H.Attribute msg
outlineIfInvalid isInvalid =
  HA.style "outline" (if isInvalid then "2px solid red" else "none")

decodePbB64 : PD.Decoder a -> String -> Maybe a
decodePbB64 dec s =
  s |> Base64.toBytes |> Maybe.andThen (PD.decode dec)
encodePbB64 : PE.Encoder -> String
encodePbB64 enc =
  PE.encode enc |> Base64.fromBytes |> must "Base64.fromBytes docs say it will never return Nothing"

decodePbFromFlags : PD.Decoder a -> String -> JD.Value -> Maybe a
decodePbFromFlags dec field val =
  JD.decodeValue (JD.field field JD.string) val
  |> Debug.log ("init " ++ field)
  |> Result.toMaybe
  |> Maybe.andThen (decodePbB64 dec)

mustDecodePbFromFlags : PD.Decoder a -> String -> JD.Value -> a
mustDecodePbFromFlags dec field val =
  decodePbFromFlags dec field val
  |> must ("bad " ++ field)

mustDecodeFromFlags : JD.Decoder a -> String -> JD.Value -> a
mustDecodeFromFlags dec field val =
  JD.decodeValue (JD.field field dec) val
  |> Result.toMaybe
  |> must ("bad " ++ field)

mustMarketCreator : Pb.UserMarketView -> Pb.UserUserView
mustMarketCreator {creator} = must "all markets must have creators" creator

mustMarketCertainty : Pb.UserMarketView -> Pb.CertaintyRange
mustMarketCertainty {certainty} = must "all markets must have certainties" certainty

mustTradeBettor : Pb.Trade -> Pb.UserId
mustTradeBettor {bettor} = must "all trades must have bettors" bettor

mustUserKind : Pb.UserId -> Pb.Kind
mustUserKind {kind} = must "all UserIds must have kinds" kind

mustTokenOwner : Pb.AuthToken -> Pb.UserId
mustTokenOwner {owner} = must "all AuthTokens must have owners" owner

mustMarketsById : Pb.MarketsById -> Dict Int Pb.UserMarketView
mustMarketsById {markets} = markets |> Dict.map (\_ v -> must "no null values are allowed in a MarketsById" v)

currentResolution : Pb.UserMarketView -> Pb.Resolution
currentResolution market =
  List.head (List.reverse market.resolutions)
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

unixtimeToTime : Int -> Time.Posix
unixtimeToTime n = Time.millisToPosix (n*1000)
timeToUnixtime : Time.Posix -> Int
timeToUnixtime t = Time.posixToMillis t // 1000

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

renderIntervalSeconds : Int -> String
renderIntervalSeconds seconds =
  let
    divmod : Int -> Int -> (Int, Int)
    divmod n div = (n // div , n |> modBy div)
    (minutes,s) = divmod seconds 60
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

marketCreatedTime : Pb.UserMarketView -> Time.Posix
marketCreatedTime market = market.createdUnixtime * 1000 |> Time.millisToPosix

marketClosesTime : Pb.UserMarketView -> Time.Posix
marketClosesTime market = market.closesUnixtime * 1000 |> Time.millisToPosix

secondsToClose : Time.Posix -> Pb.UserMarketView -> Int
secondsToClose now market = market.closesUnixtime - Time.posixToMillis now // 1000

pathToUserPage : Pb.UserId -> String
pathToUserPage user =
  case mustUserKind user of
    Pb.KindUsername username -> "/username/" ++ username
