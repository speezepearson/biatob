port module Elements.ViewUser exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD
import Dict

import Biatob.Proto.Mvp as Pb
import API
import Utils exposing (Username)

import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Widgets.ViewPredictionsWidget as ViewPredictionsWidget
import Page
import Page exposing (Command(..))

port copy : String -> Cmd msg
port navigate : Maybe String -> Cmd msg

type alias Model =
  { globals : Page.Globals
  , navbarAuth : AuthWidget.State
  , who : Username
  , predictionsWidget : ViewPredictionsWidget.State
  , working : Bool
  , notification : Html Never
  , invitationWidget : SmallInvitationWidget.State
  }

type Msg
  = SetTrusted Bool
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)
  | SetAuthWidget AuthWidget.State
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | SetPredictionsWidget ViewPredictionsWidget.State
  | SetInvitationWidget SmallInvitationWidget.State
  | CreateInvitation SmallInvitationWidget.State Pb.CreateInvitationRequest
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)
  | Copy String
  | Ignore

init : JD.Value -> ( Model, Cmd Msg )
init flags =
  ( { globals = JD.decodeValue Page.globalsDecoder flags |> Result.toMaybe |> Utils.must "flags"
    , navbarAuth = AuthWidget.init
    , who = Utils.mustDecodeFromFlags JD.string "who" flags
    , predictionsWidget = ViewPredictionsWidget.init
    , working = False
    , notification = H.text ""
    , invitationWidget = SmallInvitationWidget.init
    }
  , Cmd.none
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetTrusted trusted ->
      ( { model | working = True , notification = H.text "" }
      , API.postSetTrusted SetTrustedFinished {who=model.who, whoDepr=Nothing, trusted=trusted}
      )
    SetTrustedFinished res ->
      ( case res of
          Err e ->
            { model | working = False , notification = Utils.redText (Debug.toString e) }
          Ok resp ->
            case resp.setTrustedResult of
              Just (Pb.SetTrustedResultOk _) ->
                { model | working = False, notification = H.text "" }
              Just (Pb.SetTrustedResultError e) ->
                { model | working = False , notification = Utils.redText (Debug.toString e) }
              Nothing ->
                { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
      , Cmd.none
      )
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
      , navigate Nothing
      )
    SetPredictionsWidget widgetState ->
      ( { model | predictionsWidget = widgetState } , Cmd.none )
    SetInvitationWidget widgetState ->
      ( { model | invitationWidget = widgetState } , Cmd.none )
    CreateInvitation widgetState req ->
      ( { model | invitationWidget = widgetState }
      , API.postCreateInvitation CreateInvitationFinished req
      )
    CreateInvitationFinished res ->
      ( { model | invitationWidget = model.invitationWidget |> SmallInvitationWidget.handleCreateInvitationResponse res }
      , Cmd.none
      )
    Copy s ->
      ( model
      , copy s
      )
    Ignore ->
      ( model , Cmd.none )


view : Model -> Browser.Document Msg
view model =
  {title=model.who, body=
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
    [ H.h2 [] [H.text model.who]
    , H.br [] []
    , if Page.isSelf model.globals model.who then
        H.div []
          [ H.text "This is you! You might have meant to visit "
          , H.a [HA.href "/settings"] [H.text "your settings"]
          , H.text "?"
          ]
      else case model.globals.serverState.settings of
        Nothing -> H.text "Log in to see your relationship with this user."
        Just _ ->
          H.div []
            [ if Page.getRelationship model.globals model.who |> Maybe.map .trusting |> Maybe.withDefault False then
                H.text "This user trusts you! :)"
              else
                H.div []
                  [ H.text "This user hasn't marked you as trusted! If you think that, in real life, they "
                  , Utils.i "do"
                  , H.text " trust you, send them an invitation: "
                  , SmallInvitationWidget.view
                      { setState = SetInvitationWidget
                      , createInvitation = CreateInvitation
                      , copy = Copy
                      , destination = Just <| "/username/" ++ model.who
                      , httpOrigin = model.globals.httpOrigin
                      }
                      model.invitationWidget
                  ]
            , H.br [] []
            , if Page.getRelationship model.globals model.who |> Maybe.map .trusted |> Maybe.withDefault False then
                H.div []
                  [ H.text "You trust this user. "
                  , H.button [HA.disabled model.working, HE.onClick (SetTrusted False)] [H.text "Mark untrusted"]
                  ]
              else
                H.div []
                  [ H.text "You don't trust this user. "
                  , H.button [HA.disabled model.working, HE.onClick (SetTrusted True)] [H.text "Mark trusted"]
                  ]
            , model.notification |> H.map never
            , H.br [] []
            , if Page.getRelationship model.globals model.who |> Maybe.map .trusting |> Maybe.withDefault False then
                H.div []
                  [ H.h3 [] [H.text "Predictions"]
                  , ViewPredictionsWidget.view
                      { setState = SetPredictionsWidget
                      , predictions = model.globals.serverState.predictions
                      , allowFilterByOwner = False
                      , self = model.globals.authToken |> Maybe.map .owner |> Maybe.withDefault "TODO"
                      , now = model.globals.now
                      , timeZone = model.globals.timeZone
                      }
                      model.predictionsWidget
                  ]
              else
                H.text ""
            ]
  ]]}

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main = Browser.document {init=init, view=view, update=update, subscriptions=\_ -> Sub.none}
