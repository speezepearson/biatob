port module Elements.ViewUser exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import API
import Utils exposing (RequestStatus(..), Username)

import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Widgets.ViewPredictionsWidget as ViewPredictionsWidget
import Globals
import Time
import Dict exposing (Dict)

port copy : String -> Cmd msg
port navigate : Maybe String -> Cmd msg
port authWidgetExternallyChanged : (AuthWidget.DomModification -> msg) -> Sub msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , who : Username
  , predictionsWidget : ViewPredictionsWidget.State
  , sendInvitationRequestStatus : RequestStatus
  , setTrustedRequestStatus : RequestStatus
  }

type Msg
  = SetAuthWidget AuthWidget.State
  | SetPredictionsWidget ViewPredictionsWidget.State
  | SendInvitation
  | SendInvitationFinished Pb.SendInvitationRequest (Result Http.Error Pb.SendInvitationResponse)
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | SetTrusted Bool
  | SetTrustedFinished Pb.SetTrustedRequest (Result Http.Error Pb.SetTrustedResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | Copy String
  | Tick Time.Posix
  | AuthWidgetExternallyModified AuthWidget.DomModification
  | Ignore

init : JD.Value -> ( Model, Cmd Msg )
init flags =
  ( { globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
    , navbarAuth = AuthWidget.init
    , who = Utils.mustDecodeFromFlags JD.string "who" flags
    , predictionsWidget = ViewPredictionsWidget.init
    , sendInvitationRequestStatus = Unstarted
    , setTrustedRequestStatus = Unstarted
    }
  , Cmd.none
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetAuthWidget widgetState ->
      ( { model | navbarAuth = widgetState } , Cmd.none )
    SetPredictionsWidget widgetState ->
      ( { model | predictionsWidget = widgetState } , Cmd.none )
    SendInvitation ->
      ( { model | sendInvitationRequestStatus = AwaitingResponse }
      , let req = {recipient=model.who} in API.postSendInvitation (SendInvitationFinished req) req
      )
    SendInvitationFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSendInvitationResponse req res
                , sendInvitationRequestStatus = case API.simplifySendInvitationResponse res of
                    Ok _ -> Succeeded
                    Err e -> Failed e
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
      , case API.simplifyLogInUsernameResponse res of
          Ok _ -> navigate <| Nothing
          Err _ -> Cmd.none
      )
    RegisterUsername widgetState req ->
      ( { model | navbarAuth = widgetState }
      , API.postRegisterUsername (RegisterUsernameFinished req) req
      )
    RegisterUsernameFinished req res ->
      ( { model | globals = model.globals |> Globals.handleRegisterUsernameResponse req res
                , navbarAuth = model.navbarAuth |> AuthWidget.handleRegisterUsernameResponse res
        }
      , case API.simplifyRegisterUsernameResponse res of
          Ok _ -> navigate <| Nothing
          Err _ -> Cmd.none
      )
    SetTrusted trusted ->
      let req = {who=model.who, whoDepr=Nothing, trusted=trusted} in
      ( { model | setTrustedRequestStatus = AwaitingResponse }
      , API.postSetTrusted (SetTrustedFinished req) req
      )
    SetTrustedFinished req res ->
      ( { model | globals = model.globals |> Globals.handleSetTrustedResponse req res
                , setTrustedRequestStatus = case API.simplifySetTrustedResponse res of
                    Ok _ -> Succeeded
                    Err e -> Failed e
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
      , case API.simplifySignOutResponse res of
          Ok _ -> navigate <| Nothing
          Err _ -> Cmd.none
      )
    Copy s ->
      ( model
      , copy s
      )
    Tick now ->
      ( { model | globals = model.globals |> Globals.tick now }
      , Cmd.none
      )
    AuthWidgetExternallyModified mod ->
      ( { model | navbarAuth = model.navbarAuth |> AuthWidget.handleDomModification mod }
      , Cmd.none
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
        , id = "navbar-auth"
        }
        model.navbarAuth
    , H.main_ [HA.class "container"]
    [ H.h2 [] [H.text model.who]
    , H.br [] []
    , case Globals.getTrustRelationship model.globals model.who of
        Globals.Self ->
          H.p []
            [ H.text "This is you! You might have meant to visit "
            , H.a [HA.href "/settings"] [H.text "your settings"]
            , H.text "?"
            ]
        Globals.LoggedOut ->
          H.text "Log in to see your relationship with this user."
        Globals.NoRelation ->
          H.p []
            [ H.text "You have no relationship with this user! If you're confident that you know who owns this account, and in real life you trust them to pay their debts, and they trust you too,"
            , H.text " then send them an invitation!"
            , H.button
              [ HA.disabled (model.sendInvitationRequestStatus==AwaitingResponse)
              , HE.onClick SendInvitation
              , HA.class "btn btn-sm btn-outline-primary mx-1"
              ]
              [ H.text "I trust this person, and they trust me too" ]
            , case model.sendInvitationRequestStatus of
                Unstarted -> H.text ""
                AwaitingResponse -> H.text ""
                Succeeded -> Utils.greenText "✓"
                Failed e -> Utils.redText e
            , H.text " and then I'll let you bet against each other!"
            ]
        Globals.TrustsCurrentUser ->
          H.p []
            [ H.text "This user trusts you, but you don't trust them back! If you're confident that you know who owns this account, and in real life you ", Utils.i "do", H.text " trust them to pay their debts,"
            , H.text " then click "
            , H.button
              [ HA.disabled (model.setTrustedRequestStatus==AwaitingResponse)
              , HE.onClick (SetTrusted True) 
              , HA.class "btn btn-sm btn-outline-primary mx-1"
              ]
              [ H.text "I trust this person" ]
            , case model.setTrustedRequestStatus of
                Unstarted -> H.text ""
                AwaitingResponse -> H.text ""
                Succeeded -> Utils.greenText "✓"
                Failed e -> Utils.redText e
            , H.text " and then I'll let you bet against each other!"
            ]
        Globals.TrustedByCurrentUser ->
          H.p []
            [ H.text "You trust this user, but they don't trust you back! If you're confident that you know who owns this account, and in real life you think they ", Utils.i "do", H.text " trust you to pay your debts,"
            , H.text " then send them an invitation!"
            , H.button
              [ HA.disabled (model.sendInvitationRequestStatus==AwaitingResponse)
              , HE.onClick SendInvitation
              , HA.class "btn btn-sm btn-outline-primary mx-1"
              ]
              [ H.text "I think this person trusts me" ]
            , case model.sendInvitationRequestStatus of
                Unstarted -> H.text ""
                AwaitingResponse -> H.text ""
                Succeeded -> Utils.greenText "✓"
                Failed e -> Utils.redText e
            , H.text " and then I'll let you bet against each other!"
            , H.br [] []
            , H.text "...or, if you ", Utils.i "don't", H.text " trust them anymore, you can"
            , H.button
              [ HA.disabled (model.setTrustedRequestStatus == AwaitingResponse)
              , HE.onClick (SetTrusted False)
              , HA.class "btn btn-sm btn-outline-primary mx-1"
              ] [H.text "mark this user untrusted"]
            , case model.setTrustedRequestStatus of
                Unstarted -> H.text ""
                AwaitingResponse -> H.text ""
                Succeeded -> Utils.greenText "✓"
                Failed e -> Utils.redText e
            ]
        Globals.Friends ->
          H.p []
            [ H.text "You and this user trust each other! Aww, how nice!"
            , H.br [] []
            , H.text "...but, if you ", Utils.i "don't", H.text " trust them anymore, you can"
            , H.button
              [ HA.disabled (model.setTrustedRequestStatus == AwaitingResponse)
              , HE.onClick (SetTrusted False)
              , HA.class "btn btn-sm btn-outline-primary mx-1"
              ] [H.text "mark this user untrusted"]
            , case model.setTrustedRequestStatus of
                Unstarted -> H.text ""
                AwaitingResponse -> H.text ""
                Succeeded -> Utils.greenText " Success!"
                Failed e -> Utils.redText e
            ]
            , H.br [] []
            , if Globals.getRelationship model.globals model.who |> Maybe.map .trustsYou |> Maybe.withDefault False then
                H.div []
                  [ H.h3 [] [H.text "Predictions"]
                  , ViewPredictionsWidget.view
                      { setState = SetPredictionsWidget
                      , predictions = Dict.filter (\_ pred -> pred.creator == model.who) model.globals.serverState.predictions
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
  ]}

subscriptions : Model -> Sub Msg
subscriptions _ = authWidgetExternallyChanged AuthWidgetExternallyModified

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
