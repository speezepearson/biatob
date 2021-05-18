module Widgets.Navbar exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA

import Widgets.AuthWidget as AuthWidget
import Page

type alias Model = { authWidget : AuthWidget.Model }
type Msg
  = AuthWidgetMsg AuthWidget.Msg

init : Model
init = { authWidget = AuthWidget.init }

view : Page.Globals -> Model -> Html Msg
view globals model =
  let
    loggedInItems : List (Html Msg)
    loggedInItems =
      [ H.li [] [H.a [HA.href "/new"] [H.text "New prediction"]]
      , H.li [] [H.a [HA.href "/my_stakes"] [H.text "My stakes"]]
      , H.li [] [H.a [HA.href "/settings"] [H.text "Settings"]]
      ]
  in
  H.nav [HA.class "navbar-wrapper"]
    [ H.ul [] <|
        H.li [] [H.a [HA.href "/"] [H.text "Home"]]
        :: (if Page.isLoggedIn globals then loggedInItems else [])
        ++ [H.li [] [AuthWidget.view globals model.authWidget |> H.map AuthWidgetMsg]]
    ]

update : Msg -> Model -> ( Model , Page.Command Msg )
update msg model =
  case msg of
    AuthWidgetMsg widgetMsg ->
      let (newWidget, innerCmd) = AuthWidget.update widgetMsg model.authWidget in
      ( { model | authWidget = newWidget } , Page.mapCmd AuthWidgetMsg innerCmd )

subscriptions : Model -> Sub Msg
subscriptions model = AuthWidget.subscriptions model.authWidget |> Sub.map AuthWidgetMsg
