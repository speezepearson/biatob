module Utils exposing (..)

import Html as H
import Html.Attributes as HA
import Json.Decode as JD
import Json.Encode as JE

import Base64
import Protobuf.Decode as PD
import Protobuf.Encode as PE

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

outlineIfInvalid : Bool -> H.Attribute msg
outlineIfInvalid isInvalid =
  HA.style "outline" (if isInvalid then "2px solid red" else "none")


decodePbB64 : PD.Decoder a -> String -> Maybe a
decodePbB64 dec s =
  s |> Base64.toBytes |> Maybe.andThen (PD.decode dec)
encodePbB64 : PE.Encoder -> String
encodePbB64 enc =
  PE.encode enc |> Base64.fromBytes |> must "Base64.fromBytes docs say it will never return Nothing"
