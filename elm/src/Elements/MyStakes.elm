port module Elements.MyStakes exposing (main)

import Html as H
import Json.Decode as JD
import Http

import Biatob.Proto.Mvp as Pb
import Utils

import Biatob.Proto.Mvp exposing (StakeResult(..))
import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Widgets.ViewPredictionsWidget as ViewPredictionsWidget
import Page
import Browser
import API

port navigate : Maybe String -> Cmd msg

type alias Model =
  { globals : Page.Globals
  , navbarAuth : AuthWidget.State
  , predictionsWidget : ViewPredictionsWidget.State
  }
type Msg
  = SetAuthWidget AuthWidget.State
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | SetPredictionsWidget ViewPredictionsWidget.State
  | Ignore

init : JD.Value -> ( Model, Cmd Msg )
init flags =
  ( { globals = JD.decodeValue Page.globalsDecoder flags |> Result.toMaybe |> Utils.must "flags"
    , navbarAuth = AuthWidget.init
    , predictionsWidget = ViewPredictionsWidget.init
    }
  , Cmd.none
  )

view : Model -> Browser.Document Msg
view model =
  { title = "My stakes"
  , body =
    [ Navbar.view
        { setState = SetAuthWidget
        , logInUsername = LogInUsername
        , register = RegisterUsername
        , signOut = SignOut
        , ignore = Ignore
        , auth = Page.getAuth model.globals
        }
        model.navbarAuth
    , H.main_ []
      [ H.h2 [] [H.text "My Stakes"]
      , ViewPredictionsWidget.view
          { setState = SetPredictionsWidget
          , predictions = model.globals.serverState.predictions
          , allowFilterByOwner = True
          , self = model.globals.authToken |> Maybe.map .owner |> Maybe.withDefault "TODO"
          , now = model.globals.now
          , timeZone = model.globals.timeZone
          }
          model.predictionsWidget
      ]
    ]
  }

update : Msg -> Model -> ( Model , Cmd Msg )
update msg model =
  case msg of
    SetAuthWidget widgetState ->
      ( { model | navbarAuth = widgetState } , Cmd.none )
    LogInUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postLogInUsername (LogInUsernameFinished req) req
      )
    LogInUsernameFinished req res ->
      ( { model | globals = model.globals |> Page.handleLogInUsernameResponse req res , navbarAuth = model.navbarAuth |> AuthWidget.handleLogInUsernameResponse res }
      , navigate Nothing
      )
    RegisterUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postRegisterUsername (RegisterUsernameFinished req) req
      )
    RegisterUsernameFinished req res ->
      ( { model | globals = model.globals |> Page.handleRegisterUsernameResponse req res , navbarAuth = model.navbarAuth |> AuthWidget.handleRegisterUsernameResponse res }
      , navigate Nothing
      )
    SignOut widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postSignOut (SignOutFinished req) req
      )
    SignOutFinished req res ->
      ( { model | globals = model.globals |> Page.handleSignOutResponse req res , navbarAuth = model.navbarAuth |> AuthWidget.handleSignOutResponse res }
      , navigate <| Just "/"
      )
    SetPredictionsWidget widgetState ->
      ( { model | predictionsWidget = widgetState } , Cmd.none )
    Ignore ->
      ( model , Cmd.none )


main = Browser.document {init=init, view=view, update=update, subscriptions=\_ -> Sub.none}
