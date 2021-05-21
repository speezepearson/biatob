module Widgets.Navbar exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Http

import Widgets.AuthWidget as AuthWidget
import Page
import Biatob.Proto.Mvp as Pb

type alias Model = { authWidget : AuthWidget.State }
type Msg
  = SetAuthWidget AuthWidget.State
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished (Result Http.Error Pb.SignOutResponse)
  | Ignore

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
        ++ [H.li []
            [ AuthWidget.view
                { setState = SetAuthWidget
                , logInUsername = LogInUsername
                , register = RegisterUsername
                , signOut = SignOut
                , ignore = Ignore
                , auth = Page.getAuth globals
                }
                model.authWidget
            ]]
    ]

update : Msg -> Model -> ( Model , Page.Command Msg )
update msg model =
  case msg of
    SetAuthWidget widgetState ->
      ( { model | authWidget = widgetState } , Page.NoCmd )
    LogInUsername widgetState req ->
      ( { model | authWidget = widgetState }
      , Page.RequestCmd <| Page.LogInUsernameRequest LogInUsernameFinished req
      )
    LogInUsernameFinished res ->
      ( { model | authWidget = model.authWidget |> AuthWidget.handleLogInUsernameResponse res }
      , Page.NoCmd
      )
    RegisterUsername widgetState req ->
      ( { model | authWidget = widgetState }
      , Page.RequestCmd <| Page.RegisterUsernameRequest RegisterUsernameFinished req
      )
    RegisterUsernameFinished res ->
      ( { model | authWidget = model.authWidget |> AuthWidget.handleRegisterUsernameResponse res }
      , Page.NoCmd
      )
    SignOut widgetState req ->
      ( { model | authWidget = widgetState }
      , Page.RequestCmd <| Page.SignOutRequest SignOutFinished req
      )
    SignOutFinished res ->
      ( { model | authWidget = model.authWidget |> AuthWidget.handleSignOutResponse res }
      , Page.NoCmd
      )
    Ignore ->
      ( model , Page.NoCmd )

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
