port module TrustedUsersWidget exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Protobuf.Encode as PE
import Protobuf.Decode as PD

import Biatob.Proto.Mvp as Pb
import Utils

import Field exposing (Field)

port changed : () -> Cmd msg

type alias Model =
  { trustedUsers : List Pb.UserId
  , addTrustedUserField : Field () String
  , working : Bool
  , notification : Html Msg
  }

type Msg
  = RemoveTrust Pb.UserId
  | SetAddTrustedField String
  | AddTrusted
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)

init : List Pb.UserId -> ( Model , Cmd Msg )
init trustedUsers =
  ( { trustedUsers = trustedUsers
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

view : Model -> Html Msg
view model =
  H.div []
    [ model.notification
    , if List.isEmpty model.trustedUsers then
        H.text "You don't trust anybody yet!"
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
    , H.text "Or: "
    , Field.inputFor SetAddTrustedField () model.addTrustedUserField
        H.input
        [ HA.disabled model.working
        , HA.placeholder "username"
        ] []
    , H.button [HE.onClick AddTrusted, HA.disabled <| not <| Field.isValid () model.addTrustedUserField] [H.text "Add trust"]
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
