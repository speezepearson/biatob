port module ViewUserPage exposing (..)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD
import Protobuf.Encode as PE
import Protobuf.Decode as PD

import Biatob.Proto.Mvp as Pb
import Utils

import Biatob.Proto.Mvp exposing (StakeResult(..))
import ChangePasswordWidget
import SetEmailWidget

port changed : () -> Cmd msg

type alias Model =
  { userId : Pb.UserId
  , userView : Pb.UserUserView
  , auth : Maybe Pb.AuthToken
  , working : Bool
  , setTrustedError : Maybe String
  , changePasswordWidget : ChangePasswordWidget.Model
  , setEmailWidget : SetEmailWidget.Model
  }

type Msg
  = SetTrusted Bool
  | SetTrustedFinished (Result Http.Error Pb.SetTrustedResponse)
  | ChangePasswordMsg ChangePasswordWidget.Msg
  | SetEmailMsg SetEmailWidget.Msg

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    (changePasswordWidget, changePasswordCmd) = ChangePasswordWidget.init ()
    (setEmailWidget, setEmailCmd) = SetEmailWidget.init flags
  in
  ( { userId = Utils.mustDecodePbFromFlags Pb.userIdDecoder "userIdPbB64" flags
    , userView = Utils.mustDecodePbFromFlags Pb.userUserViewDecoder "userViewPbB64" flags
    , auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags
    , working = False
    , setTrustedError = Nothing
    , changePasswordWidget = changePasswordWidget
    , setEmailWidget = setEmailWidget
    }
  , Cmd.batch
      [ Cmd.map ChangePasswordMsg changePasswordCmd
      , Cmd.map SetEmailMsg setEmailCmd
      ]
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
    SetTrusted trusted ->
      ( { model | working = True , setTrustedError = Nothing }
      , postSetTrusted {who=Just model.userId, trusted=trusted}
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
    ChangePasswordMsg widgetMsg ->
      let (newWidget, cmd) = ChangePasswordWidget.update widgetMsg model.changePasswordWidget in
      ( { model | changePasswordWidget = newWidget }, Cmd.map ChangePasswordMsg cmd)
    SetEmailMsg widgetMsg ->
      let (newWidget, cmd) = SetEmailWidget.update widgetMsg model.setEmailWidget in
      ( { model | setEmailWidget = newWidget }, Cmd.map SetEmailMsg cmd)


view : Model -> Html Msg
view model =
  H.div []
    [ H.h2 [] [H.text model.userView.displayName]
    , H.br [] []
    , if model.userView.isSelf then
        H.div []
          [ H.text "This is you!"
          , viewOwnSettings model
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

viewOwnSettings : Model -> Html Msg
viewOwnSettings model =
  H.div []
    [ H.h3 [] [H.text "Settings"]
    , H.ul []
        [ H.li [] [H.map ChangePasswordMsg <| ChangePasswordWidget.view model.changePasswordWidget]
        , H.li [] [H.map SetEmailMsg <| SetEmailWidget.view model.setEmailWidget]
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
