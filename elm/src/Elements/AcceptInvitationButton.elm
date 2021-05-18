port module Elements.AcceptInvitationButton exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb

import Utils
import API

port invitationAccepted : () -> Cmd msg

type alias Model =
  { invitationId : Pb.InvitationId
  , working : Bool
  , notification : Html Never
  }

type Msg
  = AcceptInvitation
  | AcceptInvitationFinished (Result Http.Error Pb.AcceptInvitationResponse)

init : JD.Value -> ( Model , Cmd Msg )
init flags =
  ( { invitationId = Utils.mustDecodePbFromFlags Pb.invitationIdDecoder "invitationIdPbB64" flags
    , working = False
    , notification = H.text ""
    }
  , Cmd.none
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    AcceptInvitation ->
      ( { model | working = True , notification = H.text "" }
      , API.postAcceptInvitation AcceptInvitationFinished {invitationId=Just model.invitationId}
      )
    AcceptInvitationFinished (Err e) ->
      ( { model | working = False , notification = Utils.redText (Debug.toString e) }
      , Cmd.none
      )
    AcceptInvitationFinished (Ok resp) ->
      case resp.acceptInvitationResult of
        Just (Pb.AcceptInvitationResultOk _) ->
          ( model
          , invitationAccepted ()
          )
        Just (Pb.AcceptInvitationResultError e) ->
          ( { model | working = False , notification = Utils.redText (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )

view : Model -> Html Msg
view model =
  H.div []
    [ H.button
      [ HE.onClick AcceptInvitation
      , HA.disabled model.working
      ]
      [ H.text "I trust the person who sent me this link"]
    , model.notification |> H.map never
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main =
  Browser.element { init=init, view=view, update=update, subscriptions=subscriptions }
