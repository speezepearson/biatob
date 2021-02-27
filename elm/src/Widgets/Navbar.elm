module Widgets.Navbar exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Http

import Widgets.AuthWidget as AuthWidget
import Page
import Biatob.Proto.Mvp as Pb

type alias Model = { authWidget : AuthWidget.State }
type Msg
  = AuthEvent (Maybe AuthWidget.Event) AuthWidget.State
  | LogInUsernameFinished (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsernameFinished (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOutFinished (Result Http.Error Pb.SignOutResponse)


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
        [H.li [] [H.a [HA.href "/"] [H.text "Home"]]]
        ++ (if Page.isLoggedIn globals then loggedInItems else [])
        ++ [H.li [] [AuthWidget.view {auth=Page.getAuth globals, now=globals.now, handle=AuthEvent} model.authWidget]]
    ]

update : Msg -> Model -> ( Model , Page.Command Msg )
update msg model =
  case msg of
    AuthEvent event newState ->
      ( { model | authWidget = newState }
      , case event of
          Just (AuthWidget.LogInUsername req) -> Page.RequestCmd (Page.LogInUsernameRequest LogInUsernameFinished req)
          Just (AuthWidget.RegisterUsername req) -> Page.RequestCmd (Page.RegisterUsernameRequest RegisterUsernameFinished req)
          Just (AuthWidget.SignOut req) -> Page.RequestCmd (Page.SignOutRequest SignOutFinished req)
          Nothing -> Page.NoCmd
      )
    LogInUsernameFinished res -> ( { model | authWidget = model.authWidget |> AuthWidget.handleLogInUsernameResponse {updateWidget=\f s -> f s, setAuth=always identity} res } , Page.NoCmd )
    RegisterUsernameFinished res -> ( { model | authWidget = model.authWidget |> AuthWidget.handleRegisterUsernameResponse {updateWidget=\f s -> f s, setAuth=always identity} res } , Page.NoCmd )
    SignOutFinished res -> ( { model | authWidget = model.authWidget |> AuthWidget.handleSignOutResponse {updateWidget=\f s -> f s, setAuth=always identity} res } , Page.NoCmd )
