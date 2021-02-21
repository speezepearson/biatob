module Widgets.SmallInvitationWidget exposing (..)

import Browser

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http

import Biatob.Proto.Mvp as Pb
import Utils

import Utils
import Widgets.CopyWidget as CopyWidget

type Event = Copy String | CreateInvitation
type alias Context msg =
  { httpOrigin : String
  , destination : Maybe String
  , handle : Maybe Event -> State -> msg
  }
type alias State =
  { invitationId : Maybe Pb.InvitationId
  , working : Bool
  , notification : Html ()
  }

handleCreateInvitationResponse : Result Http.Error Pb.CreateInvitationResponse -> State -> State
handleCreateInvitationResponse res state =
  case res of
    Err e ->
      { state | working = False , notification = Utils.redText (Debug.toString e) }
    Ok resp ->
      case resp.createInvitationResult of
        Just (Pb.CreateInvitationResultOk result) ->
          { state | working = False
                  , notification = H.text ""
                  , invitationId = Just result
          }
        Just (Pb.CreateInvitationResultError e) ->
          { state | working = False , notification = Utils.redText (Debug.toString e) }
        Nothing ->
          { state | working = False , notification = Utils.redText "Invalid server response (neither Ok nor Error in protobuf)" }

setInvitation : Maybe Pb.InvitationId -> State -> State
setInvitation inv state = { state | invitationId = inv }

init : State
init =
  { invitationId = Nothing
  , working = False
  , notification = H.text ""
  }

view : Context msg -> State -> Html msg
view ctx state =
  let
    help : Html msg
    help =
      H.details [HA.style "display" "inline", HA.style "outline" "1px solid #cccccc"]
        [ H.summary [] [H.text "?"]
        , H.text <|
            "An invitation link is a one-time-use code that you send to people you trust, in order to let Biatob know you trust them."
            ++ " The intended use is: you create an invitation; you send it to somebody you trust;"
            ++ " they click the link; and from then on, Biatob knows you trust each other."
        ]
  in
  H.span []
    [ case state.invitationId of
        Nothing -> H.text ""
        Just id ->
          CopyWidget.view (\s -> ctx.handle (Just <| Copy s) state) (ctx.httpOrigin ++ Utils.invitationPath id ++ case ctx.destination of
             Just d -> "?dest="++d
             Nothing -> "" )
    , H.button
        [ HA.disabled state.working
        , HE.onClick (ctx.handle (Just CreateInvitation) { state | working = True , notification = H.text "" })
        ]
        [ H.text <| if state.working then "Creating..." else if state.invitationId == Nothing then "Create invitation" else "Create another"
        ]
    , H.text " "
    , state.notification |> H.map (\_ -> ctx.handle Nothing state)
    , H.text " "
    , help
    ]

