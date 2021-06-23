module Widgets.CopyWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE

view : (String -> msg) -> String -> Html msg
view onClick value =
  H.span []
    [ H.input [HA.class "form-control form-control-sm", HA.style "display" "inline-block", HA.attribute "readonly" "", HA.value value, HA.style "width" "auto", HA.style "max-width" "10em"] []
    , H.button [HA.class "btn btn-sm py-0 btn-outline-primary m-1", HE.onClick (onClick value)] [H.text "Copy"]
    ]
