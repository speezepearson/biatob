module Widgets.TrustedUsersWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Dict as D exposing (Dict)

import Biatob.Proto.Mvp as Pb
import Utils

import Field exposing (Field)
import Time
import Utils

import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Widgets.CopyWidget as CopyWidget

type Event = Copy String | InvitationEvent SmallInvitationWidget.Event | RemoveTrust Pb.UserId
type alias Context msg =
  { auth : Pb.AuthToken
  , trustedUsers : List Pb.UserId
  , httpOrigin : String
  , invitations : Dict String Pb.Invitation
  , handle : (Maybe Event) -> State -> msg
  }
type alias State =
  { invitationWidget : SmallInvitationWidget.State
  , addTrustedUserField : Field () String
  , working : Bool
  , notification : Html ()
  }

invitationWidgetCtx : Context msg -> State -> SmallInvitationWidget.Context msg
invitationWidgetCtx ctx state =
  { destination = Nothing
  , httpOrigin = ctx.httpOrigin
  , handle = \e m -> ctx.handle (Maybe.map InvitationEvent e) { state | invitationWidget = m }
  }

init : State
init =
  { invitationWidget = SmallInvitationWidget.init
  , addTrustedUserField = Field.okIfEmpty <| Field.init "" <| \() s -> if String.isEmpty s then Err "must not be empty" else Ok s
  , working = False
  , notification = H.text ""
  }

handleSetTrustedResponse : Result Http.Error Pb.SetTrustedResponse -> State -> State
handleSetTrustedResponse res state =
  case res of
    Err e ->
      { state | working = False , notification = Utils.redText (Debug.toString e) }
    Ok resp ->
      case resp.setTrustedResult of
        Just (Pb.SetTrustedResultOk _) ->
          { state | working = False }
        Just (Pb.SetTrustedResultError e) ->
          { state | working = False , notification = Utils.redText (Debug.toString e) }
        Nothing ->
          { state | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }

handleCreateInvitationResponse : Result Http.Error Pb.CreateInvitationResponse -> State -> State
handleCreateInvitationResponse res state = { state | invitationWidget = state.invitationWidget |> SmallInvitationWidget.handleCreateInvitationResponse res}

viewInvitation : Context msg -> State -> String -> Pb.Invitation -> Html msg
viewInvitation ctx state nonce invitation =
  case invitation.acceptedBy of
    Just accepter ->
      H.li []
        [ H.text "Accepted by "
        , Utils.renderUser accepter
        , H.text <| " on " ++ Utils.dateStr Time.utc (Utils.unixtimeToTime invitation.createdUnixtime)
        , H.text <| " (created " ++ Utils.dateStr Time.utc (Utils.unixtimeToTime invitation.createdUnixtime) ++ ")"
        ]
    Nothing ->
      H.li []
        [ let
            id : Pb.InvitationId
            id = { inviter = ctx.auth.owner , nonce = nonce }
          in
            CopyWidget.view (\s -> ctx.handle (Just <| Copy s) state) (ctx.httpOrigin ++ Utils.invitationPath id)
        , H.text <| " (created " ++ Utils.dateStr Time.utc (Utils.unixtimeToTime invitation.createdUnixtime) ++ ")"
        ]

viewInvitations : Context msg -> State -> (Pb.Invitation -> Bool) -> Html msg
viewInvitations ctx state filter =
  let
    matches =
      ctx.invitations
      |> D.filter (always filter)
      |> D.toList
      |> List.sortBy (\(_, invitation) -> -invitation.createdUnixtime)
  in
  if List.isEmpty matches then
    H.text " none yet!"
  else
    matches
    |> List.map (\(nonce, invitation) -> H.li [] [viewInvitation ctx state nonce invitation])
    |> H.ul []

view : Context msg -> State -> Html msg
view ctx state =
  H.div []
    [ state.notification |> H.map (\_ -> ctx.handle Nothing state)
    , H.strong [] [H.text "You trust: "]
    , if List.isEmpty ctx.trustedUsers then
        H.text "nobody yet!"
      else
        H.ul []
        <| List.map (\u -> H.li []
            [ Utils.renderUser u
            , H.text " "
            , H.button
                [ HE.onClick (ctx.handle (Just <| RemoveTrust u) { state | working = True , notification = H.text ""})
                , HA.disabled state.working
                ] [H.text "Remove trust"]
            ])
        <| ctx.trustedUsers
    , H.br [] []
    , H.strong [] [H.text "Invitations: "]
    , SmallInvitationWidget.view (invitationWidgetCtx ctx state) state.invitationWidget
    , H.div [] [H.text "Outstanding:", viewInvitations ctx state (\inv -> inv.acceptedBy == Nothing) ]
    , H.div [] [H.text "Past:",        viewInvitations ctx state (\inv -> inv.acceptedBy /= Nothing) ]
    ]
