port module Page exposing
  ( Command(..)
  , Element
  , Globals
  , Request(..)
  , getAuth
  , getUserInfo
  , isLoggedIn
  , mapCmd
  , page
  )

import Browser
import Html as H exposing (Html)
import Json.Decode as JD
import Time
import Http
import Dict

import Biatob.Proto.Mvp as Pb
import API
import Utils

port pageCopy : String -> Cmd msg

main = H.text ""

type Command msg
  = NoCmd
  | BatchCmd (List (Command msg))
  | RequestCmd (Request msg)
  | CopyCmd String
  | MiscCmd (Cmd msg)

type alias Model model =
  { globals : Globals
  , inner : model
  }

type Msg msg
  = Inner msg
  | Tick Time.Posix
  | RequestFinished (Response msg)

type alias Element model msg =
  { init : JD.Value -> ( model , Command msg )
  , view : Globals -> model -> Browser.Document msg
  , update : msg -> model -> ( model , Command msg )
  , subscriptions : model -> Sub msg
  }

type alias Globals =
  { authState : Maybe Pb.AuthSuccess
  , now : Time.Posix
  , httpOrigin : String
  }

type Request msg
  = WhoamiRequest (Result Http.Error Pb.WhoamiResponse -> msg) Pb.WhoamiRequest
  | SignOutRequest (Result Http.Error Pb.SignOutResponse -> msg) Pb.SignOutRequest
  | RegisterUsernameRequest (Result Http.Error Pb.RegisterUsernameResponse -> msg) Pb.RegisterUsernameRequest
  | LogInUsernameRequest (Result Http.Error Pb.LogInUsernameResponse -> msg) Pb.LogInUsernameRequest
  | CreatePredictionRequest (Result Http.Error Pb.CreatePredictionResponse -> msg) Pb.CreatePredictionRequest
  | GetPredictionRequest (Result Http.Error Pb.GetPredictionResponse -> msg) Pb.GetPredictionRequest
  | ListMyStakesRequest (Result Http.Error Pb.ListMyStakesResponse -> msg) Pb.ListMyStakesRequest
  | ListPredictionsRequest (Result Http.Error Pb.ListPredictionsResponse -> msg) Pb.ListPredictionsRequest
  | StakeRequest (Result Http.Error Pb.StakeResponse -> msg) Pb.StakeRequest
  | ResolveRequest (Result Http.Error Pb.ResolveResponse -> msg) Pb.ResolveRequest
  | SetTrustedRequest (Result Http.Error Pb.SetTrustedResponse -> msg) Pb.SetTrustedRequest
  | GetUserRequest (Result Http.Error Pb.GetUserResponse -> msg) Pb.GetUserRequest
  | ChangePasswordRequest (Result Http.Error Pb.ChangePasswordResponse -> msg) Pb.ChangePasswordRequest
  | SetEmailRequest (Result Http.Error Pb.SetEmailResponse -> msg) Pb.SetEmailRequest
  | VerifyEmailRequest (Result Http.Error Pb.VerifyEmailResponse -> msg) Pb.VerifyEmailRequest
  | GetSettingsRequest (Result Http.Error Pb.GetSettingsResponse -> msg) Pb.GetSettingsRequest
  | UpdateSettingsRequest (Result Http.Error Pb.UpdateSettingsResponse -> msg) Pb.UpdateSettingsRequest
  | CreateInvitationRequest (Result Http.Error Pb.CreateInvitationResponse -> msg) Pb.CreateInvitationRequest
  | AcceptInvitationRequest (Result Http.Error Pb.AcceptInvitationResponse -> msg) Pb.AcceptInvitationRequest

type Response msg
  = WhoamiResponse (Result Http.Error Pb.WhoamiResponse) msg
  | SignOutResponse (Result Http.Error Pb.SignOutResponse) msg
  | RegisterUsernameResponse (Result Http.Error Pb.RegisterUsernameResponse) msg
  | LogInUsernameResponse (Result Http.Error Pb.LogInUsernameResponse) msg
  | CreatePredictionResponse (Result Http.Error Pb.CreatePredictionResponse) msg
  | GetPredictionResponse (Result Http.Error Pb.GetPredictionResponse) msg
  | ListMyStakesResponse (Result Http.Error Pb.ListMyStakesResponse) msg
  | ListPredictionsResponse (Result Http.Error Pb.ListPredictionsResponse) msg
  | StakeResponse (Result Http.Error Pb.StakeResponse) msg
  | ResolveResponse (Result Http.Error Pb.ResolveResponse) msg
  | SetTrustedResponse (Result Http.Error Pb.SetTrustedResponse) msg
  | GetUserResponse (Result Http.Error Pb.GetUserResponse) msg
  | ChangePasswordResponse (Result Http.Error Pb.ChangePasswordResponse) msg
  | SetEmailResponse (Result Http.Error Pb.SetEmailResponse) msg
  | VerifyEmailResponse (Result Http.Error Pb.VerifyEmailResponse) msg
  | GetSettingsResponse (Result Http.Error Pb.GetSettingsResponse) msg
  | UpdateSettingsResponse (Result Http.Error Pb.UpdateSettingsResponse) msg
  | CreateInvitationResponse (Result Http.Error Pb.CreateInvitationResponse) msg
  | AcceptInvitationResponse (Result Http.Error Pb.AcceptInvitationResponse) msg


page : Element model msg -> Program JD.Value (Model model) (Msg msg)
page elem = Browser.document
  { init = \flags ->
      let (inner, cmds) = elem.init flags in
      ( { globals = JD.decodeValue globalsDecoder flags |> Utils.mustResult "flags"
        , inner = inner
        }
      , toCmd cmds
      )
  , view = \model -> (elem.view model.globals model.inner |> \{title, body} -> {title=title, body=List.map (H.map Inner) body})
  , update = \msg model ->
      case Debug.log "page msg" msg of
        Inner innerMsg ->
          let (newInner, cmds) = elem.update innerMsg model.inner in
          ( { model | inner = newInner } , toCmd cmds )
        Tick now ->
          ( { model | globals = model.globals |> \g -> { g | now = now } } , Cmd.none )
        RequestFinished resp ->
          let (newInner, cmds) = elem.update (extractMsg resp) model.inner in
          ( { model | inner = newInner , globals = model.globals |> handleApiResponse resp }
          , toCmd cmds
          )
  , subscriptions = \model ->
      Sub.batch
        [ Time.every 1000 Tick
        , Sub.map Inner (elem.subscriptions model.inner)
        ]
  }

getUserInfo : Globals -> Maybe Pb.GenericUserInfo
getUserInfo globals =
  globals.authState |> Maybe.map Utils.mustAuthSuccessUserInfo

getAuth : Globals -> Maybe Pb.AuthToken
getAuth globals =
  globals.authState |> Maybe.map Utils.mustAuthSuccessToken

isLoggedIn : Globals -> Bool
isLoggedIn globals = globals.authState /= Nothing

mapCmd : (a -> b) -> Command a -> Command b
mapCmd f cmd =
  case cmd of
    RequestCmd req -> RequestCmd <| case req of
      WhoamiRequest toMsg pbReq -> WhoamiRequest (toMsg >> f) pbReq
      SignOutRequest toMsg pbReq -> SignOutRequest (toMsg >> f) pbReq
      RegisterUsernameRequest toMsg pbReq -> RegisterUsernameRequest (toMsg >> f) pbReq
      LogInUsernameRequest toMsg pbReq -> LogInUsernameRequest (toMsg >> f) pbReq
      CreatePredictionRequest toMsg pbReq -> CreatePredictionRequest (toMsg >> f) pbReq
      GetPredictionRequest toMsg pbReq -> GetPredictionRequest (toMsg >> f) pbReq
      ListMyStakesRequest toMsg pbReq -> ListMyStakesRequest (toMsg >> f) pbReq
      ListPredictionsRequest toMsg pbReq -> ListPredictionsRequest (toMsg >> f) pbReq
      StakeRequest toMsg pbReq -> StakeRequest (toMsg >> f) pbReq
      ResolveRequest toMsg pbReq -> ResolveRequest (toMsg >> f) pbReq
      SetTrustedRequest toMsg pbReq -> SetTrustedRequest (toMsg >> f) pbReq
      GetUserRequest toMsg pbReq -> GetUserRequest (toMsg >> f) pbReq
      ChangePasswordRequest toMsg pbReq -> ChangePasswordRequest (toMsg >> f) pbReq
      SetEmailRequest toMsg pbReq -> SetEmailRequest (toMsg >> f) pbReq
      VerifyEmailRequest toMsg pbReq -> VerifyEmailRequest (toMsg >> f) pbReq
      GetSettingsRequest toMsg pbReq -> GetSettingsRequest (toMsg >> f) pbReq
      UpdateSettingsRequest toMsg pbReq -> UpdateSettingsRequest (toMsg >> f) pbReq
      CreateInvitationRequest toMsg pbReq -> CreateInvitationRequest (toMsg >> f) pbReq
      AcceptInvitationRequest toMsg pbReq -> AcceptInvitationRequest (toMsg >> f) pbReq
    CopyCmd s -> CopyCmd s
    MiscCmd c -> MiscCmd <| Cmd.map f c
    NoCmd -> NoCmd
    BatchCmd cs -> BatchCmd <| List.map (mapCmd f) cs




toCmd : Command msg -> Cmd (Msg msg)
toCmd cmd =
  case cmd of
    RequestCmd req -> fire req
    CopyCmd s -> pageCopy s
    MiscCmd c -> Cmd.map Inner c
    NoCmd -> Cmd.none
    BatchCmd cs -> Cmd.batch <| List.map toCmd cs

handleApiResponse : Response a -> Globals -> Globals
handleApiResponse resp globals =
  case resp of
    WhoamiResponse _ _ -> globals
    SignOutResponse res _ -> case res of
      Ok _ -> { globals | authState = Nothing }
      Err _ -> globals
    RegisterUsernameResponse res _ -> case res of
      Ok {registerUsernameResult} -> case registerUsernameResult of
        Just (Pb.RegisterUsernameResultOk authSuccess) -> { globals | authState = Just authSuccess }
        _ -> globals
      Err _ -> globals
    LogInUsernameResponse res _ -> case res of
      Ok {logInUsernameResult} -> case logInUsernameResult of
        Just (Pb.LogInUsernameResultOk authSuccess) -> { globals | authState = Just authSuccess }
        _ -> globals
      Err _ -> globals
    CreatePredictionResponse _ _ -> globals
    GetPredictionResponse _ _ -> globals
    ListMyStakesResponse _ _ -> globals
    ListPredictionsResponse _ _ -> globals
    StakeResponse _ _ -> globals
    ResolveResponse _ _ -> globals
    SetTrustedResponse res _ -> case res of
      Ok {setTrustedResult} -> case setTrustedResult of
        Just (Pb.SetTrustedResultOk userInfo) -> globals |> updateUserInfo (\_ -> userInfo)
        _ -> globals
      Err _ -> globals
    GetUserResponse _ _ -> globals
    ChangePasswordResponse _ _ -> globals
    SetEmailResponse res _ -> case res of
      Ok {setEmailResult} -> case setEmailResult of
        Just (Pb.SetEmailResultOk email) -> globals |> updateUserInfo (\u -> { u | email = Just email })
        _ -> globals
      Err _ -> globals
    VerifyEmailResponse res _ -> case res of
      Ok {verifyEmailResult} -> case verifyEmailResult of
        Just (Pb.VerifyEmailResultOk email) -> globals |> updateUserInfo (\u -> { u | email = Just email })
        _ -> globals
      Err _ -> globals
    GetSettingsResponse res _ -> case res of
      Ok {getSettingsResult} -> case getSettingsResult of
        Just (Pb.GetSettingsResultOkUsername newInfo) -> globals |> updateUserInfo (always (newInfo |> Utils.mustUsernameGenericInfo))
        _ -> globals
      Err _ -> globals
    UpdateSettingsResponse res _ -> case res of
      Ok {updateSettingsResult} -> case updateSettingsResult of
        Just (Pb.UpdateSettingsResultOk newInfo) -> globals |> updateUserInfo (always newInfo)
        _ -> globals
      Err _ -> globals
    CreateInvitationResponse res _ -> case res of
      Ok {createInvitationResult} -> case createInvitationResult of
        Just (Pb.CreateInvitationResultOk result) -> globals |> updateUserInfo (\_ -> Utils.must "TODO" result.userInfo)
        _ -> globals
      Err _ -> globals
    AcceptInvitationResponse res _ -> case res of
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

extractMsg : Response msg -> msg
extractMsg resp = case resp of
  WhoamiResponse _ msg -> msg
  SignOutResponse _ msg -> msg
  RegisterUsernameResponse _ msg -> msg
  LogInUsernameResponse _ msg -> msg
  CreatePredictionResponse _ msg -> msg
  GetPredictionResponse _ msg -> msg
  ListMyStakesResponse _ msg -> msg
  ListPredictionsResponse _ msg -> msg
  StakeResponse _ msg -> msg
  ResolveResponse _ msg -> msg
  SetTrustedResponse _ msg -> msg
  GetUserResponse _ msg -> msg
  ChangePasswordResponse _ msg -> msg
  SetEmailResponse _ msg -> msg
  VerifyEmailResponse _ msg -> msg
  GetSettingsResponse _ msg -> msg
  UpdateSettingsResponse _ msg -> msg
  CreateInvitationResponse _ msg -> msg
  AcceptInvitationResponse _ msg -> msg

fire : Request msg -> Cmd (Msg msg)
fire req =
  case req of
    WhoamiRequest toMsg pbReq -> API.postWhoami (\res -> RequestFinished <| WhoamiResponse res (toMsg res)) pbReq
    SignOutRequest toMsg pbReq -> API.postSignOut (\res -> RequestFinished <| SignOutResponse res (toMsg res)) pbReq
    RegisterUsernameRequest toMsg pbReq -> API.postRegisterUsername (\res -> RequestFinished <| RegisterUsernameResponse res (toMsg res)) pbReq
    LogInUsernameRequest toMsg pbReq -> API.postLogInUsername (\res -> RequestFinished <| LogInUsernameResponse res (toMsg res)) pbReq
    CreatePredictionRequest toMsg pbReq -> API.postCreatePrediction (\res -> RequestFinished <| CreatePredictionResponse res (toMsg res)) pbReq
    GetPredictionRequest toMsg pbReq -> API.postGetPrediction (\res -> RequestFinished <| GetPredictionResponse res (toMsg res)) pbReq
    ListMyStakesRequest toMsg pbReq -> API.postListMyStakes (\res -> RequestFinished <| ListMyStakesResponse res (toMsg res)) pbReq
    ListPredictionsRequest toMsg pbReq -> API.postListPredictions (\res -> RequestFinished <| ListPredictionsResponse res (toMsg res)) pbReq
    StakeRequest toMsg pbReq -> API.postStake (\res -> RequestFinished <| StakeResponse res (toMsg res)) pbReq
    ResolveRequest toMsg pbReq -> API.postResolve (\res -> RequestFinished <| ResolveResponse res (toMsg res)) pbReq
    SetTrustedRequest toMsg pbReq -> API.postSetTrusted (\res -> RequestFinished <| SetTrustedResponse res (toMsg res)) pbReq
    GetUserRequest toMsg pbReq -> API.postGetUser (\res -> RequestFinished <| GetUserResponse res (toMsg res)) pbReq
    ChangePasswordRequest toMsg pbReq -> API.postChangePassword (\res -> RequestFinished <| ChangePasswordResponse res (toMsg res)) pbReq
    SetEmailRequest toMsg pbReq -> API.postSetEmail (\res -> RequestFinished <| SetEmailResponse res (toMsg res)) pbReq
    VerifyEmailRequest toMsg pbReq -> API.postVerifyEmail (\res -> RequestFinished <| VerifyEmailResponse res (toMsg res)) pbReq
    GetSettingsRequest toMsg pbReq -> API.postGetSettings (\res -> RequestFinished <| GetSettingsResponse res (toMsg res)) pbReq
    UpdateSettingsRequest toMsg pbReq -> API.postUpdateSettings (\res -> RequestFinished <| UpdateSettingsResponse res (toMsg res)) pbReq
    CreateInvitationRequest toMsg pbReq -> API.postCreateInvitation (\res -> RequestFinished <| CreateInvitationResponse res (toMsg res)) pbReq
    AcceptInvitationRequest toMsg pbReq -> API.postAcceptInvitation (\res -> RequestFinished <| AcceptInvitationResponse res (toMsg res)) pbReq
