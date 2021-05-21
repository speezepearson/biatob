port module Page.Program exposing (page)

import Browser
import Dict
import Http
import Time
import Json.Decode as JD
import Html as H
import Task

import Widgets.AuthWidget as AuthWidget
import Biatob.Proto.Mvp as Pb
import API
import Utils exposing (PredictionId, Username)
import Widgets.Navbar as Navbar
import Page exposing (..)

port pageCopy : String -> Cmd msg {- TODO(P3): delete the old Copy port -}
port navigate : Maybe String -> Cmd msg

type alias Model model =
  { globals : Globals
  , navbarAuth : AuthWidget.State
  , reloading : Bool
  , inner : model
  }

type Msg msg
  = Inner msg
  | RequestFinished Response msg
  | Tick Time.Posix
  | NavbarSetAuthWidget AuthWidget.State
  | NavbarLogInUsername AuthWidget.State Pb.LogInUsernameRequest
  | NavbarLogInUsernameFinished (Result Http.Error Pb.LogInUsernameResponse)
  | NavbarRegisterUsername AuthWidget.State Pb.RegisterUsernameRequest
  | NavbarRegisterUsernameFinished (Result Http.Error Pb.RegisterUsernameResponse)
  | NavbarSignOut AuthWidget.State Pb.SignOutRequest
  | NavbarSignOutFinished (Result Http.Error Pb.SignOutResponse)
  | Ignore

page : Element model msg -> Program JD.Value (Model model) (Msg msg)
page elem =
  let
    init : JD.Value -> ( Model model , Cmd (Msg msg) )
    init flags =
      let (inner, cmd) = elem.init flags in
      ( { globals = JD.decodeValue globalsDecoder flags |> Utils.mustResult "flags"
        , navbarAuth = AuthWidget.init
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
                  ( (Navbar.view
                      { setState = NavbarSetAuthWidget
                      , logInUsername = NavbarLogInUsername
                      , register = NavbarRegisterUsername
                      , signOut = NavbarSignOut
                      , ignore = Ignore
                      , auth = model.globals.authToken
                      }
                      model.navbarAuth
                    )
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
        NavbarSetAuthWidget widgetState ->
          ( { model | navbarAuth = widgetState } , Cmd.none )
        NavbarLogInUsername widgetState req ->
          ( { model | navbarAuth = widgetState }
          , API.postLogInUsername NavbarLogInUsernameFinished req
          )
        NavbarLogInUsernameFinished res ->
          case API.simplifyLogInUsernameResponse res of
            Ok _ -> ( { model | reloading = True } , navigate Nothing )
            Err _ ->
              ( { model | navbarAuth = model.navbarAuth |> AuthWidget.handleLogInUsernameResponse res }
              , Cmd.none
              )
        NavbarRegisterUsername widgetState req ->
          ( { model | navbarAuth = widgetState }
          , API.postRegisterUsername NavbarRegisterUsernameFinished req
          )
        NavbarRegisterUsernameFinished res ->
          case API.simplifyRegisterUsernameResponse res of
            Ok _ -> ( { model | reloading = True } , navigate Nothing )
            Err _ ->
              ( { model | navbarAuth = model.navbarAuth |> AuthWidget.handleRegisterUsernameResponse res }
              , Cmd.none
              )
        NavbarSignOut widgetState req ->
          ( { model | navbarAuth = widgetState }
          , API.postSignOut NavbarSignOutFinished req
          )
        NavbarSignOutFinished res ->
          case API.simplifySignOutResponse res of
            Ok _ -> ( { model | reloading = True } , navigate (Just "/") )
            Err _ ->
              ( { model | navbarAuth = model.navbarAuth |> AuthWidget.handleSignOutResponse res }
              , Cmd.none
              )
        Ignore ->
          ( model , Cmd.none )

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
    LogInUsernameResponse _ (Ok {logInUsernameResult}) -> case logInUsernameResult of
      Just (Pb.LogInUsernameResultOk _) -> True
      _ -> False
    RegisterUsernameResponse _ (Ok {registerUsernameResult}) -> case registerUsernameResult of
      Just (Pb.RegisterUsernameResultOk _) -> True
      _ -> False
    SignOutResponse _ (Ok _) -> True
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
    WhoamiRequest toMsg pbReq -> API.postWhoami (\res -> wrapResponse (WhoamiResponse pbReq res) (toMsg res)) pbReq
    SignOutRequest toMsg pbReq -> API.postSignOut (\res -> wrapResponse (SignOutResponse pbReq res) (toMsg res)) pbReq
    RegisterUsernameRequest toMsg pbReq -> API.postRegisterUsername (\res -> wrapResponse (RegisterUsernameResponse pbReq res) (toMsg res)) pbReq
    LogInUsernameRequest toMsg pbReq -> API.postLogInUsername (\res -> wrapResponse (LogInUsernameResponse pbReq res) (toMsg res)) pbReq
    CreatePredictionRequest toMsg pbReq -> API.postCreatePrediction (\res -> wrapResponse (CreatePredictionResponse pbReq res) (toMsg res)) pbReq
    GetPredictionRequest toMsg pbReq -> API.postGetPrediction (\res -> wrapResponse (GetPredictionResponse pbReq res) (toMsg res)) pbReq
    ListMyStakesRequest toMsg pbReq -> API.postListMyStakes (\res -> wrapResponse (ListMyStakesResponse pbReq res) (toMsg res)) pbReq
    ListPredictionsRequest toMsg pbReq -> API.postListPredictions (\res -> wrapResponse (ListPredictionsResponse pbReq res) (toMsg res)) pbReq
    StakeRequest toMsg pbReq -> API.postStake (\res -> wrapResponse (StakeResponse pbReq res) (toMsg res)) pbReq
    ResolveRequest toMsg pbReq -> API.postResolve (\res -> wrapResponse (ResolveResponse pbReq res) (toMsg res)) pbReq
    SetTrustedRequest toMsg pbReq -> API.postSetTrusted (\res -> wrapResponse (SetTrustedResponse pbReq res) (toMsg res)) pbReq
    GetUserRequest toMsg pbReq -> API.postGetUser (\res -> wrapResponse (GetUserResponse pbReq res) (toMsg res)) pbReq
    ChangePasswordRequest toMsg pbReq -> API.postChangePassword (\res -> wrapResponse (ChangePasswordResponse pbReq res) (toMsg res)) pbReq
    SetEmailRequest toMsg pbReq -> API.postSetEmail (\res -> wrapResponse (SetEmailResponse pbReq res) (toMsg res)) pbReq
    VerifyEmailRequest toMsg pbReq -> API.postVerifyEmail (\res -> wrapResponse (VerifyEmailResponse pbReq res) (toMsg res)) pbReq
    GetSettingsRequest toMsg pbReq -> API.postGetSettings (\res -> wrapResponse (GetSettingsResponse pbReq res) (toMsg res)) pbReq
    UpdateSettingsRequest toMsg pbReq -> API.postUpdateSettings (\res -> wrapResponse (UpdateSettingsResponse pbReq res) (toMsg res)) pbReq
    CreateInvitationRequest toMsg pbReq -> API.postCreateInvitation (\res -> wrapResponse (CreateInvitationResponse pbReq res) (toMsg res)) pbReq
    AcceptInvitationRequest toMsg pbReq -> API.postAcceptInvitation (\res -> wrapResponse (AcceptInvitationResponse pbReq res) (toMsg res)) pbReq

type Response
  = WhoamiResponse Pb.WhoamiRequest (Result Http.Error Pb.WhoamiResponse)
  | SignOutResponse Pb.SignOutRequest (Result Http.Error Pb.SignOutResponse)
  | RegisterUsernameResponse Pb.RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse)
  | LogInUsernameResponse Pb.LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse)
  | CreatePredictionResponse Pb.CreatePredictionRequest (Result Http.Error Pb.CreatePredictionResponse)
  | GetPredictionResponse Pb.GetPredictionRequest (Result Http.Error Pb.GetPredictionResponse)
  | ListMyStakesResponse Pb.ListMyStakesRequest (Result Http.Error Pb.ListMyStakesResponse)
  | ListPredictionsResponse Pb.ListPredictionsRequest (Result Http.Error Pb.ListPredictionsResponse)
  | StakeResponse Pb.StakeRequest (Result Http.Error Pb.StakeResponse)
  | ResolveResponse Pb.ResolveRequest (Result Http.Error Pb.ResolveResponse)
  | SetTrustedResponse Pb.SetTrustedRequest (Result Http.Error Pb.SetTrustedResponse)
  | GetUserResponse Pb.GetUserRequest (Result Http.Error Pb.GetUserResponse)
  | ChangePasswordResponse Pb.ChangePasswordRequest (Result Http.Error Pb.ChangePasswordResponse)
  | SetEmailResponse Pb.SetEmailRequest (Result Http.Error Pb.SetEmailResponse)
  | VerifyEmailResponse Pb.VerifyEmailRequest (Result Http.Error Pb.VerifyEmailResponse)
  | GetSettingsResponse Pb.GetSettingsRequest (Result Http.Error Pb.GetSettingsResponse)
  | UpdateSettingsResponse Pb.UpdateSettingsRequest (Result Http.Error Pb.UpdateSettingsResponse)
  | CreateInvitationResponse Pb.CreateInvitationRequest (Result Http.Error Pb.CreateInvitationResponse)
  | AcceptInvitationResponse Pb.AcceptInvitationRequest (Result Http.Error Pb.AcceptInvitationResponse)

updateGlobalsFromResponse : Response -> Globals -> Globals
updateGlobalsFromResponse resp globals =
  case resp of
    WhoamiResponse req res -> handleWhoamiResponse req res globals
    SignOutResponse req res -> handleSignOutResponse req res globals
    RegisterUsernameResponse req res -> handleRegisterUsernameResponse req res globals
    LogInUsernameResponse req res -> handleLogInUsernameResponse req res globals
    CreatePredictionResponse req res -> handleCreatePredictionResponse req res globals
    GetPredictionResponse req res -> handleGetPredictionResponse req res globals
    ListMyStakesResponse req res -> handleListMyStakesResponse req res globals
    ListPredictionsResponse req res -> handleListPredictionsResponse req res globals
    StakeResponse req res -> handleStakeResponse req res globals
    ResolveResponse req res -> handleResolveResponse req res globals
    SetTrustedResponse req res -> handleSetTrustedResponse req res globals
    GetUserResponse req res -> handleGetUserResponse req res globals
    ChangePasswordResponse req res -> handleChangePasswordResponse req res globals
    SetEmailResponse req res -> handleSetEmailResponse req res globals
    VerifyEmailResponse req res -> handleVerifyEmailResponse req res globals
    GetSettingsResponse req res -> handleGetSettingsResponse req res globals
    UpdateSettingsResponse req res -> handleUpdateSettingsResponse req res globals
    CreateInvitationResponse req res -> handleCreateInvitationResponse req res globals
    AcceptInvitationResponse req res -> handleAcceptInvitationResponse req res globals

addPrediction : PredictionId -> Pb.UserPredictionView -> ServerState -> ServerState
addPrediction predictionId prediction state =
  { state | predictions = state.predictions |> Dict.insert predictionId prediction }

addPredictions : Pb.PredictionsById -> ServerState -> ServerState
addPredictions predictions state =
  { state | predictions = state.predictions |> Dict.union (Utils.mustMapValues predictions.predictions) }

addRelationship : Username -> Pb.Relationship -> ServerState -> ServerState
addRelationship username relationship state =
  { state | settings = state.settings |> Maybe.map (\s -> { s | relationships = s.relationships |> Dict.insert username (Just relationship) }) }

updateUserInfo : (Pb.GenericUserInfo -> Pb.GenericUserInfo) -> Globals -> Globals
updateUserInfo f globals =
  { globals | serverState = globals.serverState |> \s -> {s | settings = s.settings |> Maybe.map f } }
