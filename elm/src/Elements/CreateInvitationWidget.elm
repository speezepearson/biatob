port module Elements.CreateInvitationWidget exposing (..)

import Browser

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import Utils
import Widgets.CopyWidget as CopyWidget
import Page
import API

port copy : String -> Cmd msg

type Msg
  = Copy String
  | CreateInvitation
  | CreateInvitationFinished (Result Http.Error Pb.CreateInvitationResponse)

type alias Model =
  { httpOrigin : String
  , invitationId : Maybe Pb.InvitationId
  , destination : Maybe String
  , working : Bool
  , notification : Html Never
  }

update : Msg -> Model -> ( Model , Cmd Msg )
update msg model =
  case msg of
    Copy s -> ( model , copy s )
    CreateInvitation ->
      ( { model | working = False , notification = H.text "" }
      , API.postCreateInvitation CreateInvitationFinished {notes=""}
      )
    CreateInvitationFinished res ->
      ( case res of
          Err e ->
            { model | working = False , notification = Utils.redText (Debug.toString e) }
          Ok resp ->
            case resp.createInvitationResult of
              Just (Pb.CreateInvitationResultOk result) ->
                { model | working = False
                        , notification = H.text ""
                        , invitationId = result.id
                }
              Just (Pb.CreateInvitationResultError e) ->
                { model | working = False , notification = Utils.redText (Debug.toString e) }
              Nothing ->
                { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
      , Cmd.none
      )

setInvitation : Maybe Pb.InvitationId -> Model -> Model
setInvitation inv model = { model | invitationId = inv }

init : JD.Value -> ( Model , Cmd Msg )
init flags =
  ( { httpOrigin = Utils.mustDecodeFromFlags JD.string "httpOrigin" flags
    , invitationId = Nothing
    , destination = Utils.mustDecodeFromFlags (JD.nullable JD.string) "destination" flags
    , working = False
    , notification = H.text ""
    }
  , Cmd.none
  )

view : Model -> Html Msg
view model =
  let
    help : Html Msg
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
    [ case model.invitationId of
        Nothing -> H.text ""
        Just id ->
          CopyWidget.view Copy (model.httpOrigin ++ Utils.invitationPath id ++ case model.destination of
             Just d -> "?dest="++d
             Nothing -> "" )
    , H.button
        [ HA.disabled model.working
        , HE.onClick CreateInvitation
        ]
        [ H.text <| if model.working then "Creating..." else if model.invitationId == Nothing then "Create invitation" else "Create another"
        ]
    , H.text " "
    , model.notification |> H.map never
    , H.text " "
    , help
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main =
  Browser.element {init=init, view=view, update=update, subscriptions=subscriptions}
