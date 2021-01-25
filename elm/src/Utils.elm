module Utils exposing (..)

import Biatob.Proto.Mvp as Pb


must : String -> Maybe a -> a
must errmsg mx =
  case mx of
    Just x -> x
    Nothing -> Debug.todo errmsg

logoddsToProb : Float -> Float
logoddsToProb logodds =
  let odds = e^logodds
  in odds / (odds+1)

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
