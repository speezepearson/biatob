module Widgets.SmallInvitationWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http

import Biatob.Proto.Mvp as Pb
import Utils

import Utils
import Widgets.CopyWidget as CopyWidget
import API
import Utils exposing (InvitationNonce)

type alias Config msg =
  { setState : State -> msg
  , createInvitation : State -> Pb.CreateInvitationRequest -> msg
  , copy : String -> msg
  , destination : Maybe String
  , httpOrigin : String
  }
type State
  = Unstarted
  | AwaitingResponse
  | Succeeded InvitationNonce
  | Failed String

handleCreateInvitationResponse : Result Http.Error Pb.CreateInvitationResponse -> State -> State
handleCreateInvitationResponse res _ =
  case API.simplifyCreateInvitationResponse res of
    Ok resp -> Succeeded resp.nonce
    Err e -> Failed e

init : State
init = Unstarted

view : Config msg -> State -> Html msg
view config model =
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
    [ case model of
        Succeeded nonce ->
          CopyWidget.view config.copy (config.httpOrigin ++ Utils.invitationPath nonce ++ case config.destination of
             Just d -> "?dest="++d
             Nothing -> "" )
        _ -> H.text ""
    , H.button
        [ HA.disabled (model == AwaitingResponse)
        , HE.onClick (config.createInvitation AwaitingResponse {notes=""})
        ]
        [ H.text <| case model of
            Unstarted -> "Create invitation"
            AwaitingResponse -> "Creating..."
            Succeeded _ -> "Create another"
            Failed _ -> "Try again"
        ]
    , H.text " "
    , case model of
        Failed e -> Utils.redText e
        _ -> H.text ""
    , H.text " "
    , help
    ]
