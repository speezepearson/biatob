module Elements.Welcome exposing (main)

import Browser
import Html as H
import Html.Attributes as HA
import Json.Decode as JD
import Http

import Utils

import Widgets.AuthWidget as AuthWidget
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Widgets.EmailSettingsWidget as EmailSettingsWidget
import Page
import Page.Program
import Biatob.Proto.Mvp as Pb

type alias Model =
  { authWidget : AuthWidget.State
  , invitationWidget : SmallInvitationWidget.State
  , emailSettingsWidget : EmailSettingsWidget.State
  }

type Msg
  = SetEmailWidget EmailSettingsWidget.State
  | UpdateSettings EmailSettingsWidget.State Pb.UpdateSettingsRequest
  | UpdateSettingsFinished (Result Http.Error Pb.UpdateSettingsResponse)
  | SetEmail EmailSettingsWidget.State Pb.SetEmailRequest
  | SetEmailFinished (Result Http.Error Pb.SetEmailResponse)
  | VerifyEmail EmailSettingsWidget.State Pb.VerifyEmailRequest
  | VerifyEmailFinished (Result Http.Error Pb.VerifyEmailResponse)
  | SetAuthWidget AuthWidget.State
  | LogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | LogInUsernameFinished (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | RegisterUsernameFinished (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut AuthWidget.State Pb.SignOutRequest
  | SignOutFinished (Result Http.Error Pb.SignOutResponse)
  | SetInvitationWidget SmallInvitationWidget.State
  | CreateInvitation SmallInvitationWidget.State Pb.CreateInvitationRequest
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)
  | Copy String
  | Ignore

pagedef : Page.Element Model Msg
pagedef =
  { init = init
  , view = view
  , update = update
  , subscriptions = subscriptions
  }

init : JD.Value -> (Model, Page.Command Msg)
init _ =
  ( { authWidget = AuthWidget.init
    , invitationWidget = SmallInvitationWidget.init
    , emailSettingsWidget = EmailSettingsWidget.init
    }
  , Page.NoCmd
  )


update : Msg -> Model -> (Model, Page.Command Msg)
update msg model =
  case msg of
    SetEmailWidget widgetState ->
      ( { model | emailSettingsWidget = widgetState } , Page.NoCmd )
    UpdateSettings widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , Page.RequestCmd <| Page.UpdateSettingsRequest UpdateSettingsFinished req
      )
    UpdateSettingsFinished res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleUpdateSettingsResponse res }
      , Page.NoCmd
      )
    SetEmail widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , Page.RequestCmd <| Page.SetEmailRequest SetEmailFinished req
      )
    SetEmailFinished res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleSetEmailResponse res }
      , Page.NoCmd
      )
    VerifyEmail widgetState req ->
      ( { model | emailSettingsWidget = widgetState }
      , Page.RequestCmd <| Page.VerifyEmailRequest VerifyEmailFinished req
      )
    VerifyEmailFinished res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleVerifyEmailResponse res }
      , Page.NoCmd
      )
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
    SetInvitationWidget widgetState ->
      ( { model | invitationWidget = widgetState } , Page.NoCmd )
    CreateInvitation widgetState req ->
      ( { model | invitationWidget = widgetState }
      , Page.RequestCmd <| Page.CreateInvitationRequest CreateInvitationFinished req
      )
    CreateInvitationFinished res ->
      ( { model | invitationWidget = model.invitationWidget |> SmallInvitationWidget.handleCreateInvitationResponse res }
      , Page.NoCmd
      )
    Copy s ->
      ( model
      , Page.CopyCmd s
      )
    Ignore ->
      ( model , Page.NoCmd )


view : Page.Globals -> Model -> Browser.Document Msg
view globals model =
  { title = "Welcome to Biatob!"
  , body = [
    H.main_ [HA.style "text-align" "justify"]
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
                [ AuthWidget.view
                  { setState = SetAuthWidget
                  , logInUsername = LogInUsername
                  , register = RegisterUsername
                  , signOut = SignOut
                  , ignore = Ignore
                  , auth = Page.getAuth globals
                  }
                  model.authWidget
                ]
            ]
        , H.li [HA.style "margin-bottom" "1em"]
            [ H.text " Go to "
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
                    SmallInvitationWidget.view
                      { setState = SetInvitationWidget
                      , createInvitation = CreateInvitation
                      , copy = Copy
                      , destination = Nothing
                      , httpOrigin = globals.httpOrigin
                      }
                      model.invitationWidget
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
                      EmailSettingsWidget.view
                        { setState = SetEmailWidget
                        , ignore = Ignore
                        , setEmail = SetEmail
                        , verifyEmail = VerifyEmail
                        , updateSettings = UpdateSettings
                        , userInfo = userInfo
                        }
                        model.emailSettingsWidget
                ]
            ]
        , H.li [HA.style "margin-bottom" "1em"]
            [ H.text " When your prediction resolves to Yes or No, settle up with your friends! "
            ]
        ]
    ]
  ]}

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main = Page.Program.page pagedef
