port module Elements.ViewUser exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import API
import Utils exposing (Username)

import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Widgets.ViewPredictionsWidget as ViewPredictionsWidget
import Globals

port copy : String -> Cmd msg
port navigate : Maybe String -> Cmd msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , who : Username
  , predictionsWidget : ViewPredictionsWidget.State
  , working : Bool
  , notification : Html Never
  , invitationWidget : SmallInvitationWidget.State
  }

type Msg
  = SetAuthWidget AuthWidget.State
  | SetInvitationWidget SmallInvitationWidget.State
  | SetPredictionsWidget ViewPredictionsWidget.State
  | CreateInvitation SmallInvitationWidget.State Pb.CreateInvitationRequest
  | CreateInvitationFinished Pb.CreateInvitationRequest (Result Http.Error Pb.CreateInvitationResponse)
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | SetTrusted Bool
  | SetTrustedFinished Pb.SetTrustedRequest (Result Http.Error Pb.SetTrustedResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | Copy String
  | Ignore

init : JD.Value -> ( Model, Cmd Msg )
init flags =
  ( { globals = JD.decodeValue Globals.globalsDecoder flags |> Result.toMaybe |> Utils.must "flags"
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
    SetAuthWidget widgetState ->
      ( { model | navbarAuth = widgetState } , Cmd.none )
    SetInvitationWidget widgetState ->
      ( { model | invitationWidget = widgetState } , Cmd.none )
    SetPredictionsWidget widgetState ->
      ( { model | predictionsWidget = widgetState } , Cmd.none )
    CreateInvitation widgetState req ->
      ( { model | invitationWidget = widgetState }
      , API.postCreateInvitation (CreateInvitationFinished req) req
      )
    CreateInvitationFinished req res ->
      ( { model | globals = model.globals |> Globals.handleCreateInvitationResponse req res
                , invitationWidget = model.invitationWidget |> SmallInvitationWidget.handleCreateInvitationResponse res
        }
      , Cmd.none
      )
    LogInUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postLogInUsername (LogInUsernameFinished req) req
      )
    LogInUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleLogInUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleLogInUsernameResponse res
        }
      , navigate Nothing
      )
    RegisterUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postRegisterUsername (RegisterUsernameFinished req) req
      )
    RegisterUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleRegisterUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleRegisterUsernameResponse res
        }
      , navigate Nothing
      )
    SetTrusted trusted ->
      let req = {who=model.who, whoDepr=Nothing, trusted=trusted} in
      ( { model | working = True , notification = H.text "" }
      , API.postSetTrusted (SetTrustedFinished req) req
      )
    SetTrustedFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSetTrustedResponse req res
                , working = False
                , notification = case API.simplifySetTrustedResponse res of
                    Ok _ -> H.text ""
                    Err e -> Utils.redText e
        }
      , Cmd.none
      )
    SignOut widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postSignOut (SignOutFinished req) req
      )
    SignOutFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSignOutResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleSignOutResponse res
        }
      , navigate Nothing
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
        , auth = Globals.getAuth model.globals
        }
        model.navbarAuth
    , H.main_ []
    [ H.h2 [] [H.text model.who]
    , H.br [] []
    , if Globals.isSelf model.globals model.who then
        H.div []
          [ H.text "This is you! You might have meant to visit "
          , H.a [HA.href "/settings"] [H.text "your settings"]
          , H.text "?"
          ]
      else case model.globals.serverState.settings of
        Nothing -> H.text "Log in to see your relationship with this user."
        Just _ ->
          H.div []
            [ if Globals.getRelationship model.globals model.who |> Maybe.map .trusting |> Maybe.withDefault False then
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
            , if Globals.getRelationship model.globals model.who |> Maybe.map .trusted |> Maybe.withDefault False then
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
            , if Globals.getRelationship model.globals model.who |> Maybe.map .trusting |> Maybe.withDefault False then
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
