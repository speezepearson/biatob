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
import SmallInvitationWidget

port changed : () -> Cmd msg

type AuthState = LoggedIn Pb.AuthToken SmallInvitationWidget.Model | LoggedOut
type alias Model =
  { userId : Pb.UserId
  , userView : Pb.UserUserView
  , authState : AuthState
  , working : Bool
  , setTrustedError : Maybe String
  }

type Msg
  = SetTrusted Bool
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)
  | InvitationMsg SmallInvitationWidget.Msg

init : JD.Value -> (Model, Cmd Msg)
init flags =
  ( { userId = Utils.mustDecodePbFromFlags Pb.userIdDecoder "userIdPbB64" flags
    , userView = Utils.mustDecodePbFromFlags Pb.userUserViewDecoder "userViewPbB64" flags
    , authState = case Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags of
        Just auth -> LoggedIn auth (SmallInvitationWidget.init {auth=auth, linkToAuthority=Utils.mustDecodeFromFlags JD.string "linkToAuthority" flags})
        Nothing -> LoggedOut
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
    InvitationMsg widgetMsg ->
      case model.authState of
        LoggedIn auth widget ->
          let (newWidget, widgetCmd) = SmallInvitationWidget.update widgetMsg widget in
          ( { model | authState = LoggedIn auth newWidget }
          , Cmd.map InvitationMsg widgetCmd
          )
        LoggedOut -> Debug.todo "bad state"


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
      else case model.authState of
        LoggedOut ->
          H.text "Log in to see your relationship with this user."
        LoggedIn _ invitationWidget ->
          H.div []
            [ if model.userView.trustsYou then
                H.text "This user trusts you! :)"
              else
                H.div []
                  [ H.text "This user hasn't marked you as trusted! If you think that, in real life, they "
                  , H.i [] [H.text "do"]
                  , H.text " trust you, send them an invitation: "
                  , SmallInvitationWidget.view invitationWidget |> H.map InvitationMsg
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
