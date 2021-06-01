module Widgets.Navbar exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA

import Widgets.AuthWidget as AuthWidget

view : AuthWidget.Config msg -> AuthWidget.State -> Html msg
view config state =
  let
    loggedInItems : List (Html msg)
    loggedInItems =
      [ H.li [] [H.a [HA.href "/new"] [H.text "New prediction"]]
      , H.li [] [H.a [HA.href "/my_stakes"] [H.text "My stakes"]]
      , H.li [] [H.a [HA.href "/settings"] [H.text "Settings"]]
      ]
  in
  H.nav [HA.class "navbar-wrapper"]
    [ H.ul [] <|
        H.li [] [H.a [HA.href "/"] [H.text "Home"]]
        :: (if config.auth == Nothing then [] else loggedInItems)
        ++ [H.li []
            [ AuthWidget.view config state
            ]]
    ]
