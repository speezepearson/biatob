module Widgets.SmallInvitationWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http

import Biatob.Proto.Mvp as Pb

import API
import Utils exposing (Username)

type alias Config msg =
  { setState : State -> msg
  , sendInvitation : State -> Pb.SendInvitationRequest -> msg
  , recipient : Username
  }
type State
  = Unstarted
  | AwaitingResponse
  | Succeeded
  | Failed String

handleSendInvitationResponse : Result Http.Error Pb.SendInvitationResponse -> State -> State
handleSendInvitationResponse res _ =
  case API.simplifySendInvitationResponse res of
    Ok _ -> Succeeded
    Err e -> Failed e

init : State
init = Unstarted

view : Config msg -> State -> Html msg
view config state =
  let
    help : Html msg
    help =
      H.details [HA.style "display" "inline", HA.style "outline" "1px solid #cccccc"]
        [ H.summary [] [H.text "(huh?)"]
        , H.text <|
            "An invitation link is a one-time-use code that you send to people you trust, in order to let Biatob know you trust them."
            ++ " The intended use is: you create an invitation; you send it to somebody you trust;"
            ++ " they click the link; and from then on, Biatob knows you trust each other."
        ]
  in
  H.span []
    [ case state of
        Unstarted ->
          H.button [ HE.onClick <| config.sendInvitation AwaitingResponse {recipient=config.recipient} ] [ H.text <| "Invite " ++ config.recipient ]
        AwaitingResponse ->
          H.button [HA.disabled True] [H.text "Sending invitation..."]
        Succeeded ->
          H.button [HA.disabled True] [H.text "Invitation sent!"]
        Failed e ->
          H.span []
          [ Utils.redText e
          , H.button [ HE.onClick <| config.sendInvitation AwaitingResponse {recipient=config.recipient} ] [ H.text "Try again?" ]
          ]
    , H.text " "
    , help
    ]
