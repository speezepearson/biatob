port module Elements.LogInWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE

import Biatob.Proto.Mvp as Pb
import Utils exposing (WorkingState(..))
import Http

import Field exposing (Field)
import Set
import Field
import API
import Browser

port loggedIn : () -> Cmd msg
port passwordManagerFilled : ({target:String, value:String} -> msg) -> Sub msg

type Msg
  = SetUsernameField String
  | SetPasswordField String
  | Ignore
  | LogInUsername
  | LogInUsernameFinished (Result Http.Error Pb.LogInUsernameResponse)
  | RegisterUsername
  | RegisterUsernameFinished (Result Http.Error Pb.RegisterUsernameResponse)

type alias Model =
  { usernameField : Field () String
  , passwordField : Field () String
  , working : WorkingState
  }

illegalUsernameCharacters : String -> Set.Set Char
illegalUsernameCharacters s =
  let
    okayChars = ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" |> String.toList |> Set.fromList)
    presentChars = s |> String.toList |> Set.fromList
  in
    Set.diff presentChars okayChars

init : () -> (Model, Cmd Msg)
init () =
  ( { usernameField = Field.okIfEmpty <| Field.init "" <| \() s ->
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
    , working = Awaiting { notification=H.text "" }
    }
  , Cmd.none
  )

view : Model -> Html Msg
view model =
  let
    disableInputs = case model.working of
      Awaiting _ -> False
      Working -> True
      Done -> True
    disableButtons = disableInputs || case (Field.parse () model.usernameField, Field.parse () model.passwordField) of
      (Ok _, Ok _) -> False
      _ -> True
  in
  H.div []
    [ Field.inputFor SetUsernameField () model.usernameField
        H.input
        [ HA.disabled disableInputs
        , HA.style "width" "8em"
        , HA.type_ "text"
        , HA.placeholder "username"
        , HA.class "username-field"
        , HA.class "watch-for-password-manager-fill"
        , HA.attribute "data-password-manager-target" "username"
        , HA.attribute "data-elm-value" model.usernameField.string
        ] []
    , Field.inputFor SetPasswordField () model.passwordField
        H.input
        [ HA.disabled disableInputs
        , HA.style "width" "8em"
        , HA.type_ "password"
        , HA.placeholder "password"
        , HA.class "watch-for-password-manager-fill"
        , HA.attribute "data-password-manager-target" "password"
        , HA.attribute "data-elm-value" model.usernameField.string
        , Utils.onEnter LogInUsername Ignore
        ] []
    , H.button
        [ HA.disabled <| disableButtons
        , HE.onClick LogInUsername
        ]
        [H.text "Log in"]
    , H.text " or "
    , H.button
        [ HA.disabled <| disableButtons
        , HE.onClick RegisterUsername
        ]
        [H.text "Sign up"]
    , case model.working of
        Awaiting {notification} -> notification |> H.map never
        Working -> H.text ""
        Done -> H.text "Logged in..."
    ]

update : Msg -> Model -> ( Model , Cmd Msg )
update msg model =
  case msg of
    SetUsernameField s -> ( { model | usernameField = model.usernameField |> Field.setStr s } , Cmd.none )
    SetPasswordField s -> ( { model | passwordField = model.passwordField |> Field.setStr s } , Cmd.none )
    LogInUsername ->
      case (Field.parse () model.usernameField, Field.parse () model.passwordField) of
        (Ok username, Ok password) ->
          ( { model | working = Working }
          , API.postLogInUsername LogInUsernameFinished {username=username, password=password}
          )
        _ ->
          ( model
          , Cmd.none
          )
    LogInUsernameFinished res ->
      case res of
        Err e ->
          ( { model | working = Awaiting { notification = Utils.redText (Debug.toString e) } }
          , Cmd.none
          )
        Ok resp ->
          case resp.logInUsernameResult of
            Just (Pb.LogInUsernameResultOk _) ->
              ( { model | working = Done }
              , loggedIn ()
              )
            Just (Pb.LogInUsernameResultError e) ->
              ( { model | working = Awaiting { notification = Utils.redText (Debug.toString e) } }
              , Cmd.none
              )
            Nothing ->
              ( { model | working = Awaiting { notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" } }
              , Cmd.none
              )

    RegisterUsername ->
      case (Field.parse () model.usernameField, Field.parse () model.passwordField) of
        (Ok username, Ok password) ->
          ( { model | working = Working }
          , API.postRegisterUsername RegisterUsernameFinished {username=username, password=password}
          )
        _ ->
          ( model
          , Cmd.none
          )
    RegisterUsernameFinished res ->
      case res of
          Err e ->
            ( { model | working = Awaiting { notification = Utils.redText (Debug.toString e)} }
            , Cmd.none
            )
          Ok resp ->
            case resp.registerUsernameResult of
              Just (Pb.RegisterUsernameResultOk _) ->
                ( { model | working = Done }
                , loggedIn ()
                )
              Just (Pb.RegisterUsernameResultError e) ->
                ( { model | working = Awaiting { notification = Utils.redText (Debug.toString e) } }
                , Cmd.none
                )
              Nothing ->
                ( { model | working = Awaiting { notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" } }
                , Cmd.none
                )

    Ignore -> ( model , Cmd.none )

subscriptions : Model -> Sub Msg
subscriptions _ =
  passwordManagerFilled (\event -> case (Debug.log "Password manager or something changed auth fields" event).target of
    "username" -> SetUsernameField event.value
    "password" -> SetPasswordField event.value
    _ -> Ignore
  )

main =
  Browser.element {init=init, view=view, update=update, subscriptions=subscriptions}
