module Utils exposing (..)

import Html as H
import Html.Attributes as HA

import Biatob.Proto.Mvp as Pb


formatDollars : Float -> String
formatDollars n =
  if n < 0 then "-" ++ formatDollars (-n) else
  let
    approxCents = round (100 * n)
    fullDollars = approxCents // 100
    centsOnly = approxCents |> modBy 100
  in
    "$" ++ (String.fromInt fullDollars) ++ if centsOnly == 0 then "" else ("." ++ String.fromInt centsOnly)

capitalize : String -> String
capitalize s =
  String.toUpper (String.left 1 s) ++ String.dropLeft 1 s

must : String -> Maybe a -> a
must errmsg mx =
  case mx of
    Just x -> x
    Nothing -> Debug.todo errmsg

they : Pb.Pronouns -> String
they pronouns = case pronouns of
  Pb.HeHim -> "he"
  Pb.SheHer -> "she"
  Pb.TheyThem -> "they"
  _ -> "they"

them : Pb.Pronouns -> String
them pronouns = case pronouns of
  Pb.HeHim -> "him"
  Pb.SheHer -> "her"
  Pb.TheyThem -> "them"
  _ -> "them"

their : Pb.Pronouns -> String
their pronouns = case pronouns of
  Pb.HeHim -> "his"
  Pb.SheHer -> "her"
  Pb.TheyThem -> "their"
  Pb.PronounsUnrecognized_ _ -> "their"

pluralize : Pb.Pronouns -> (String, String) -> String
pluralize pronouns (singular, plural) = case pronouns of
  Pb.HeHim -> singular
  Pb.SheHer -> singular
  Pb.TheyThem -> plural
  Pb.PronounsUnrecognized_ _ -> plural

outlineIfInvalid : Bool -> H.Attribute msg
outlineIfInvalid isInvalid =
  HA.style "outline" (if isInvalid then "2px solid red" else "none")
