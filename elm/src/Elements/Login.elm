module Elements.Login exposing (main)

import Html as H

import Page
import Page.Program

type alias Model = ()
type alias Msg = Never

pagedef : Page.Element Model Msg
pagedef =
  { init = \_ -> ((), Page.NoCmd)
  , view = \g m -> {title="Log in", body=[H.h2 [] [H.text "Log in"], H.main_ [] [H.text "...using the navbar at the top, as always."]]}
  , update = never
  , subscriptions = \() -> Sub.none
  }

main = Page.Program.page pagedef
