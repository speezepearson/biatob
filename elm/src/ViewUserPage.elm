port module ViewUserPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import API

port changed : () -> Cmd msg

type alias Model =
  { userId : Pb.UserId
  , userView : Pb.UserUserView
  , auth : Maybe Pb.AuthToken
  , working : Bool
  , setTrustedError : Maybe String
  }

type Msg
  = SetTrusted Bool
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)

init : JD.Value -> (Model, Cmd Msg)
init flags =
  ( { userId = Utils.mustDecodePbFromFlags Pb.userIdDecoder "userIdPbB64" flags
    , userView = Utils.mustDecodePbFromFlags Pb.userUserViewDecoder "userViewPbB64" flags
    , auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    , working = False
    , setTrustedError = Nothing
    }
  , Cmd.none
  )

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SetTrusted trusted ->
      ( { model | working = True , setTrustedError = Nothing }
      , API.postSetTrusted SetTrustedFinished {who=Just model.userId, trusted=trusted}
      )
    SetTrustedFinished (Err e) ->
      ( { model | working = False , setTrustedError = Just (Debug.toString e) }
      , Cmd.none
      )
    SetTrustedFinished (Ok resp) ->
      case resp.setTrustedResult of
        Just (Pb.SetTrustedResultOk _) ->
          ( model
          , changed ()
          )
        Just (Pb.SetTrustedResultError e) ->
          ( { model | working = False , setTrustedError = Just (Debug.toString e) }
          , Cmd.none
          )
        Nothing ->
          ( { model | working = False , setTrustedError = Just "Invalid server response (neither Ok nor Error in protobuf)" }
          , Cmd.none
          )

view : Model -> Html Msg
view model =
  H.div []
    [ H.h2 [] [H.text model.userView.displayName]
    , H.br [] []
    , if model.userView.isSelf then
        H.div []
          [ H.text "This is you! You might have meant to visit "
          , H.a [HA.href "/settings"] [H.text "your settings"]
          , H.text "?"
          ]
      else case model.auth of
        Nothing ->
          H.text "Log in to see your trust level with this user."
        Just token ->
          H.div []
            [ if model.userView.trustsYou then
                H.text "This user trusts you! :)"
              else
                H.div []
                  [ H.text "This user hasn't marked you as trusted! If you think that, in real life, they "
                  , H.i [] [H.text "do"]
                  , H.text " trust you to pay your debts, send them a link to "
                  , H.a [HA.href <| Utils.pathToUserPage <| Utils.mustTokenOwner token] [H.text "your user page"]
                  , H.text " and ask them to mark you as trusted."
                  ]
            , H.br [] []
            , if model.userView.isTrusted then
                H.div []
                  [ H.text "You trust this user. "
                  , H.button [HA.disabled model.working, HE.onClick (SetTrusted False)] [H.text "Mark untrusted"]
                  ]
              else
                H.div []
                  [ H.text "You don't trust this user. "
                  , H.button [HA.disabled model.working, HE.onClick (SetTrusted True)] [H.text "Mark trusted"]
                  ]
            , case model.setTrustedError of
                Just e -> H.div [HA.style "color" "red"] [H.text e]
                Nothing -> H.text ""
            ]
    ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

main : Program JD.Value Model Msg
main =
  Browser.element
    { init = init
    , subscriptions = subscriptions
    , view = view
    , update = update
    }
