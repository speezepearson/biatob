port module Widgets.AuthWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Html exposing (s)

import Biatob.Proto.Mvp as Pb
import Utils
import Http

import Field exposing (Field)
import Set
import Field
import Page
import Field
import Page

port passwordManagerFilled : ({target:String, value:String} -> msg) -> Sub msg -- for password managers

type Msg
  = SetUsernameField String
  | SetPasswordField String
  | Ignore
  | LogInUsername
  | LogInUsernameFinished (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername
  | RegisterUsernameFinished (Result Http.Error Pb.RegisterUsernameResponse)
  | SignOut
  | SignOutFinished (Result Http.Error Pb.SignOutResponse)
type alias Model =
  { usernameField : Field () String
  , passwordField : Field () String
  , working : Bool
  , notification : Html Never
  }

illegalUsernameCharacters : String -> Set.Set Char
illegalUsernameCharacters s =
  let
    okayChars = ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" |> String.toList |> Set.fromList)
    presentChars = s |> String.toList |> Set.fromList
  in
    Set.diff presentChars okayChars

init : Model
init =
  { usernameField = Field.okIfEmpty <| Field.init "" <| \() s ->
      if s=="" then
        Err ""
      else let badChars = illegalUsernameCharacters s in
      if not (Set.isEmpty badChars) then
        Err ("bad characters: " ++ Debug.toString (Set.toList badChars))
      else
        Ok s
  , passwordField = Field.okIfEmpty <| Field.init "" <| \() s ->
      if s=="" then
        Err ""
      else if String.length s > 256 then
        Err "must not be over 256 characters, good grief"
      else
        Ok s
  , working = False
  , notification = H.text ""
  }

view : Page.Globals -> Model -> Html Msg
view globals model =
  case Page.getAuth globals of
    Nothing ->
      let
        disableButtons = case (Field.parse () model.usernameField, Field.parse () model.passwordField) of
          (Ok _, Ok _) -> False
          _ -> True
      in
      H.div []
        [ Field.inputFor SetUsernameField () model.usernameField
            H.input
            [ HA.disabled model.working
            , HA.style "width" "8em"
            , HA.type_ "text"
            , HA.placeholder "username"
            , HA.class "username-field"
            , HA.class "watch-for-password-manager-fill"
            , HA.attribute "data-password-manager-target" "username"
            ] []
        , Field.inputFor SetPasswordField () model.passwordField
            H.input
            [ HA.disabled model.working
            , HA.style "width" "8em"
            , HA.type_ "password"
            , HA.placeholder "password"
            , HA.class "watch-for-password-manager-fill"
            , HA.attribute "data-password-manager-target" "password"
            , Utils.onEnter LogInUsername Ignore
            ] []
        , H.button
            [ HA.disabled <| model.working || disableButtons
            , HE.onClick LogInUsername
            ]
            [H.text "Log in"]
        , H.text " or "
        , H.button
            [ HA.disabled <| model.working || disableButtons
            , HE.onClick RegisterUsername
            ]
            [H.text "Sign up"]
        , model.notification |> H.map never
        ]
    Just auth ->
      H.div []
        [ H.text <| "Signed in as "
        , Utils.renderUser <| Utils.mustTokenOwner auth
        , H.text " "
        , H.button [HA.disabled model.working, HE.onClick SignOut] [H.text "Sign out"]
        , model.notification |> H.map never
        ]

update : Msg -> Model -> ( Model , Page.Command Msg )
update msg model =
  case msg of
    SetUsernameField s -> ( { model | usernameField = model.usernameField |> Field.setStr s } , Page.NoCmd )
    SetPasswordField s -> ( { model | passwordField = model.passwordField |> Field.setStr s } , Page.NoCmd )
    LogInUsername ->
      case (Field.parse () model.usernameField, Field.parse () model.passwordField) of
        (Ok username, Ok password) ->
          ( { model | working = True , notification = H.text "" }
          , Page.RequestCmd <| Page.LogInUsernameRequest LogInUsernameFinished {username=username, password=password}
          )
        _ ->
          ( model
          , Page.NoCmd
          )
    LogInUsernameFinished res ->
      ( case res of
          Err e -> { model | working = False , notification = Utils.redText (Debug.toString e)}
          Ok resp ->
            case resp.logInUsernameResult of
              Just (Pb.LogInUsernameResultOk _) ->
                { model | working = False , notification = H.text "" }
              Just (Pb.LogInUsernameResultError e) ->
                { model | working = False , notification = Utils.redText (Debug.toString e) }
              Nothing ->
                { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
      , Page.NoCmd
      )

    RegisterUsername ->
      case (Field.parse () model.usernameField, Field.parse () model.passwordField) of
        (Ok username, Ok password) ->
          ( { model | working = True , notification = H.text "" }
          , Page.RequestCmd <| Page.RegisterUsernameRequest RegisterUsernameFinished {username=username, password=password}
          )
        _ ->
          ( model
          , Page.NoCmd
          )
    RegisterUsernameFinished res ->
      ( case res of
          Err e -> { model | working = False , notification = Utils.redText (Debug.toString e)}
          Ok resp ->
            case resp.registerUsernameResult of
              Just (Pb.RegisterUsernameResultOk _) ->
                { model | working = False , notification = H.text "" }
              Just (Pb.RegisterUsernameResultError e) ->
                { model | working = False , notification = Utils.redText (Debug.toString e) }
              Nothing ->
                { model | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }
      , Page.NoCmd
      )
    SignOut ->
      ( { model | working = True , notification = H.text "" }
      , Page.RequestCmd <| Page.SignOutRequest SignOutFinished {}
      )
    SignOutFinished res ->
      ( case res of
          Err e -> { model | working = False , notification = Utils.redText (Debug.toString e)}
          Ok _ -> { model | working = False , notification = H.text "" }
      , Page.NoCmd
      )

    Ignore -> ( model , Page.NoCmd )

subscriptions : Model -> Sub Msg
subscriptions _ =
  passwordManagerFilled (\event -> case (Debug.log "event" event).target of
    "username" -> SetUsernameField event.value
    "password" -> SetPasswordField event.value
    _ -> Ignore
  )
