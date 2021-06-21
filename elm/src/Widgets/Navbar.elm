module Widgets.Navbar exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA

import Widgets.AuthWidget as AuthWidget

view : AuthWidget.Config msg -> AuthWidget.State -> Html msg
view config state =
  let
    loggedInItems : List (Html msg)
    loggedInItems =
      [ H.li [HA.class "nav-item"] [H.a [HA.class "nav-link", HA.href "/new"] [H.text "New prediction"]]
      , H.li [HA.class "nav-item"] [H.a [HA.class "nav-link", HA.href "/my_stakes"] [H.text "My stakes"]]
      , H.li [HA.class "nav-item"] [H.a [HA.class "nav-link", HA.href "/settings"] [H.text "Settings"]]
      ]

    navItems : List (Html msg)
    navItems =
      H.li [HA.class "nav-item"] [H.a [HA.class "nav-link", HA.href "/"] [H.text "Home"]]
      :: if config.auth == Nothing then [] else loggedInItems

  in
  H.nav [HA.class "navbar", HA.class "navbar-expand-lg", HA.class "navbar-light", HA.class "bg-light"]
  [ H.div [HA.class "container"]
    [ H.a [HA.class "navbar-brand", HA.href "#"]
      [ H.text "Biatob" ]
    , H.button [HA.class "navbar-toggler", HA.attribute "type" "button", HA.attribute "data-bs-toggle" "collapse", HA.attribute "data-bs-target" "#navbarSupportedContent", HA.attribute "aria-controls" "navbarSupportedContent", HA.attribute "aria-expanded" "false", HA.attribute "aria-label" "Toggle navigation"]
      [ H.span [HA.class "navbar-toggler-icon"] []
      ]
    , H.div [HA.class "collapse", HA.class "navbar-collapse", HA.attribute "id" "navbarSupportedContent"]
      [ H.ul [HA.class "navbar-nav", HA.class "me-auto", HA.class "mb-2", HA.class "mb-lg-0"]
        navItems
      ]
    , H.div [HA.class "collapse", HA.class "navbar-collapse", HA.attribute "id" "navbarSupportedContent"]
      [ H.ul [HA.class "navbar-nav", HA.class "ms-auto"]
        [ H.li [HA.class "nav-item"] [AuthWidget.view config state]
        ]
      ]
    ]
  ]
