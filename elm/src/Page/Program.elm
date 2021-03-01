port module Page.Program exposing (page)

import Browser
import Http
import Time
import Json.Decode as JD
import Html as H exposing (Html)
import Html.Attributes as HA
import Task

import Biatob.Proto.Mvp as Pb
import API
import Utils
import Widgets.Navbar as Navbar
import Page exposing (..)

port pageCopy : String -> Cmd msg {- TODO(P3): delete the old Copy port -}
port navigate : Maybe String -> Cmd msg

type alias Model model =
  { globals : Globals
  , navbar : Navbar.Model
  , reloading : Bool
  , inner : model
  }

type Msg msg
  = Inner msg
  | RequestFinished Response msg
  | NavbarMsg Navbar.Msg
  | NavbarRequestFinished Response Navbar.Msg
  | Tick Time.Posix

page : Element model msg -> Program JD.Value (Model model) (Msg msg)
page elem =
  let
    init : JD.Value -> ( Model model , Cmd (Msg msg) )
    init flags =
      let (inner, cmd) = elem.init flags in
      ( { globals = JD.decodeValue globalsDecoder flags |> Utils.mustResult "flags"
        , navbar = Navbar.init
        , reloading = False
        , inner = inner
        }
      , Cmd.batch [Task.perform Tick Time.now, toCmd RequestFinished Inner cmd]
      )

    view : Model model -> Browser.Document (Msg msg)
    view model =
      elem.view model.globals model.inner
      |> \{title, body} ->
            { title = title
            , body =
                if model.reloading then
                  [H.text "Reloading..."]
                else
                  ( (Navbar.view model.globals model.navbar |> H.map NavbarMsg)
                    :: List.map (H.map Inner) body)
            }

    update : Msg msg -> Model model -> ( Model model , Cmd (Msg msg) )
    update msg model =
      case msg of
        Inner innerMsg ->
          let (newInner, cmd) = elem.update innerMsg model.inner in
          ( { model | inner = newInner } , toCmd RequestFinished Inner cmd )
        Tick now ->
          ( { model | globals = model.globals |> \g -> { g | now = now } } , Cmd.none )
        RequestFinished resp innerMsg ->
          if didAuthChange resp then
            ( {model|reloading=True} , navigate Nothing )
          else
            let (newInner, cmd) = elem.update innerMsg model.inner in
            ( { model | inner = newInner , globals = model.globals |> updateGlobalsFromResponse resp }
            , toCmd RequestFinished Inner cmd
            )
        NavbarMsg widgetMsg ->
          let (newWidget, widgetCmd) = Navbar.update widgetMsg model.navbar in
          ( { model | navbar = newWidget } , toCmd NavbarRequestFinished NavbarMsg widgetCmd )
        NavbarRequestFinished resp widgetMsg ->
          if didAuthChange resp then
            ( {model|reloading=True} , navigate Nothing )
          else
            let (newWidget, widgetCmd) = Navbar.update widgetMsg model.navbar in
            ( { model | navbar = newWidget , globals = model.globals |> updateGlobalsFromResponse resp }
            , toCmd NavbarRequestFinished NavbarMsg widgetCmd
            )

    subscriptions : Model model -> Sub (Msg msg)
    subscriptions model =
      Sub.batch
        [ Time.every 1000 Tick
        , Sub.map Inner (elem.subscriptions model.inner)
        ]
  in
  Browser.document {init=init, view=view, update=update, subscriptions=subscriptions}

didAuthChange : Response -> Bool
didAuthChange resp =
  case resp of
    LogInUsernameResponse (Ok {logInUsernameResult}) -> case logInUsernameResult of
      Just (Pb.LogInUsernameResultOk _) -> True
      _ -> False
    RegisterUsernameResponse (Ok {registerUsernameResult}) -> case registerUsernameResult of
      Just (Pb.RegisterUsernameResultOk _) -> True
      _ -> False
    SignOutResponse (Ok _) -> True
    _ -> False

toCmd : (Response -> a -> Msg msg) -> (a -> Msg msg) -> Command a -> Cmd (Msg msg)
toCmd wrapResponse wrapMisc cmd =
  case cmd of
    RequestCmd req -> fire wrapResponse req
    CopyCmd s -> pageCopy s
    MiscCmd c -> Cmd.map wrapMisc c
    NoCmd -> Cmd.none
    BatchCmd cs -> Cmd.batch <| List.map (toCmd wrapResponse wrapMisc) cs
    NavigateCmd dest -> navigate dest

fire : (Response -> a -> Msg msg) -> Request a -> Cmd (Msg msg)
fire wrapResponse req =
  case req of
    WhoamiRequest toMsg pbReq -> API.postWhoami (\res -> wrapResponse (WhoamiResponse res) (toMsg res)) pbReq
    SignOutRequest toMsg pbReq -> API.postSignOut (\res -> wrapResponse (SignOutResponse res) (toMsg res)) pbReq
    RegisterUsernameRequest toMsg pbReq -> API.postRegisterUsername (\res -> wrapResponse (RegisterUsernameResponse res) (toMsg res)) pbReq
    LogInUsernameRequest toMsg pbReq -> API.postLogInUsername (\res -> wrapResponse (LogInUsernameResponse res) (toMsg res)) pbReq
    CreatePredictionRequest toMsg pbReq -> API.postCreatePrediction (\res -> wrapResponse (CreatePredictionResponse res) (toMsg res)) pbReq
    GetPredictionRequest toMsg pbReq -> API.postGetPrediction (\res -> wrapResponse (GetPredictionResponse res) (toMsg res)) pbReq
    ListMyStakesRequest toMsg pbReq -> API.postListMyStakes (\res -> wrapResponse (ListMyStakesResponse res) (toMsg res)) pbReq
    ListPredictionsRequest toMsg pbReq -> API.postListPredictions (\res -> wrapResponse (ListPredictionsResponse res) (toMsg res)) pbReq
    StakeRequest toMsg pbReq -> API.postStake (\res -> wrapResponse (StakeResponse res) (toMsg res)) pbReq
    ResolveRequest toMsg pbReq -> API.postResolve (\res -> wrapResponse (ResolveResponse res) (toMsg res)) pbReq
    SetTrustedRequest toMsg pbReq -> API.postSetTrusted (\res -> wrapResponse (SetTrustedResponse res) (toMsg res)) pbReq
    GetUserRequest toMsg pbReq -> API.postGetUser (\res -> wrapResponse (GetUserResponse res) (toMsg res)) pbReq
    ChangePasswordRequest toMsg pbReq -> API.postChangePassword (\res -> wrapResponse (ChangePasswordResponse res) (toMsg res)) pbReq
    SetEmailRequest toMsg pbReq -> API.postSetEmail (\res -> wrapResponse (SetEmailResponse res) (toMsg res)) pbReq
    VerifyEmailRequest toMsg pbReq -> API.postVerifyEmail (\res -> wrapResponse (VerifyEmailResponse res) (toMsg res)) pbReq
    GetSettingsRequest toMsg pbReq -> API.postGetSettings (\res -> wrapResponse (GetSettingsResponse res) (toMsg res)) pbReq
    UpdateSettingsRequest toMsg pbReq -> API.postUpdateSettings (\res -> wrapResponse (UpdateSettingsResponse res) (toMsg res)) pbReq
    CreateInvitationRequest toMsg pbReq -> API.postCreateInvitation (\res -> wrapResponse (CreateInvitationResponse res) (toMsg res)) pbReq
    AcceptInvitationRequest toMsg pbReq -> API.postAcceptInvitation (\res -> wrapResponse (AcceptInvitationResponse res) (toMsg res)) pbReq

type Response
  = WhoamiResponse (Result Http.Error Pb.WhoamiResponse)
  | SignOutResponse (Result Http.Error Pb.SignOutResponse)
  | RegisterUsernameResponse (Result Http.Error Pb.RegisterUsernameResponse)
  | LogInUsernameResponse (Result Http.Error Pb.LogInUsernameResponse)
  | CreatePredictionResponse (Result Http.Error Pb.CreatePredictionResponse)
  | GetPredictionResponse (Result Http.Error Pb.GetPredictionResponse)
  | ListMyStakesResponse (Result Http.Error Pb.ListMyStakesResponse)
  | ListPredictionsResponse (Result Http.Error Pb.ListPredictionsResponse)
  | StakeResponse (Result Http.Error Pb.StakeResponse)
  | ResolveResponse (Result Http.Error Pb.ResolveResponse)
  | SetTrustedResponse (Result Http.Error Pb.SetTrustedResponse)
  | GetUserResponse (Result Http.Error Pb.GetUserResponse)
  | ChangePasswordResponse (Result Http.Error Pb.ChangePasswordResponse)
  | SetEmailResponse (Result Http.Error Pb.SetEmailResponse)
  | VerifyEmailResponse (Result Http.Error Pb.VerifyEmailResponse)
  | GetSettingsResponse (Result Http.Error Pb.GetSettingsResponse)
  | UpdateSettingsResponse (Result Http.Error Pb.UpdateSettingsResponse)
  | CreateInvitationResponse (Result Http.Error Pb.CreateInvitationResponse)
  | AcceptInvitationResponse (Result Http.Error Pb.AcceptInvitationResponse)

updateGlobalsFromResponse : Response -> Globals -> Globals
updateGlobalsFromResponse resp globals =
  case resp of
    WhoamiResponse _ -> globals
    SignOutResponse res -> case res of
      Ok _ -> { globals | authState = Nothing }
      Err _ -> globals
    RegisterUsernameResponse res -> case res of
      Ok {registerUsernameResult} -> case registerUsernameResult of
        Just (Pb.RegisterUsernameResultOk authSuccess) -> { globals | authState = Just authSuccess }
        _ -> globals
      Err _ -> globals
    LogInUsernameResponse res -> case res of
      Ok {logInUsernameResult} -> case logInUsernameResult of
        Just (Pb.LogInUsernameResultOk authSuccess) -> { globals | authState = Just authSuccess }
        _ -> globals
      Err _ -> globals
    CreatePredictionResponse _ -> globals
    GetPredictionResponse _ -> globals
    ListMyStakesResponse _ -> globals
    ListPredictionsResponse _ -> globals
    StakeResponse _ -> globals
    ResolveResponse _ -> globals
    SetTrustedResponse res -> case res of
      Ok {setTrustedResult} -> case Debug.log "setTrustedResult" setTrustedResult of
        Just (Pb.SetTrustedResultOk userInfo) -> Debug.log "globals before update" globals |> updateUserInfo (\_ -> userInfo) |> Debug.log "globals after update"
        _ -> globals
      Err _ -> globals
    GetUserResponse _ -> globals
    ChangePasswordResponse _ -> globals
    SetEmailResponse res -> case res of
      Ok {setEmailResult} -> case setEmailResult of
        Just (Pb.SetEmailResultOk email) -> globals |> updateUserInfo (\u -> { u | email = Just email })
        _ -> globals
      Err _ -> globals
    VerifyEmailResponse res -> case res of
      Ok {verifyEmailResult} -> case verifyEmailResult of
        Just (Pb.VerifyEmailResultOk email) -> globals |> updateUserInfo (\u -> { u | email = Just email })
        _ -> globals
      Err _ -> globals
    GetSettingsResponse res -> case res of
      Ok {getSettingsResult} -> case getSettingsResult of
        Just (Pb.GetSettingsResultOkUsername newInfo) -> globals |> updateUserInfo (always (newInfo |> Utils.mustUsernameGenericInfo))
        _ -> globals
      Err _ -> globals
    UpdateSettingsResponse res -> case res of
      Ok {updateSettingsResult} -> case updateSettingsResult of
        Just (Pb.UpdateSettingsResultOk newInfo) -> globals |> updateUserInfo (always newInfo)
        _ -> globals
      Err _ -> globals
    CreateInvitationResponse res -> case res of
      Ok {createInvitationResult} -> case createInvitationResult of
        Just (Pb.CreateInvitationResultOk result) -> globals |> updateUserInfo (\_ -> Utils.must "TODO" result.userInfo)
        _ -> globals
      Err _ -> globals
    AcceptInvitationResponse res -> case res of
      Ok {acceptInvitationResult} -> case acceptInvitationResult of
        Just (Pb.AcceptInvitationResultOk userInfo) -> globals |> updateUserInfo (\_ -> userInfo)
        _ -> globals
      Err _ -> globals

globalsDecoder : JD.Decoder Globals
globalsDecoder =
  JD.map3 Globals
    (JD.field "authSuccessPbB64" <| JD.nullable <| Utils.pbB64Decoder Pb.authSuccessDecoder)
    (JD.field "initUnixtime" JD.float |> JD.map Utils.unixtimeToTime)
    (JD.field "httpOrigin" JD.string)

updateUserInfo : (Pb.GenericUserInfo -> Pb.GenericUserInfo) -> Globals -> Globals
updateUserInfo f globals =
  { globals | authState = globals.authState |> Maybe.map (\u -> { u | userInfo = u.userInfo |> Maybe.map f }) }
