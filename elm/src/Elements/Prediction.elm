port module Elements.Prediction exposing (main)

import Browser
import Dict
import Html as H exposing (Html)
import Html.Attributes as HA
import Json.Decode as JD
import Http

import Utils

import Widgets.CopyWidget as CopyWidget
import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Widgets.PredictionWidget as PredictionWidget
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Globals
import API
import Biatob.Proto.Mvp as Pb
import Utils exposing (PredictionId)
import Time

port copy : String -> Cmd msg
port navigate : Maybe String -> Cmd msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , predictionId : PredictionId
  , predictionWidget : PredictionWidget.State
  , invitationWidget : SmallInvitationWidget.State
  }

type Msg
  = SetAuthWidget AuthWidget.State
  | SetInvitationWidget SmallInvitationWidget.State
  | SetPredictionWidget PredictionWidget.State
  | CreateInvitation SmallInvitationWidget.State Pb.CreateInvitationRequest
  | CreateInvitationFinished Pb.CreateInvitationRequest (Result Http.Error Pb.CreateInvitationResponse)
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | Resolve PredictionWidget.State Pb.ResolveRequest
  | ResolveFinished Pb.ResolveRequest (Result Http.Error Pb.ResolveResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | Stake PredictionWidget.State Pb.StakeRequest
  | StakeFinished Pb.StakeRequest (Result Http.Error Pb.StakeResponse)
  | Copy String
  | Tick Time.Posix
  | Ignore

init : JD.Value -> ( Model, Cmd Msg )
init flags =
  ( { globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
    , navbarAuth = AuthWidget.init
    , predictionId = Utils.mustDecodeFromFlags JD.int "predictionId" flags
    , predictionWidget = PredictionWidget.init
    , invitationWidget = SmallInvitationWidget.init
    }
  , Cmd.none
  )

view : Model -> Browser.Document Msg
view model =
  let prediction = Utils.must "must have loaded prediction being viewed" <| Dict.get model.predictionId model.globals.serverState.predictions in
  { title = "My stakes"
  , body =
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
      [ H.h2 [] [H.text "My Stakes"]
      , PredictionWidget.view
          { setState = SetPredictionWidget
          , copy = Copy
          , stake = Stake
          , resolve = Resolve
          , invitationWidget = viewInvitationWidget model
          , linkTitle = False
          , disableCommit = True
          , predictionId = model.predictionId
          , prediction = prediction
          , httpOrigin = model.globals.httpOrigin
          , creatorRelationship = Globals.getTrustRelationship model.globals prediction.creator
          , timeZone = model.globals.timeZone
          , now = model.globals.now
          }
          model.predictionWidget
    , if not (Globals.isLoggedIn model.globals) then
        viewWhatIsThis prediction
      else if Globals.isSelf model.globals prediction.creator then
        H.div []
          [ H.text "If you want to link to your prediction, here are some snippets of HTML you could copy-paste:"
          , viewEmbedInfo model
          , H.text "If there are people you want to participate, but you haven't already established trust with them in Biatob, send them invitations: "
          , viewInvitationWidget model
          ]
      else
        H.text ""
      ]
    ]
  }

viewInvitationWidget : Model -> Html Msg
viewInvitationWidget model =
  SmallInvitationWidget.view
    { setState = SetInvitationWidget
    , createInvitation = CreateInvitation
    , copy = Copy
    , destination = Just <| Utils.pathToPrediction model.predictionId
    , httpOrigin = model.globals.httpOrigin
    }
    model.invitationWidget
viewEmbedInfo : Model -> Html Msg
viewEmbedInfo model =
  let
    prediction = Utils.must "must have loaded prediction being viewed" <| Dict.get model.predictionId model.globals.serverState.predictions
    linkUrl = model.globals.httpOrigin ++ Utils.pathToPrediction model.predictionId  -- TODO(P0): needs origin to get stuck in text field
    imgUrl = model.globals.httpOrigin ++ Utils.pathToPrediction model.predictionId ++ "/embed.png"
    imgStyles = [("max-height","1.5ex"), ("border-bottom","1px solid #008800")]
    imgCode =
      "<a href=\"" ++ linkUrl ++ "\">"
      ++ "<img style=\"" ++ (imgStyles |> List.map (\(k,v) -> k++":"++v) |> String.join ";") ++ "\" src=\"" ++ imgUrl ++ "\" /></a>"
    linkText =
      "["
      ++ Utils.formatCents (prediction.maximumStakeCents // 100 * 100)
      ++ " @ "
      ++ String.fromInt (round <| (Utils.mustPredictionCertainty prediction).low * 100)
      ++ "-"
      ++ String.fromInt (round <| (Utils.mustPredictionCertainty prediction).high * 100)
      ++ "%]"
    linkCode =
      "<a href=\"" ++ linkUrl ++ "\">" ++ linkText ++ "</a>"
  in
    H.ul []
      [ H.li [] <|
        [ H.text "A linked inline image: "
        , CopyWidget.view Copy imgCode
        , H.br [] []
        , H.text "This would render as: "
        , H.a [HA.href linkUrl]
          [ H.img (HA.src imgUrl :: (imgStyles |> List.map (\(k,v) -> HA.style k v))) []]
        ]
      , H.li [] <|
        [ H.text "A boring old link: "
        , CopyWidget.view Copy linkCode
        , H.br [] []
        , H.text "This would render as: "
        , H.a [HA.href linkUrl] [H.text linkText]
        ]
      ]

viewWhatIsThis : Pb.UserPredictionView -> Html msg
viewWhatIsThis prediction =
  H.div []
  [ H.hr [HA.style "margin" "4em 0"] []
  , H.h3 [] [H.text "Huh? What is this?"]
  , H.p []
      [ H.text "This site is a tool that helps people make friendly wagers, thereby clarifying and concretizing their beliefs and making the world a better, saner place."
      ]
  , H.p []
      [ Utils.renderUser prediction.creator
      , H.text <| " is putting their money where their mouth is: they've staked " ++ Utils.formatCents prediction.maximumStakeCents ++ " of real-life money on this prediction,"
          ++ " and they're willing to bet at the above odds against anybody they trust. Good for them!"
      ]
  , H.p []
      [ H.text "If you know and trust ", Utils.renderUser prediction.creator
      , H.text <| ", and they know and trust you, and you want to bet against them on this prediction,"
          ++ " then message them however you normally do, and ask them for an invitation to this market!"
      ]
  , H.hr [] []
  , H.h3 [] [H.text "But... why would you do this?"]
  , H.p []
      [ H.text "Personally, when I force myself to make concrete predictions -- especially on topics I feel strongly about -- it frequently turns out that "
      , Utils.i "I don't actually believe what I thought I did."
      , H.text " Crazy, right!? Brains suck! And betting, i.e. attaching money to my predictions, is "
      , H.a [HA.href "https://marginalrevolution.com/marginalrevolution/2012/11/a-bet-is-a-tax-on-bullshit.html"]
          [ H.text "an incentive to actually try to get them right"
          ]
      , H.text ": it forces my brain to cut through (some of) the layers of "
      , H.a [HA.href "https://en.wikipedia.org/wiki/Social-desirability_bias"]
          [ H.text "social-desirability bias"
          ]
      , H.text " and "
      , H.a [HA.href "https://www.lesswrong.com/posts/DSnamjnW7Ad8vEEKd/trivers-on-self-deception"]
          [ H.text "Triversian self-deception"
          ]
      , H.text " to lay bare "
      , H.a [HA.href "https://www.lesswrong.com/posts/a7n8GdKiAZRX86T5A/making-beliefs-pay-rent-in-anticipated-experiences"]
          [ H.text "my actual beliefs about what I expect to see"
          ]
      , H.text "."
      ]
  , H.p [] [H.text "I made this tool to share that joy with you."]
  ]

update : Msg -> Model -> ( Model , Cmd Msg )
update msg model =
  case msg of
    SetAuthWidget widgetState ->
      ( { model | navbarAuth = widgetState } , Cmd.none )
    SetInvitationWidget widgetState ->
      ( { model | invitationWidget = widgetState } , Cmd.none )
    SetPredictionWidget widgetState ->
      ( { model | predictionWidget = widgetState } , Cmd.none )
    CreateInvitation widgetState req ->
      ( { model | invitationWidget = widgetState }
      , API.postCreateInvitation (CreateInvitationFinished req) req
      )
    CreateInvitationFinished req res ->
      ( { model | globals = model.globals |> Globals.handleCreateInvitationResponse req res , invitationWidget = model.invitationWidget |> SmallInvitationWidget.handleCreateInvitationResponse res }
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
    Resolve widgetState req ->
      ( { model | predictionWidget = widgetState }
      , API.postResolve (ResolveFinished req) req
      )
    ResolveFinished req res ->
      ( { model | globals = model.globals |> Globals.handleResolveResponse req res
                , predictionWidget = model.predictionWidget |> PredictionWidget.handleResolveResponse res
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
      , navigate <| Just "/"
      )
    Stake widgetState req ->
      ( { model | predictionWidget = widgetState }
      , API.postStake (StakeFinished req) req
      )
    StakeFinished req res ->
      ( { model | globals = model.globals |> Globals.handleStakeResponse req res
                , predictionWidget = model.predictionWidget |> PredictionWidget.handleStakeResponse res
        }
      , Cmd.none
      )
    Copy s ->
      ( model
      , copy s
      )
    Tick now ->
      ( { model | globals = model.globals |> Globals.tick now }
      , Cmd.none
      )
    Ignore ->
      ( model , Cmd.none )

subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
