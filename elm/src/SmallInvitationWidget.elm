module SmallInvitationWidget exposing (..)

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

type alias Model =
  { auth : Pb.AuthToken
  , invitationId : Maybe Pb.InvitationId
  , working : Bool
  , notification : Html Msg
  }

type Msg
  = CreateInvitation
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)

init : { auth : Pb.AuthToken } -> ( Model , Cmd Msg )
init flags =
  ( { auth = flags.auth
    , invitationId = Nothing
    , working = False
    , notification = H.text ""
    }
  , Cmd.none
  )

checkCreationSuccess : Msg -> Maybe Pb.CreateInvitationResponseResult
checkCreationSuccess msg =
  case msg of
    CreateInvitationFinished (Ok {createInvitationResult}) ->
      case createInvitationResult of
        Just (Pb.CreateInvitationResultOk result) ->
          Just result
        _ -> Nothing
    _ -> Nothing

postCreateInvitation : Pb.CreateInvitationRequest -> Cmd Msg
postCreateInvitation req =
  Http.post
    { url = "/api/CreateInvitation"
    , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toCreateInvitationRequestEncoder req
    , expect = PD.expectBytes CreateInvitationFinished Pb.createInvitationResponseDecoder }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
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
          ( { model | working = False , invitationId = Just {inviter=model.auth.owner, nonce=result.nonce} }
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
  let
    help : Html msg
    help =
      H.details [HA.style "display" "inline", HA.style "outline" "1px solid #cccccc"]
        [ H.summary [] [H.text "?"]
        , H.text <|
            "Recall that you can only bet against people you trust;"
            ++ " an invitation link is a one-time-use code that proves you trust whoever has it."
            ++ " The intended use is, you create a code, message it to somebody you trust"
            ++ " (however you normally message them), and they click the link to claim your trust."
        ]
  in
  H.span []
    [ case model.invitationId of
        Nothing -> H.text ""
        Just id ->
          let path = Utils.invitationPath id in H.a [HA.href path] [H.text path]
    , H.button
        [ HA.disabled model.working
        , HE.onClick CreateInvitation
        ]
        [ H.text <| if model.working then "Creating..." else if model.invitationId == Nothing then "Create invitation" else "Create another"
        ]
    , H.text " "
    , model.notification
    , H.text " "
    , help
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
