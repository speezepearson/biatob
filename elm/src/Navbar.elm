module Navbar exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Json.Decode as JD
import Html exposing (Html)

import AuthWidget

type alias Model =
  { authWidget : AuthWidget.Model
  , authExpanded : Bool
  }

type Msg
  = AuthMsg AuthWidget.Msg

init : JD.Value -> ( Model , Cmd Msg )
init flags =
  let (authWidget, authCmd) = AuthWidget.init flags in
  ( { authWidget = authWidget , authExpanded = False }
  , Cmd.map AuthMsg authCmd
  )

view : Model -> Html Msg
view model =
  H.ul [HA.style "width" "100%", HA.style "display" "flex", HA.style "flex-direction" "row", HA.style "list-style" "none", HA.style "background-color" "lightblue", HA.style "align-items" "center"]
    [ H.li [HA.style "margin" "0.5ex 1ex"] [H.a [HA.href "/"] [H.text "Home"]]
    , H.li [HA.style "margin" "0.5ex 1ex"] [H.a [HA.href "/new"] [H.text "New market"]]
    , if AuthWidget.hasAuth model.authWidget then
        H.li [HA.style "margin" "0.5ex 1ex"] [H.a [HA.href "/markets"] [H.text "My markets"]]
      else
        H.text ""
    , H.li [HA.style "margin" "0.5ex 1ex"] [AuthWidget.view model.authWidget |> H.map AuthMsg]
    ]

update : Msg -> Model -> ( Model , Cmd Msg )
update msg model =
  case msg of
    AuthMsg authMsg ->
      let (newWidget, authCmd) = AuthWidget.update authMsg model.authWidget in
      ( { model | authWidget = newWidget } , Cmd.map AuthMsg authCmd)

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.map AuthMsg (AuthWidget.subscriptions model.authWidget)

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }
