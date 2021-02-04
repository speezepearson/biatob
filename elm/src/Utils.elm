module Utils exposing (..)

import Html as H
import Html.Attributes as HA
import Json.Decode as JD
import Time

import Base64
import Protobuf.Decode as PD
import Protobuf.Encode as PE

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

renderUser : Pb.UserId -> String
renderUser user =
  user.kind |> must "all users have kinds" |> (\k -> case k of
    Pb.KindUsername username -> username
  )

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
    Pb.ResolutionUnrecognized_ _ -> Debug.todo "unrecognized resolution"

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

renderIntervalSeconds : Int -> String
renderIntervalSeconds seconds =
  let
    divmod : Int -> Int -> (Int, Int)
    divmod n div = (n // div , n |> modBy div)
    t0 = seconds
    (w,t1) = divmod t0 (60*60*24*7)
    (d,t2) = divmod t1 (60*60*24)
    (h,t3) = divmod t2 (60*60)
    (m,s) = divmod t3 (60)
  in
    if w /= 0 then String.fromInt w ++ "w " ++ String.fromInt d ++ "d" else
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
