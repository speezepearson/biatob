module Elements.Welcome exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Json.Decode as JD
import Http
import Dict exposing (Dict)
import Time
import Task

import Biatob.Proto.Mvp as Pb
import Utils

import Widgets.AuthWidget as AuthWidget
import Widgets.Navbar as Navbar
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Widgets.EmailSettingsWidget as EmailSettingsWidget
import Widgets.CopyWidget as CopyWidget
import Page

type alias Model =
  { navbar : Navbar.Model
  , authWidget : AuthWidget.Model
  , invitationWidget : SmallInvitationWidget.Model
  , emailSettingsWidget : EmailSettingsWidget.Model
  }

type Msg
  = NavbarMsg Navbar.Msg
  | AuthWidgetMsg AuthWidget.Msg
  | InvitationMsg SmallInvitationWidget.Msg
  | EmailSettingsMsg EmailSettingsWidget.Msg

pagedef : Page.Element Model Msg
pagedef =
  { init = init
  , view = view
  , update = update
  , subscriptions = \_ -> Sub.none
  }

init : JD.Value -> (Model, Page.Command Msg)
init _ =
  ( { navbar = Navbar.init
    , authWidget = AuthWidget.init
    , invitationWidget = SmallInvitationWidget.init Nothing
    , emailSettingsWidget = EmailSettingsWidget.init
    }
  , Page.NoCmd
  )


update : Msg -> Model -> (Model, Page.Command Msg)
update msg model =
  case msg of
    NavbarMsg widgetMsg ->
      let (newWidget, innerCmd) = Navbar.update widgetMsg model.navbar in
      ( { model | navbar = newWidget } , Page.mapCmd NavbarMsg innerCmd )
    AuthWidgetMsg widgetMsg ->
      let (newWidget, innerCmd) = AuthWidget.update widgetMsg model.authWidget in
      ( { model | authWidget = newWidget } , Page.mapCmd AuthWidgetMsg innerCmd )
    EmailSettingsMsg widgetMsg ->
      let (newWidget, innerCmd) = EmailSettingsWidget.update widgetMsg model.emailSettingsWidget in
      ( { model | emailSettingsWidget = newWidget } , Page.mapCmd EmailSettingsMsg innerCmd )
    InvitationMsg widgetMsg ->
      let (newWidget, innerCmd) = SmallInvitationWidget.update widgetMsg model.invitationWidget in
      ( { model | invitationWidget = newWidget } , Page.mapCmd InvitationMsg innerCmd )


view : Page.Globals -> Model -> Browser.Document Msg
view globals model =
  { title = "Welcome to Biatob!"
  , body = [
    Navbar.view globals model.navbar |> H.map NavbarMsg
   ,H.main_ [HA.id "main", HA.style "text-align" "justify"]
    [ H.h1 [] [H.text "Betting is a tax on BS."]
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
    , H.h2 [] [ H.text "But what does it " , Utils.i "do?" ]
    , H.p []
        [ H.text "Biatob provides a place for you to advertise things like this to your friends: "
        , H.blockquote []
            [ H.text "  Hey, I think that X has at least a 2/3 chance of happening!   If you think I'm overconfident, let's bet: I'll pay you $20 if I'm wrong, against your $10 if I'm right. "
            ]
        , H.text "Then, you publish a link to that page, and any of your friends can take you up on that bet. Biatob handles the bookkeeping, emails you (if you want) to make sure you remember to resolve the prediction when the answer becomes clear, and calculates and informs everybody of their net winnings."
        ]
    , H.p []
        [ H.text "Note that last bit: \""
        , Utils.i "informs everybody of"
        , H.text " their net winnings.\""
        , Utils.b " Everything is purely honor-system."
        , H.text " Biatob doesn't touch money, it relies on you to settle up on your own. While a significant restriction in some ways (you can only bet against people who trust you to pay your debts) this also makes things "
        , Utils.i "much"
        , H.text " simpler: you don't need to give me your credit card number, you don't need to pay any fees, I don't need to worry about being charged with running an illegal gambling operation -- everybody wins!"
        ]
    , H.p []
        [ H.text "If you want thickly traded markets with thousands of participants, try "
        , H.a [HA.href "https://www.predictit.org/"]
            [ H.text "PredictIt"
            ]
        , H.text " or "
        , H.a [HA.href "https://www.metaculus.com/"]
            [ H.text "Metaculus"
            ]
        , H.text ". This is a different beast."
        ]
    , H.hr [] []
    , H.h2 []
        [ H.text "Cool! How do I use it?"
        ]
    , H.ul []
        [ H.li [HA.style "margin-bottom" "1em"]
            [ H.text " Create an account:   "
            , H.div [HA.id "welcome-page-auth-widget"]
                [ AuthWidget.view globals model.authWidget |> H.map AuthWidgetMsg ]
            ]
        , H.li [HA.style "margin-bottom" "1em"]
            [ H.a [HA.name "postcreateaccount"] []
            , H.text " Go to "
            , H.a [HA.href "/new"]
                [ H.text "the New Prediction page"
                ]
            , H.text " to create a bet. "
            ]
        , H.li [HA.style "margin-bottom" "1em"]
            [ H.text " Advertise your bet -- post the link on Facebook, include a cute little embeddable image in your blog, whatever. "
            ]
        , H.li [HA.style "margin-bottom" "1em"]
            [ H.text " Send your friends invitation links so I know who you trust to bet against you:   "
            , H.div [HA.style "border" "1px solid gray", HA.style "padding" "0.5em", HA.style "margin" "0.5em"]
                [ if Page.isLoggedIn globals then
                    SmallInvitationWidget.view globals model.invitationWidget |> H.map InvitationMsg
                  else
                    H.text "(first, log in)"
                ]
            ]
        , H.li [HA.style "margin-bottom" "1em"]
            [ H.text " Consider adding an email address, so I can remind you to resolve your prediction when the time comes:   "
            , H.div [HA.style "border" "1px solid gray", HA.style "padding" "0.5em", HA.style "margin" "0.5em"]
                [ case Page.getUserInfo globals of
                    Nothing -> H.text "(first, log in)"
                    Just userInfo ->
                      EmailSettingsWidget.view globals model.emailSettingsWidget |> H.map EmailSettingsMsg
                ]
            ]
        , H.li [HA.style "margin-bottom" "1em"]
            [ H.text " When your prediction resolves to Yes or No, settle up with your friends! "
            ]
        ]
    ]
  ]}

main = Page.page pagedef
