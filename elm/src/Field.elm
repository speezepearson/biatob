module Field exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE

{- Consider just using https://github.com/rtfeldman/elm-validate instead of this module? -}

type alias Field ctx a =
  { string : String
  , parse : ctx -> String -> Result String a
  , highlightErrorIfEmpty : Bool
  }

init : String -> (ctx -> String -> Result String a ) -> Field ctx a
init string parse_ = {string=string, parse=parse_, highlightErrorIfEmpty=True}

okIfEmpty : Field ctx a -> Field ctx a
okIfEmpty f = { f | highlightErrorIfEmpty = False }

raw : Field ctx a -> String
raw f = f.string

setStr : String -> Field ctx a -> Field ctx a
setStr s f = { f | string = s }

parse : ctx -> Field ctx a -> Result String a
parse ctx f = f.parse ctx f.string

isValid : ctx -> Field ctx a -> Bool
isValid ctx f =
  case parse ctx f of
    Ok _ -> True
    Err _ -> False

inputFor : (String -> msg) -> ctx -> Field ctx a -> (List (H.Attribute msg) -> List (Html msg) -> Html msg) -> List (H.Attribute msg) -> List (Html msg) -> H.Html msg
inputFor onInput ctx field ctor attrs children =
  let
    allAttrs =
      HA.value field.string
      :: HE.onInput onInput
      :: attrs
  in
  case parse ctx field of
    Ok _ ->
      H.span [] -- required so Elm can identify the ctor output in this branch with the other branch, so focus isn't lost when errorness toggles
        [ ctor allAttrs children
        ]
    Err e ->
      if List.member (HA.disabled True) attrs || (field.string == "" && not field.highlightErrorIfEmpty) then
        H.span []
          [ ctor allAttrs children
          ]
      else
        H.span [HA.style "outline" "1px solid red"]
          [ ctor allAttrs children
          , H.span [HA.style "color" "red"] [H.text e]
          ]
