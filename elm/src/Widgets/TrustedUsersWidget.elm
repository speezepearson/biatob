module Widgets.TrustedUsersWidget exposing (..)
import Page

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Dict as D

import Biatob.Proto.Mvp as Pb
import Utils exposing (Username)

import Utils

import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Widgets.CopyWidget as CopyWidget

type Msg
  = Copy String
  | InvitationMsg SmallInvitationWidget.Msg
  | RemoveTrust Username
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)

type alias Model =
  { invitationWidget : SmallInvitationWidget.Model
  , working : Bool
  , notification : Html Never
  }

init : Model
init =
  { invitationWidget = SmallInvitationWidget.init Nothing
  , working = False
  , notification = H.text ""
  }

update : Msg -> Model -> ( Model , Page.Command Msg )
update msg model =
  case msg of
    Copy s -> ( model , Page.CopyCmd s )
    RemoveTrust u ->
      ( { model | working = True, notification = H.text "" }
      , Page.RequestCmd <| Page.SetTrustedRequest SetTrustedFinished {whoDepr=Just {kind=Just (Pb.KindUsername u)}, who=u, trusted=False}
      )
    InvitationMsg widgetMsg ->
      let (newWidget, widgetCmd) = SmallInvitationWidget.update widgetMsg model.invitationWidget in
      ( { model | invitationWidget = newWidget }
      , Page.mapCmd InvitationMsg widgetCmd
      )
    SetTrustedFinished res ->
      ( case res of
          Err e ->
            { model | working = False , notification = Utils.redText (Debug.toString e) }
          Ok resp ->
            case resp.setTrustedResult of
              Just (Pb.SetTrustedResultOk _) ->
                { model | working = False , notification = H.text "" }
              Just (Pb.SetTrustedResultError e) ->
                { model | working = False , notification = Utils.redText (Debug.toString e) }
              Nothing ->
                { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
      , Page.NoCmd
      )

viewInvitation : Page.Globals -> String -> Pb.Invitation -> Html Msg
viewInvitation globals nonce invitation =
  case Page.getAuth globals of
    Nothing -> Utils.redText "Hrrm, strange, I'm confused about whether you're logged in. Sorry!"
    Just auth ->
      case invitation.acceptedBy of
        "" ->
          H.li []
            [ CopyWidget.view Copy (globals.httpOrigin ++ Utils.invitationPath {inviterDepr=auth.ownerDepr, inviter="", nonce=nonce})
            , H.text <| " (created " ++ Utils.dateStr globals.timeZone (Utils.unixtimeToTime invitation.createdUnixtime) ++ ")"
            ]
        accepter ->
          H.li []
            [ H.text "Accepted by "
            , Utils.renderUser accepter
            , H.text <| " on " ++ Utils.dateStr globals.timeZone (Utils.unixtimeToTime invitation.createdUnixtime)
            , H.text <| " (created " ++ Utils.dateStr globals.timeZone (Utils.unixtimeToTime invitation.createdUnixtime) ++ ")"
            ]

viewInvitations : Page.Globals -> (Pb.Invitation -> Bool) -> Html Msg
viewInvitations globals filter =
  case Page.getUserInfo globals of
    Nothing -> Utils.redText "Hrrm, strange, I'm confused about whether you're logged in. Sorry!"
    Just userInfo ->
      let
        matches =
          userInfo.invitations
          |> Utils.mustMapValues
          |> D.filter (always filter)
          |> D.toList
          |> List.sortBy (\(_, invitation) -> -invitation.createdUnixtime)
      in
        if List.isEmpty matches then
          H.text " none yet!"
        else
          matches
          |> List.map (\(nonce, invitation) -> H.li [] [viewInvitation globals nonce invitation])
          |> H.ul []

view : Page.Globals -> Model -> Html Msg
view globals model =
  case globals.serverState.settings of
    Nothing -> H.text "(Log in to see who you trust!)"
    Just userInfo ->
      H.div []
        [ model.notification |> H.map never
        , Utils.b "Your relationships: "
        , let relationships = userInfo |> .relationships |> Utils.mustMapValues in
          if D.isEmpty relationships then
            H.text "nobody yet!"
          else
            H.ul []
            <| List.map (\(u, rel) -> H.li []
                [ Utils.renderUser u
                , H.text ": "
                , if rel.trusted then
                    H.span []
                      [ H.text "trusted "
                      , H.button
                          [ HE.onClick (RemoveTrust u)
                          , HA.disabled model.working
                          ] [H.text "Remove trust"]
                      ]
                  else
                    H.text " untrusted"
                ])
            <| D.toList relationships
        , H.br [] []
        , Utils.b "Invitations: "
        , SmallInvitationWidget.view globals model.invitationWidget |> H.map InvitationMsg
        , H.div [] [H.text "Outstanding:", viewInvitations globals (\inv -> inv.acceptedByDepr == Nothing) ]
        , H.div [] [H.text "Past:",        viewInvitations globals (\inv -> inv.acceptedByDepr /= Nothing) ]
        ]

subscriptions : Model -> Sub Msg
subscriptions model = SmallInvitationWidget.subscriptions model.invitationWidget |> Sub.map InvitationMsg
