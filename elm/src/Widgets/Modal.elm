port module Widgets.Modal exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA

port showModal : Bool -> Cmd msg

type alias Config msg =
  { header : List (Html msg)
  , body : List (Html msg)
  , footer : List (Html msg)
  , show : Bool
  }

view : Config msg -> Html msg
view config =
  H.div [HA.id "modal", HA.class "modal fade", HA.class (if config.show then "" else "d-none")]
  [ H.div [HA.class "modal-dialog"]
    [ H.div [HA.class "modal-content"]
      [ H.div [HA.class "modal-header"] config.header
      , H.div [HA.class "modal-body"] config.body
      , H.div [HA.class "modal-footer"] config.footer
      ]
    ]
  ]
