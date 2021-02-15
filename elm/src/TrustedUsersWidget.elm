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

port changed : () -> Cmd msg

type alias Model =
  { auth : Pb.AuthToken
  , trustedUsers : List Pb.UserId
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
  | CreateInvitation
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)

init : { auth : Pb.AuthToken , trustedUsers : List Pb.UserId , invitations : Dict String Pb.Invitation } -> ( Model , Cmd Msg )
init flags =
  ( { auth = flags.auth
    , trustedUsers = flags.trustedUsers
    , invitations = flags.invitations
    , addTrustedUserField = Field.okIfEmpty <| Field.init "" <| \() s -> if String.isEmpty s then Err "must not be empty" else Ok s
    , working = False
    , notification = H.text ""
    }
  , Cmd.none
  )

postSetTrusted : Pb.SetTrustedRequest -> Cmd Msg
postSetTrusted req =
  Http.post
    { url = "/api/SetTrusted"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toSetTrustedRequestEncoder req
    , expect = PD.expectBytes SetTrustedFinished Pb.setTrustedResponseDecoder }

postCreateInvitation : Pb.CreateInvitationRequest -> Cmd Msg
postCreateInvitation req =
  Http.post
    { url = "/api/CreateInvitation"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toCreateInvitationRequestEncoder req
    , expect = PD.expectBytes CreateInvitationFinished Pb.createInvitationResponseDecoder }

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
    CreateInvitation ->
      ( { model | working = True , notification = H.text "" }
      , postCreateInvitation {notes = ""}  -- TODO(P3): add notes field
      )
    CreateInvitationFinished (Err e) ->
      ( { model | working = False , notification = Utils.redText (Debug.toString e) }
      , Cmd.none
      )
    CreateInvitationFinished (Ok resp) ->
      case resp.createInvitationResult of
        Just (Pb.CreateInvitationResultOk result) ->
          ( { model | working = False , invitations = model.invitations |> D.insert result.nonce (Utils.mustCreateInvitationResultInvitation result)}
          , Cmd.none
          )
        Just (Pb.CreateInvitationResultError e) ->
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
    , H.strong [] [H.text "Your invitations: "]
    , if D.isEmpty model.invitations then
        H.text "none yet!"
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
                      username = case Utils.mustUserKind <| Utils.mustTokenOwner model.auth of
                         Pb.KindUsername u -> u
                    in
                    H.a [HA.href <| "/invitation/" ++ username ++ "/" ++ nonce] [H.text "link"]
                  , H.text <| " (created " ++ Utils.dateStr Time.utc (Utils.unixtimeToTime invitation.createdUnixtime) ++ ")"
                  ]
                )
        <| List.sortBy (\(_, invitation) -> -invitation.createdUnixtime)
        <| D.toList
        <| model.invitations
    , H.br [] []
    , H.button [HE.onClick CreateInvitation] [H.text "New invitation"]
    , H.br [] []
    , H.text "Send the above links to people you trust in real life; when they click the link, that will tell Biatob that you trust them."
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
