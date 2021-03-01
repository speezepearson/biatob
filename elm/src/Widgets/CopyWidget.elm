module Widgets.CopyWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE

view : (String -> msg) -> String -> Html msg
view onClick value =
  H.span []
    [ H.input [HA.value value, HA.style "width" "4em"] []
    , H.button [HE.onClick (onClick value)] [H.text "Copy"]
    ]
