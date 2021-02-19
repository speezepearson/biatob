port module TrustedUsersWidget exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Dict as D exposing (Dict)
import Protobuf.Encode as PE
import Protobuf.Decode as PD

import Biatob.Proto.Mvp as Pb
import Utils

import Field exposing (Field)
import Time
import Utils

import SmallInvitationWidget
import CopyWidget
import API

port changed : () -> Cmd msg

type alias Model =
  { auth : Pb.AuthToken
  , trustedUsers : List Pb.UserId
  , invitationWidget : SmallInvitationWidget.Model
  , invitations : Dict String Pb.Invitation
  , addTrustedUserField : Field () String
  , linkToAuthority : String
  , working : Bool
  , notification : Html Msg
  }

type Msg
  = RemoveTrust Pb.UserId
  | SetAddTrustedField String
  | AddTrusted
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)
  | InvitationMsg SmallInvitationWidget.Msg
  | Copy String

init : { auth : Pb.AuthToken , trustedUsers : List Pb.UserId , invitations : Dict String Pb.Invitation , linkToAuthority : String } -> ( Model , Cmd Msg )
init flags =
  ( { auth = flags.auth
    , trustedUsers = flags.trustedUsers
    , invitationWidget = SmallInvitationWidget.init {auth=flags.auth, linkToAuthority=flags.linkToAuthority, destination=Nothing}
    , invitations = flags.invitations
    , addTrustedUserField = Field.okIfEmpty <| Field.init "" <| \() s -> if String.isEmpty s then Err "must not be empty" else Ok s
    , linkToAuthority = flags.linkToAuthority
    , working = False
    , notification = H.text ""
    }
  , Cmd.none
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetAddTrustedField s ->
      ( { model | addTrustedUserField = model.addTrustedUserField |> Field.setStr s }
      , Cmd.none
      )
    AddTrusted ->
      case Field.parse () model.addTrustedUserField of
        Ok username ->
          ( { model | addTrustedUserField = model.addTrustedUserField |> Field.setStr ""
                    , working = True
                    , notification = H.text ""
            }
          , API.postSetTrusted SetTrustedFinished {who=Just {kind=Just (Pb.KindUsername username)}, trusted=True}
          )
        Err _ ->
          ( model , Cmd.none )
    RemoveTrust victim ->
      if List.member victim model.trustedUsers then
        ( { model | working = True
                  , notification = H.text ""
          }
        , API.postSetTrusted SetTrustedFinished {who=Just victim, trusted=False}
        )
      else
        ( model , Cmd.none )
    SetTrustedFinished (Err e) ->
      ( { model | working = False , notification = Utils.redText (Debug.toString e) }
      , Cmd.none
      )
    SetTrustedFinished (Ok resp) ->
      case resp.setTrustedResult of
        Just (Pb.SetTrustedResultOk _) ->
          ( { model | working = False } , changed () )
        Just (Pb.SetTrustedResultError e) ->
          ( { model | working = False , notification = Utils.redText (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )
    InvitationMsg widgetMsg ->
      let (widget, widgetCmd) = SmallInvitationWidget.update widgetMsg model.invitationWidget in
      ( { model | invitationWidget = widget }
        |> case SmallInvitationWidget.checkCreationSuccess widgetMsg of
              Just result -> \m -> { m | invitations = m.invitations |> D.insert result.nonce (Utils.mustCreateInvitationResultInvitation result) }
              _ -> identity
      , Cmd.map InvitationMsg widgetCmd
      )

    Copy s -> ( model , CopyWidget.copy s )

viewInvitation : Model -> String -> Pb.Invitation -> Html Msg
viewInvitation model nonce invitation =
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
            id = { inviter = model.auth.owner , nonce = nonce }
            username = case Utils.mustUserKind <| Utils.mustTokenOwner model.auth of
                Pb.KindUsername u -> u
          in
            CopyWidget.view Copy (model.linkToAuthority ++ Utils.invitationPath id)
        , H.text <| " (created " ++ Utils.dateStr Time.utc (Utils.unixtimeToTime invitation.createdUnixtime) ++ ")"
        ]

viewInvitations : Model -> (Pb.Invitation -> Bool) -> Html Msg
viewInvitations model filter =
  let
    matches =
      model.invitations
      |> D.filter (always filter)
      |> D.toList
      |> List.sortBy (\(_, invitation) -> -invitation.createdUnixtime)
  in
  if List.isEmpty matches then
    H.text " none yet!"
  else
    matches
    |> List.map (\(nonce, invitation) -> H.li [] [viewInvitation model nonce invitation])
    |> H.ul []

view : Model -> Html Msg
view model =
  H.div []
    [ model.notification
    , H.strong [] [H.text "You trust: "]
    , if List.isEmpty model.trustedUsers then
        H.text "nobody yet!"
      else
        H.ul []
        <| List.map (\u -> H.li []
            [ Utils.renderUser u
            , H.text " "
            , H.button
                [ HE.onClick (RemoveTrust u)
                , HA.disabled model.working
                ] [H.text "Remove trust"]
            ])
        <| model.trustedUsers
    , H.br [] []
    , H.strong [] [H.text "Invitations: "]
    , SmallInvitationWidget.view model.invitationWidget |> H.map InvitationMsg
    , H.div [] [H.text "Outstanding:", viewInvitations model (\inv -> inv.acceptedBy == Nothing) ]
    , H.div [] [H.text "Past:",        viewInvitations model (\inv -> inv.acceptedBy /= Nothing) ]
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
