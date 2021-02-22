module Elements.EmailSettings exposing (main)

import Browser
import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import Field exposing (Field)
import API
import Widgets.EmailSettingsWidget as Widget

type alias Model = ( Widget.Context Msg , Widget.State )
type Msg
  = WidgetEvent (Maybe Widget.Event) Widget.State
  | SetEmailFinished (Result Http.Error Pb.SetEmailResponse)
  | VerifyEmailFinished (Result Http.Error Pb.VerifyEmailResponse)
  | UpdateSettingsFinished (Result Http.Error Pb.UpdateSettingsResponse)

init : JD.Value -> (Model, Cmd Msg)
init flags =
  let
    userInfo = Utils.mustDecodePbFromFlags Pb.genericUserInfoDecoder "userInfoPbB64" flags
  in
  ( ( { emailFlowState = userInfo |> Utils.mustUserInfoEmail
      , emailRemindersToResolve = userInfo.emailRemindersToResolve
      , emailResolutionNotifications = userInfo.emailResolutionNotifications
      , handle = WidgetEvent
      }
    , Widget.init
    )
  , Cmd.none
  )

updateCtx : Pb.GenericUserInfo -> Widget.Context Msg -> Widget.Context Msg
updateCtx userInfo ctx =
  { ctx | emailFlowState = userInfo |> Utils.mustUserInfoEmail
        , emailRemindersToResolve = userInfo.emailRemindersToResolve
        , emailResolutionNotifications = userInfo.emailResolutionNotifications
  }

emailSettingsHandler : Widget.Handler Model
emailSettingsHandler =
  { updateWidget = \f (ctx, m) -> (ctx, m |> f)
  , setEmailFlowState = \e (ctx, m) -> ({ ctx | emailFlowState = e }, m)
  }

update : Msg -> Model -> (Model, Cmd Msg)
update msg (ctx, model) =
  case msg of
    WidgetEvent event newState ->
      let
        cmd = case event of
          Just (Widget.SetEmail req) -> API.postSetEmail SetEmailFinished req
          Just (Widget.VerifyEmail req) -> API.postVerifyEmail VerifyEmailFinished req
          Just (Widget.UpdateSettings req) -> API.postUpdateSettings UpdateSettingsFinished req
          Just Widget.Ignore -> Cmd.none
          Nothing -> Cmd.none
      in
        ((ctx, newState), cmd)

    SetEmailFinished res ->
      ( Widget.handleSetEmailResponse emailSettingsHandler res (ctx, model)
      , Cmd.none
      )

    VerifyEmailFinished res ->
      ( Widget.handleVerifyEmailResponse emailSettingsHandler res (ctx, model)
      , Cmd.none
      )

    UpdateSettingsFinished res ->
      ( ( case res |> Result.toMaybe |> Maybe.andThen .updateSettingsResult of
            Just (Pb.UpdateSettingsResultOk userInfo) -> ctx |> updateCtx userInfo
            _ -> ctx
        , model |> Widget.handleUpdateSettingsResponse res
        )
      , Cmd.none
      )

main = Browser.element
  { init = init
  , update = update
  , view = \(ctx, model) -> Widget.view ctx model
  , subscriptions = \_ -> Sub.none
  }