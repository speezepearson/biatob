port module Elements.Welcome exposing (main)

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
import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Widgets.EmailSettingsWidget as EmailSettingsWidget
import Widgets.CopyWidget as CopyWidget
import API

port authChanged : () -> Cmd msg

type AuthState = LoggedOut | LoggedIn Pb.AuthToken Pb.GenericUserInfo
getAuth : AuthState -> Maybe Pb.AuthToken
getAuth authState = case authState of
  LoggedOut -> Nothing
  LoggedIn auth _ -> Just auth
type alias Model =
  { authState : AuthState
  , authWidget : AuthWidget.State
  , invitationWidget : SmallInvitationWidget.State
  , emailSettingsWidget : EmailSettingsWidget.State
  , httpOrigin : String
  , now : Time.Posix
  }

updateUserInfo : (Pb.GenericUserInfo -> Pb.GenericUserInfo) -> Model -> Model
updateUserInfo f model =
  case model.authState of
    LoggedOut -> model
    LoggedIn auth info -> { model | authState = LoggedIn auth (f info) }

type Msg
  = AuthEvent (Maybe AuthWidget.Event) AuthWidget.State
  | InvitationEvent (Maybe SmallInvitationWidget.Event) SmallInvitationWidget.State
  | EmailSettingsEvent (Maybe EmailSettingsWidget.Event) EmailSettingsWidget.State
  | LogInUsernameFinished (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsernameFinished (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOutFinished (Result Http.Error Pb.SignOutResponse)
  | SetEmailFinished (Result Http.Error Pb.SetEmailResponse)
  | VerifyEmailFinished (Result Http.Error Pb.VerifyEmailResponse)
  | UpdateSettingsFinished (Result Http.Error Pb.UpdateSettingsResponse)
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)
  | Copy String
  | Tick Time.Posix

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    userInfo = Utils.decodePbFromFlags Pb.genericUserInfoDecoder "userInfoPbB64" flags
    httpOrigin = Utils.mustDecodeFromFlags JD.string "httpOrigin" flags
  in
  ( { authState = case (auth, userInfo) of
        (Nothing, Nothing) -> LoggedOut
        (Just auth_, Just userInfo_) -> LoggedIn auth_ userInfo_
        _ -> Debug.todo "bad data from server; auth and userInfo should be both present or both absent"
    , authWidget = AuthWidget.init
    , invitationWidget = SmallInvitationWidget.init
    , emailSettingsWidget = EmailSettingsWidget.init
    , httpOrigin = httpOrigin
    , now = Utils.unixtimeToTime 0
    }
  , Task.perform Tick Time.now
  )

authHandler : AuthWidget.Handler Model
authHandler =
  { updateWidget = \f m -> { m | authWidget = m.authWidget |> f }
  , setAuth = \a m -> m -- TODO: I don't like this implicit reliance on reloading the page when this happens
  }

emailSettingsHandler : EmailSettingsWidget.Handler Model
emailSettingsHandler =
  { updateWidget = \f m -> { m | emailSettingsWidget = m.emailSettingsWidget |> f }
  , setEmailFlowState = \e m -> m |> updateUserInfo (\u -> { u | email = Just e })
  }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    AuthEvent event newState ->
      (case event of
        Just (AuthWidget.LogInUsername req) -> ( model , API.postLogInUsername LogInUsernameFinished req )
        Just (AuthWidget.RegisterUsername req) -> ( model , API.postRegisterUsername RegisterUsernameFinished req )
        Just (AuthWidget.SignOut req) -> ( model , API.postSignOut SignOutFinished req )
        Nothing -> ( model , Cmd.none )
      ) |> Tuple.mapFirst (\m -> { m | authWidget = newState })
    InvitationEvent event newState ->
      (case event of
        Just SmallInvitationWidget.CreateInvitation -> ( model , API.postCreateInvitation CreateInvitationFinished {notes=""} )
        Just (SmallInvitationWidget.Copy s) -> ( model , CopyWidget.copy s )
        Nothing -> ( model , Cmd.none )
      ) |> Tuple.mapFirst (\m -> { m | invitationWidget = newState })
    EmailSettingsEvent event newState ->
      (case event of
        Just (EmailSettingsWidget.SetEmail req) -> ( model , API.postSetEmail SetEmailFinished req )
        Just (EmailSettingsWidget.VerifyEmail req) -> ( model , API.postVerifyEmail VerifyEmailFinished req )
        Just (EmailSettingsWidget.UpdateSettings req) -> ( model , API.postUpdateSettings UpdateSettingsFinished req )
        Just EmailSettingsWidget.Ignore -> ( model , Cmd.none )
        Nothing -> ( model , Cmd.none )
      ) |> Tuple.mapFirst (\m -> { m | emailSettingsWidget = newState })

    LogInUsernameFinished res ->
      ( AuthWidget.handleLogInUsernameResponse authHandler res model
      , if AuthWidget.isSuccessfulLogInUsername res then authChanged () else Cmd.none
      )
    RegisterUsernameFinished res ->
      ( AuthWidget.handleRegisterUsernameResponse authHandler res model
      , if AuthWidget.isSuccessfulRegisterUsername res then authChanged () else Cmd.none
      )
    SignOutFinished res ->
      ( AuthWidget.handleSignOutResponse authHandler res model
      , if AuthWidget.isSuccessfulSignOut res then authChanged () else Cmd.none
      )


    SetEmailFinished res ->
      ( EmailSettingsWidget.handleSetEmailResponse emailSettingsHandler res model
      , Cmd.none
      )

    VerifyEmailFinished res ->
      ( EmailSettingsWidget.handleVerifyEmailResponse emailSettingsHandler res model
      , Cmd.none
      )
    UpdateSettingsFinished res ->
      ( { model | emailSettingsWidget = model.emailSettingsWidget |> EmailSettingsWidget.handleUpdateSettingsResponse res }
        |> updateUserInfo (\userInfo ->
            case res |> Result.toMaybe |> Maybe.andThen .updateSettingsResult of
              Just (Pb.UpdateSettingsResultOk newInfo) -> newInfo
              _ -> userInfo
              )
      , Cmd.none
      )

    CreateInvitationFinished res ->
      ( { model | invitationWidget = model.invitationWidget |> SmallInvitationWidget.handleCreateInvitationResponse res }
        |> updateUserInfo (\userInfo ->
            case res |> Result.toMaybe |> Maybe.andThen .createInvitationResult of
              Just (Pb.CreateInvitationResultOk result) -> userInfo |> \u -> { u | invitations = u.invitations |> Dict.insert (result.id |> Utils.must "" |> .nonce) result.invitation }
              _ -> userInfo
              )
      , Cmd.none
      )

    Copy s -> ( model , CopyWidget.copy s )
    Tick now -> ( { model | now = now } , Cmd.none )


view : Model -> Html Msg
view model =
  H.main_ [HA.id "main", HA.style "text-align" "justify"]
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
                    { auth = getAuth model.authState
                    , now = model.now
                    , handle = AuthEvent
                    }
                    model.authWidget
                ]
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
                [ case model.authState of
                    LoggedOut -> H.text "(first, log in)"
                    LoggedIn _ _ ->
                      SmallInvitationWidget.view
                        { httpOrigin = model.httpOrigin
                        , destination = Nothing
                        , handle = InvitationEvent
                        }
                      model.invitationWidget
                ]
            ]
        , H.li [HA.style "margin-bottom" "1em"]
            [ H.text " Consider adding an email address, so I can remind you to resolve your prediction when the time comes:   "
            , H.div [HA.style "border" "1px solid gray", HA.style "padding" "0.5em", HA.style "margin" "0.5em"]
                [ case model.authState of
                    LoggedOut -> H.text "(first, log in)"
                    LoggedIn _ userInfo ->
                      EmailSettingsWidget.view
                        { emailFlowState = userInfo |> Utils.mustUserInfoEmail
                        , emailRemindersToResolve = userInfo.emailRemindersToResolve
                        , emailResolutionNotifications = userInfo.emailResolutionNotifications
                        , handle = EmailSettingsEvent
                        }
                      model.emailSettingsWidget
                ]
            ]
        , H.li [HA.style "margin-bottom" "1em"]
            [ H.text " When your prediction resolves to Yes or No, settle up with your friends! "
            ]
        ]
    ]

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = \_ -> Time.every 1000 Tick
    , view = view
    , update = update
    }
