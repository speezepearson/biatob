module Utils exposing (..)

import Html as H
import Html.Attributes as HA
import Json.Decode as JD
import Json.Encode as JE

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
