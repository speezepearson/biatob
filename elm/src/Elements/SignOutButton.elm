port module Elements.SignOutButton exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE

import Biatob.Proto.Mvp as Pb
import Utils exposing (WorkingState(..))
import Http

import API
import Browser

port loggedOut : () -> Cmd msg

type Msg
  = SignOut
  | SignOutFinished (Result Http.Error Pb.SignOutResponse)

type alias Model = WorkingState

init : () -> (Model, Cmd Msg)
init () =
  ( Awaiting { notification = H.text "" }
  , Cmd.none
  )

view : Model -> Html Msg
view model =
  case model of
    Awaiting {notification} ->
      H.div []
        [ H.button [ HE.onClick SignOut ] [H.text "Sign out"]
        , notification |> H.map never
        ]

    Working ->
      H.button [ HA.disabled True ] [ H.text "Signing out..." ]

    Done ->
      H.button [ HA.disabled True ] [ H.text "Signed out" ]

update : Msg -> Model -> ( Model , Cmd Msg )
update msg _ =
  case msg of
    SignOut ->
      ( Working
      , API.postSignOut SignOutFinished {}
      )
    SignOutFinished res ->
      ( case res of
          Err e -> Awaiting { notification = Utils.redText (Debug.toString e) }
          Ok {} -> Done
      , loggedOut ()
      )

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main =
  Browser.element {init=init, view=view, update=update, subscriptions=subscriptions}
