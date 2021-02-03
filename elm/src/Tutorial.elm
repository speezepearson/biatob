module Tutorial exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE

import Biatob.Proto.Mvp as Pb

type alias Config msg =
  { setState : State -> msg
  , onSignUp : {email:String, password:String} -> msg
  , onHideTutorial : msg
  , creator : Pb.UserUserView
  }

type alias State =
  { emailField : String
  , passwordField : String
  }



view : Config msg -> State -> Html msg
view config state =
  H.div [HA.style "margin" "2em", HA.style "border" "1px solid black", HA.style "padding" "1em"]
    [ H.p []
        [ H.text "Hi, newcomer! Confused? Curious?  This is a site that helps people make friendly wagers! "
        , H.span [HA.style "opacity" "0.5"]
            [ H.text "(\"Why?\" To promote epistemic virtue and thereby make the world a better, saner place! When I force myself to make concrete predictions about important things, it frequently turns out that I don't actually believe what I thought I did. (Crazy, right!? Brains <i>suck!</i>) And betting, i.e. attaching money to my predictions, is "
            , H.a [HA.href "https://marginalrevolution.com/marginalrevolution/2012/11/a-bet-is-a-tax-on-bullshit.html"]
                [H.text "just an extra incentive to get them right"]
            , H.text ".)"
            ]
        ]
    , H.p []
        [ H.text <|
            config.creator.displayName
            ++ " is willing to put their money where their mouth is."
            ++ " Good for them!"
            ++ " And, if you think they're wrong, you can earn money and set them straight at the same time!"
        ]
    , H.details []
        [ H.summary [] [H.strong [] [H.text "\"Cool! How do I accept this bet?\""]]
        , H.p []
            [ H.text "First off, let's be clear: this is not a \"real\" prediction market site like PredictIt or Betfair. Everything here works on the honor system. A bet can only be made between "
            , H.i [] [H.text "people who trust each other in real life."]
            , H.text <|
                " So, ask yourself, do you trust "
                ++ config.creator.displayName
                ++ " to pay their debts? And do they trust you? If either answer is no, you're out of luck: the honor system only works where there's honor."
            ]
        , H.p [] [H.text "But! If you do trust each other, the flow goes like this:"]
        , H.ul []
            [ H.li []
                [ H.input [HA.type_ "email", HA.placeholder "email@ddre.ss", HA.value state.emailField, HE.onInput (\s -> config.setState {state | emailField = s})] []
                , H.input [HA.type_ "password", HA.placeholder "password", HA.value state.passwordField, HE.onInput (\s -> config.setState {state | passwordField = s})] []
                , H.button [HE.onClick <| config.onSignUp {email=state.emailField, password=state.passwordField}] [H.text "Sign up"]
                ]
            , H.li []
                [ H.text "Send "
                , H.a [HA.href "http://example.com/TODO"] [H.text "your user-page link"]
                , H.text <| " to " ++ config.creator.displayName ++ " so they can mark you as trusted. Ask them for theirs, in turn."
                ]
            , H.li [] [H.text <| "Wager against them, below!"]
            ]
        , H.p [] [H.text "When the bet resolves, you'll both get an email telling you who owes who how much. You can enter that into Venmo or Splitwise or whatever."]
        , H.p [] [H.button [HE.onClick config.onHideTutorial] [H.text "Hide this tutorial."]]
        ]
    , H.details []
        [ H.summary [] [H.strong [] [H.text "\"I ", H.i [] [H.text "really"], H.text " don't like this idea.\""]]
        , H.text "Sorry! I know some people are averse to this sort of thing. If you click "
        , H.button [] [H.text "Hide embeds"]
        , H.text ", I'll try to not show you any more links to people's wagers (insofar as I can -- it's hard to control what appears on other people's sites)."
        ]
    ]

initStateForDemo : State
initStateForDemo =
  { emailField = ""
  , passwordField = ""
  }

type MsgForDemo = SetState State | Ignore
main : Program () State MsgForDemo
main =
  Browser.sandbox
    { init = initStateForDemo
    , view = view {setState=SetState, onSignUp=always Ignore, onHideTutorial=Ignore, creator={displayName="Spencer", isSelf=False, isTrusted=True, trustsYou=True}}
    , update = \msg model -> case msg of
        Ignore -> model
        SetState newState -> newState
    }
