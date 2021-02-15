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
import CopyWidget

type alias Model =
  { auth : Pb.AuthToken
  , invitationId : Maybe Pb.InvitationId
  , linkToAuthority : String
  , working : Bool
  , notification : Html Msg
  }

type Msg
  = CreateInvitation
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)
  | Copy String

init : { auth : Pb.AuthToken , linkToAuthority : String } -> Model
init flags =
  { auth = flags.auth
  , invitationId = Nothing
  , linkToAuthority = flags.linkToAuthority
  , working = False
  , notification = H.text ""
  }

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

    Copy s -> ( model , CopyWidget.copy s )

view : Model -> Html Msg
view model =
  let
    help : Html msg
    help =
      H.details [HA.style "display" "inline", HA.style "outline" "1px solid #cccccc"]
        [ H.summary [] [H.text "?"]
        , H.text <|
            "An invitation link is a one-time-use code that you send to people you trust, in order to let Biatob know you trust them."
            ++ " The intended use is: you create an invitation; you send it to somebody you trust;"
            ++ " they click the link; and from then on, Biatob knows you trust each other."
        ]
  in
  H.span []
    [ case model.invitationId of
        Nothing -> H.text ""
        Just id ->
          CopyWidget.view Copy (model.linkToAuthority ++ Utils.invitationPath id)
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
