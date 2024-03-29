port module Elements.Welcome exposing (main)

import Browser
import Html as H
import Html.Attributes as HA
import Json.Decode as JD
import Http
import Time

import Utils

import Widgets.AuthWidget as AuthWidget
import Globals
import API
import Widgets.Navbar as Navbar
import Biatob.Proto.Mvp as Pb

port copy : String -> Cmd msg
port navigate : Maybe String -> Cmd msg
port authWidgetExternallyChanged : (AuthWidget.DomModification -> msg) -> Sub msg

type alias Model =
  { globals : Globals.Globals
  , navbarAuth : AuthWidget.State
  , authWidget : AuthWidget.State
  }

type AuthWidgetLoc = Navbar | Inline
type Msg
  = SetAuthWidget AuthWidgetLoc AuthWidget.State
  | LogInUsername AuthWidgetLoc AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished AuthWidgetLoc Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | SignOut AuthWidgetLoc AuthWidget.State Pb.SignOutRequest
  | SignOutFinished AuthWidgetLoc Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | Copy String
  | Tick Time.Posix
  | AuthWidgetExternallyModified AuthWidget.DomModification
  | Ignore

init : JD.Value -> (Model, Cmd Msg)
init flags =
  ( { globals = JD.decodeValue Globals.globalsDecoder flags |> Utils.mustResult "flags"
    , navbarAuth = AuthWidget.init
    , authWidget = AuthWidget.init
    }
  , Cmd.none
  )

updateAuthWidget : AuthWidgetLoc -> (AuthWidget.State -> AuthWidget.State) -> Model -> Model
updateAuthWidget loc f model =
  case loc of
    Navbar -> { model | navbarAuth = model.navbarAuth |> f }
    Inline -> { model | authWidget = model.authWidget |> f }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetAuthWidget loc widgetState ->
      ( updateAuthWidget loc (always widgetState) model , Cmd.none )
    LogInUsername loc widgetState req ->
      ( updateAuthWidget loc (always widgetState) model
      , API.postLogInUsername (LogInUsernameFinished loc req) req
      )
    LogInUsernameFinished loc req res ->
      ( updateAuthWidget loc (AuthWidget.handleLogInUsernameResponse res) { model | globals = model.globals |> Globals.handleLogInUsernameResponse req res }
      , case API.simplifyLogInUsernameResponse res of
          Ok _ -> navigate <| if loc == Inline then Just "/welcome#welcome-page-auth-widget" else Nothing
          Err _ -> Cmd.none
      )
    SignOut loc widgetState req ->
      ( updateAuthWidget loc (always widgetState) model
      , API.postSignOut (SignOutFinished loc req) req
      )
    SignOutFinished loc req res ->
      ( updateAuthWidget loc (AuthWidget.handleSignOutResponse res) { model | globals = model.globals |> Globals.handleSignOutResponse req res }
      , case API.simplifySignOutResponse res of
          Ok _ -> navigate <| Just "/"
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
      ( updateAuthWidget
          (case mod.authWidgetId of
             "navbar-auth" -> Navbar
             "inline-auth" -> Inline
             _ -> Debug.todo "unknown auth widget id"
          )
          (AuthWidget.handleDomModification mod)
          model
      , Cmd.none
      )
    Ignore ->
      ( model , Cmd.none )


view : Model -> Browser.Document Msg
view model =
  { title = "Welcome to Biatob!"
  , body = [
    Navbar.view
        { setState = SetAuthWidget Navbar
        , logInUsername = LogInUsername Navbar
        , signOut = SignOut Navbar
        , ignore = Ignore
        , username = Globals.getOwnUsername model.globals
        , id = "navbar-auth"
        }
        model.navbarAuth
    ,
    H.main_ [HA.class "container", HA.style "text-align" "justify"]
    [ H.h1 [HA.class "text-center my-5"] [H.text "Betting is a tax on BS."]
    , H.p []
        [ H.text "Hi! This is a tool that helps people make friendly wagers, thereby clarifying and concretizing their beliefs and making the world a better, saner place."
        ]
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
    , H.hr [] []
    , H.h2 [HA.class "text-center"] [ H.text "But what does it " , Utils.i "do?" ]
    , H.p []
        [ H.text "Biatob provides a place for you to advertise things like this to your friends: "
        , H.p [HA.class "mt-2 mb-2 mx-4"]
            [ Utils.i "  Hey, I think that X is pretty likely! If you disagree, let's bet: I'll pay you $20 if I'm wrong, against your mere $10 if I'm right. "
            ]
        , H.text "Then, you publish a link to that page, and any of your friends can take you up on that bet. Biatob handles the bookkeeping, emails you (if you want) to make sure you remember to resolve the prediction when the answer becomes clear, and calculates and informs everybody of their net winnings so that they can settle up."
        ]
    , H.p []
        [ H.text "Note that last bit: "
        , Utils.b " everything is purely honor-system."
        , H.text " Biatob doesn't touch money, it relies on you to settle up on your own. While a significant restriction in some ways (you can only bet against people whom you trust to pay their debts) this also makes things "
        , Utils.i "much"
        , H.text " simpler: you don't need to give me your credit card number, you don't need to pay any fees, I don't need to worry about being charged with running an illegal gambling operation -- everybody wins!"
        ]
    , H.p []
        [ H.text "If you want thickly traded markets with thousands of participants, try "
        , H.a [HA.href "https://www.predictit.org/"]
            [ H.text "PredictIt"
            ]
        , H.text " or "
        , H.a [HA.href "https://www.betfair.com/"]
            [ H.text "Betfair"
            ]
        , H.text ". This is a different beast."
        ]
    , H.hr [] []
    , H.h2 [HA.class "text-center"]
        [ H.text "Cool! How do I use it?"
        ]
    , H.ul []
        [ H.li [HA.style "margin-bottom" "1em"]
            [ H.a [HA.href "/signup"] [H.text "Create an account!"]
            ]
        , H.li [HA.style "margin-bottom" "1em"]
            [ H.text " Go to "
            , H.a [HA.href "/new"]
                [ H.text "the New Prediction page"
                ]
            , H.text " to create a bet. "
            ]
        , H.li [HA.style "margin-bottom" "1em"]
            [ H.text " Advertise your bet -- post the link on Facebook, include a cute little embeddable image in your blog, whatever."
            , H.text " (The prediction page will show you how.)"
            ]
        , H.li [HA.style "margin-bottom" "1em"]
            [ H.text " When your prediction resolves to Yes or No, settle up with your friends! "
            ]
        ]
    ]
  ]}

subscriptions : Model -> Sub Msg
subscriptions _ = authWidgetExternallyChanged AuthWidgetExternallyModified

main = Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}
