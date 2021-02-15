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

port changed : () -> Cmd msg

type alias Model =
  { auth : Pb.AuthToken
  , trustedUsers : List Pb.UserId
  , invitationWidget : SmallInvitationWidget.Model
  , invitations : Dict String Pb.Invitation
  , addTrustedUserField : Field () String
  , working : Bool
  , notification : Html Msg
  }

type Msg
  = RemoveTrust Pb.UserId
  | SetAddTrustedField String
  | AddTrusted
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)
  | InvitationMsg SmallInvitationWidget.Msg

init : { auth : Pb.AuthToken , trustedUsers : List Pb.UserId , invitations : Dict String Pb.Invitation } -> ( Model , Cmd Msg )
init flags =
  let (widget, widgetCmd) = SmallInvitationWidget.init {auth=flags.auth} in
  ( { auth = flags.auth
    , trustedUsers = flags.trustedUsers
    , invitationWidget = widget
    , invitations = flags.invitations
    , addTrustedUserField = Field.okIfEmpty <| Field.init "" <| \() s -> if String.isEmpty s then Err "must not be empty" else Ok s
    , working = False
    , notification = H.text ""
    }
  , Cmd.map InvitationMsg widgetCmd
  )

postSetTrusted : Pb.SetTrustedRequest -> Cmd Msg
postSetTrusted req =
  Http.post
    { url = "/api/SetTrusted"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toSetTrustedRequestEncoder req
    , expect = PD.expectBytes SetTrustedFinished Pb.setTrustedResponseDecoder }

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
          , postSetTrusted {who=Just {kind=Just (Pb.KindUsername username)}, trusted=True}
          )
        Err _ ->
          ( model , Cmd.none )
    RemoveTrust victim ->
      if List.member victim model.trustedUsers then
        ( { model | working = True
                  , notification = H.text ""
          }
        , postSetTrusted {who=Just victim, trusted=False}
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
    , H.br [] []
    , H.text "Outstanding:"
    , if D.isEmpty model.invitations then
        H.text " none yet!"
      else
        H.ul []
        <| List.map (\(nonce, invitation) ->
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
                    H.a [HA.href <| Utils.invitationPath id] [H.text "link"]
                  , H.text <| " (created " ++ Utils.dateStr Time.utc (Utils.unixtimeToTime invitation.createdUnixtime) ++ ")"
                  ]
                )
        <| List.sortBy (\(_, invitation) -> -invitation.createdUnixtime)
        <| D.toList
        <| model.invitations
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
