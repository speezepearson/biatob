module Elements.AcceptInvitation exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import Widgets.AuthWidget as AuthWidget
import Utils
import Page
import Page.Program

type alias Model =
  { invitationId : Pb.InvitationId
  , invitationIsOpen : Bool
  , destination : Maybe String
  , authWidget : AuthWidget.Model
  , working : Bool
  , acceptNotification : Html Msg
  }

type Msg
  = AcceptInvitation
  | AcceptInvitationFinished (Result Http.Error Pb.AcceptInvitationResponse)
  | AuthWidgetMsg AuthWidget.Msg

init : JD.Value -> (Model, Page.Command Msg)
init flags =
  ( { invitationId = Utils.mustDecodePbFromFlags Pb.invitationIdDecoder "invitationIdPbB64" flags
    , destination = Utils.mustDecodeFromFlags (JD.nullable JD.string) "destination" flags
    , invitationIsOpen = Utils.mustDecodeFromFlags JD.bool "invitationIsOpen" flags
    , authWidget = AuthWidget.init
    , working = False
    , acceptNotification = H.text ""
    }
  , Page.NoCmd
  )

update : Msg -> Model -> (Model, Page.Command Msg)
update msg model =
  case msg of
    AcceptInvitation ->
      ( { model | working = True , acceptNotification = H.text "" }
      , Page.RequestCmd <| Page.AcceptInvitationRequest AcceptInvitationFinished {invitationId=Just model.invitationId}
      )
    AcceptInvitationFinished (Err e) ->
      ( { model | working = False , acceptNotification = Utils.redText (Debug.toString e) }
      , Page.NoCmd
      )
    AcceptInvitationFinished (Ok resp) ->
      case resp.acceptInvitationResult of
        Just (Pb.AcceptInvitationResultOk _) ->
          ( model
          , Page.NavigateCmd <| Just <| Maybe.withDefault (Utils.pathToUserPage model.invitationId.inviter) model.destination
          )
        Just (Pb.AcceptInvitationResultError e) ->
          ( { model | working = False , acceptNotification = Utils.redText (Debug.toString e) }
          , Page.NoCmd
          )
        Nothing ->
          ( { model | working = False , acceptNotification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
          , Page.NoCmd
          )
    AuthWidgetMsg widgetMsg ->
      let (newWidget, widgetCmd) = AuthWidget.update widgetMsg model.authWidget in
      ( { model | authWidget = newWidget } , Page.mapCmd AuthWidgetMsg widgetCmd )

isOwnInvitation : Page.Globals -> Pb.InvitationId -> Bool
isOwnInvitation globals invitationId =
  case Page.getAuth globals of
    Nothing -> False
    Just token -> token.owner == invitationId.inviter

view : Page.Globals -> Model -> Browser.Document Msg
view globals model =
  { title = "Accept Invitation"
  , body = [
    H.main_ [HA.style "text-align" "justify"] <|
    if isOwnInvitation globals model.invitationId then
      [H.text "This is your own invitation!"]
    else if not model.invitationIsOpen then
      [H.text "This invitation has been used up already!"]
    else
      [ H.h2 [] [H.text "Invitation from ", Utils.renderUser model.invitationId.inviter]
      , H.p []
        [ H.text <| "The person who sent you this link is interested in betting against you regarding real-world events,"
          ++ " with real money, upheld by the honor system!"
          ++ " They trust you to behave honorably and pay your debts, and hope that you trust them back."
        ]
      , H.p [] <|
        if Page.isLoggedIn globals then
          [ H.text "If you trust them back, click "
          , H.button [HE.onClick AcceptInvitation, HA.disabled model.working] [H.text "I trust the person who sent me this link"]
          , model.acceptNotification
          , H.text "; otherwise, just close this tab."
          ]
        else
          [ H.text "If you trust them back, and you're interested in betting against them:"
          , H.ul []
            [ H.li [] [H.text "Authenticate yourself: ", AuthWidget.view globals model.authWidget |> H.map AuthWidgetMsg]
            , H.li []
              [ H.text "...then click "
              , H.button
                [ HE.onClick AcceptInvitation
                , HA.disabled True -- login will trigger reload, and then we'll take the other case branch
                ] [H.text "I trust the person who sent me this link"]
              , model.acceptNotification
              , H.text "."
              ]
            ]
          ]
      , H.hr [] []
      , H.h3 [] [H.text "Huh? What? What is this?"]
      , H.p [] [H.text "This site is a tool that helps people make concrete predictions and bet on them, thereby clarifying their beliefs and making the world a better, saner place."]
      , H.p [] [H.text <| "Users can make predictions and say how confident they are;"
          ++ " then other people can bet real money against them. "
          , Utils.b "Everything is purely honor-system,"
          , H.text <| " so you don't have to provide a credit card or anything, but you ", Utils.i  "do"
          , H.text <| " have to tell the site who you trust, so that it knows who's allowed to bet against you."
          ++ " (Honor systems only work where there is honor.)"]
      , H.p [] [Utils.renderUser model.invitationId.inviter, H.text <|
          " thinks you might be interested in gambling against them, and trusts you to pay any debts you incur when you lose;"
          ++ " if you feel likewise, accept their invitation!"]
      ]
  ]}

subscriptions : Model -> Sub Msg
subscriptions model = AuthWidget.subscriptions model.authWidget |> Sub.map AuthWidgetMsg

pagedef : Page.Element Model Msg
pagedef = {init=init, view=view, update=update, subscriptions=subscriptions}

main = Page.Program.page pagedef
