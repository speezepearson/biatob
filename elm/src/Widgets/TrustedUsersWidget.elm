module Widgets.TrustedUsersWidget exposing (..)
import Biatob.Proto.Mvp exposing (SetTrustedRequest)
import Page

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

type Msg
  = Copy String
  | InvitationMsg SmallInvitationWidget.Msg
  | RemoveTrust Pb.UserId
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)

type alias Model =
  { invitationWidget : SmallInvitationWidget.Model
  , addTrustedUserField : Field () String
  , working : Bool
  , notification : Html Never
  }

init : Model
init =
  { invitationWidget = SmallInvitationWidget.init Nothing
  , addTrustedUserField = Field.okIfEmpty <| Field.init "" <| \() s -> if String.isEmpty s then Err "must not be empty" else Ok s
  , working = False
  , notification = H.text ""
  }

update : Msg -> Model -> ( Model , Page.Command Msg )
update msg model =
  case msg of
    Copy s -> ( model , Page.CopyCmd s )
    RemoveTrust u ->
      ( { model | working = True, notification = H.text "" }
      , Page.RequestCmd <| Page.SetTrustedRequest SetTrustedFinished {who=Just u, trusted=False}
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
        Just accepter ->
          H.li []
            [ H.text "Accepted by "
            , Utils.renderUser accepter
            , H.text <| " on " ++ Utils.dateStr globals.timeZone (Utils.unixtimeToTime invitation.createdUnixtime)
            , H.text <| " (created " ++ Utils.dateStr globals.timeZone (Utils.unixtimeToTime invitation.createdUnixtime) ++ ")"
            ]
        Nothing ->
          H.li []
            [ CopyWidget.view Copy (globals.httpOrigin ++ Utils.invitationPath {inviter=auth.owner, nonce=nonce})
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
  case globals.authState of
    Nothing -> H.text "(Log in to see who you trust!)"
    Just auth ->
      H.div []
        [ model.notification |> H.map never
        , H.strong [] [H.text "You trust: "]
        , case (Utils.mustAuthSuccessUserInfo auth).trustedUsers of
            [] -> H.text "nobody yet!"
            trustedUsers ->
              H.ul []
              <| List.map (\u -> H.li []
                  [ Utils.renderUser u
                  , H.text " "
                  , H.button
                      [ HE.onClick (RemoveTrust u)
                      , HA.disabled model.working
                      ] [H.text "Remove trust"]
                  ])
                  trustedUsers
        , H.br [] []
        , H.strong [] [H.text "Invitations: "]
        , SmallInvitationWidget.view globals model.invitationWidget |> H.map InvitationMsg
        , H.div [] [H.text "Outstanding:", viewInvitations globals (\inv -> inv.acceptedBy == Nothing) ]
        , H.div [] [H.text "Past:",        viewInvitations globals (\inv -> inv.acceptedBy /= Nothing) ]
        ]
