port module Page.Program exposing (page)

import Browser
import Dict
import Http
import Time
import Json.Decode as JD
import Html as H
import Task

import Biatob.Proto.Mvp as Pb
import API
import Utils exposing (PredictionId, Username)
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
        , Sub.map NavbarMsg (Navbar.subscriptions model.navbar)
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
    WhoamiResponse _ _ -> globals
    SignOutResponse _ res -> case res of
      Ok _ -> { globals | authToken = Nothing , serverState = globals.serverState |> \s -> { s | settings = Nothing } }
      Err _ -> globals
    RegisterUsernameResponse _ res -> case res of
      Ok {registerUsernameResult} -> case registerUsernameResult of
        Just (Pb.RegisterUsernameResultOk authSuccess) -> { globals | authToken = Just (authSuccess |> Utils.mustAuthSuccessToken) , serverState = globals.serverState |> \s -> { s | settings = Just (Utils.mustAuthSuccessUserInfo authSuccess)} }
        _ -> globals
      Err _ -> globals
    LogInUsernameResponse _ res -> case res of
      Ok {logInUsernameResult} -> case logInUsernameResult of
        Just (Pb.LogInUsernameResultOk authSuccess) -> { globals | authToken = Just (authSuccess |> Utils.mustAuthSuccessToken) , serverState = globals.serverState |> \s -> { s | settings = Just (Utils.mustAuthSuccessUserInfo authSuccess)} }
        _ -> globals
      Err _ -> globals
    CreatePredictionResponse _ _ -> globals
    GetPredictionResponse req res -> case res of
      Ok {getPredictionResult} -> case getPredictionResult of
        Just (Pb.GetPredictionResultPrediction prediction) -> { globals | serverState = globals.serverState |> addPrediction req.predictionId prediction }
        _ -> globals
      Err _ -> globals
    ListMyStakesResponse {} res -> case res of
      Ok {listMyStakesResult} -> case listMyStakesResult of
        Just (Pb.ListMyStakesResultOk predictions) -> { globals | serverState = globals.serverState |> addPredictions predictions }
        _ -> globals
      Err _ -> globals
    ListPredictionsResponse _ res -> case res of
      Ok {listPredictionsResult} -> case listPredictionsResult of
        Just (Pb.ListPredictionsResultOk predictions) -> { globals | serverState = globals.serverState |> addPredictions predictions }
        _ -> globals
      Err _ -> globals
    StakeResponse req res -> case res of
      Ok {stakeResult} -> case Debug.log "stakeResult" stakeResult of
        Just (Pb.StakeResultOk newPrediction) -> { globals | serverState = globals.serverState |> addPrediction req.predictionId newPrediction }
        _ -> globals
      Err _ -> globals
    ResolveResponse req res -> case res of
      Ok {resolveResult} -> case Debug.log "resolveResult" resolveResult of
        Just (Pb.ResolveResultOk newPrediction) -> { globals | serverState = globals.serverState |> addPrediction req.predictionId newPrediction }
        _ -> globals
      Err _ -> globals
    SetTrustedResponse _ res -> case res of
      Ok {setTrustedResult} -> case Debug.log "setTrustedResult" setTrustedResult of
        Just (Pb.SetTrustedResultOk userInfo) -> Debug.log "globals before update" globals |> updateUserInfo (\_ -> userInfo) |> Debug.log "globals after update"
        _ -> globals
      Err _ -> globals
    GetUserResponse req res -> case res of
      Ok {getUserResult} -> case Debug.log "getUserResult" getUserResult of
        Just (Pb.GetUserResultOk relationship) -> { globals | serverState = globals.serverState |> addRelationship req.who relationship }
        _ -> globals
      Err _ -> globals
    ChangePasswordResponse _ _ -> globals
    SetEmailResponse _ res -> case res of
      Ok {setEmailResult} -> case setEmailResult of
        Just (Pb.SetEmailResultOk email) -> globals |> updateUserInfo (\u -> { u | email = Just email })
        _ -> globals
      Err _ -> globals
    VerifyEmailResponse _ res -> case res of
      Ok {verifyEmailResult} -> case verifyEmailResult of
        Just (Pb.VerifyEmailResultOk email) -> globals |> updateUserInfo (\u -> { u | email = Just email })
        _ -> globals
      Err _ -> globals
    GetSettingsResponse _ res -> case res of
      Ok {getSettingsResult} -> case getSettingsResult of
        Just (Pb.GetSettingsResultOk newInfo) -> globals |> updateUserInfo (always newInfo)
        _ -> globals
      Err _ -> globals
    UpdateSettingsResponse _ res -> case res of
      Ok {updateSettingsResult} -> case updateSettingsResult of
        Just (Pb.UpdateSettingsResultOk newInfo) -> globals |> updateUserInfo (always newInfo)
        _ -> globals
      Err _ -> globals
    CreateInvitationResponse _ res -> case res of
      Ok {createInvitationResult} -> case createInvitationResult of
        Just (Pb.CreateInvitationResultOk result) -> globals |> updateUserInfo (\_ -> Utils.must "TODO" result.userInfo)
        _ -> globals
      Err _ -> globals
    AcceptInvitationResponse _ res -> case res of
      Ok {acceptInvitationResult} -> case acceptInvitationResult of
        Just (Pb.AcceptInvitationResultOk userInfo) -> globals |> updateUserInfo (\_ -> userInfo)
        _ -> globals
      Err _ -> globals

addPrediction : PredictionId -> Pb.UserPredictionView -> ServerState -> ServerState
addPrediction predictionId prediction state =
  { state | predictions = state.predictions |> Dict.insert predictionId prediction }

addPredictions : Pb.PredictionsById -> ServerState -> ServerState
addPredictions predictions state =
  { state | predictions = state.predictions |> Dict.union (Utils.mustMapValues predictions.predictions) }

addRelationship : Username -> Pb.Relationship -> ServerState -> ServerState
addRelationship username relationship state =
  { state | settings = state.settings |> Maybe.map (\s -> { s | relationships = s.relationships |> Dict.insert username (Just relationship) }) }

globalsDecoder : JD.Decoder Globals
globalsDecoder =
  (JD.field "authSuccessPbB64" <| JD.nullable <| Utils.pbB64Decoder Pb.authSuccessDecoder) |> JD.andThen (\authSuccess ->
  (JD.maybe <| JD.field "predictionsPbB64" <| Utils.pbB64Decoder Pb.predictionsByIdDecoder) |> JD.map (Maybe.map .predictions >> Maybe.withDefault Dict.empty) |> JD.andThen (\predictions ->
  (JD.field "initUnixtime" JD.float |> JD.map Utils.unixtimeToTime) |> JD.andThen (\now ->
  (JD.field "timeZoneOffsetMinutes" JD.int |> JD.map (\n -> Time.customZone n [])) |> JD.andThen (\timeZone ->
  (JD.field "httpOrigin" JD.string) |> JD.andThen (\httpOrigin ->
    JD.succeed
      { authToken = Maybe.map Utils.mustAuthSuccessToken authSuccess
      , serverState =
          { settings = Maybe.map Utils.mustAuthSuccessUserInfo authSuccess
          , predictions = predictions |> Utils.mustMapValues
          }
      , now = now
      , timeZone = timeZone
      , httpOrigin = httpOrigin
      }
  )))))

updateUserInfo : (Pb.GenericUserInfo -> Pb.GenericUserInfo) -> Globals -> Globals
updateUserInfo f globals =
  { globals | serverState = globals.serverState |> \s -> {s | settings = s.settings |> Maybe.map f } }
