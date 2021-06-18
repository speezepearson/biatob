module Widgets.TrustedUsersWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Dict as D

import Biatob.Proto.Mvp as Pb
import Utils

import Widgets.SmallInvitationWidget as SmallInvitationWidget
import Widgets.CopyWidget as CopyWidget
import API
import Time

type alias Config msg =
  { setState : State -> msg
  , setTrusted : State -> Pb.SetTrustedRequest -> msg
  , copy : String -> msg
  , auth : Pb.AuthToken
  , userInfo : Pb.GenericUserInfo
  , timeZone : Time.Zone
  , httpOrigin : String
  }
type alias State =
  { invitationWidget : SmallInvitationWidget.State
  , working : Bool
  , notification : Html Never
  }

init : State
init =
  { invitationWidget = SmallInvitationWidget.init
  , working = False
  , notification = H.text ""
  }

handleSetTrustedResponse : Result Http.Error Pb.SetTrustedResponse -> State -> State
handleSetTrustedResponse res state =
  { state | working = False
          , notification = case API.simplifySetTrustedResponse res of
              Ok _ -> H.text ""
              Err e -> Utils.redText e
  }

viewInvitation : Config msg -> String -> Pb.Invitation -> Html msg
viewInvitation config nonce invitation =
  case invitation.acceptedBy of
    "" ->
      H.li []
        [ CopyWidget.view config.copy (config.httpOrigin ++ Utils.invitationPath nonce)
        , H.text <| " (created " ++ Utils.dateStr config.timeZone (Utils.unixtimeToTime invitation.createdUnixtime) ++ ")"
        ]
    accepter ->
      H.li []
        [ H.text "Accepted by "
        , Utils.renderUser accepter
        , H.text <| " on " ++ Utils.dateStr config.timeZone (Utils.unixtimeToTime invitation.createdUnixtime)
        , H.text <| " (created " ++ Utils.dateStr config.timeZone (Utils.unixtimeToTime invitation.createdUnixtime) ++ ")"
        ]

view : Config msg -> State -> Html msg
view config state =
  H.div []
    [ state.notification |> H.map never
    , Utils.b "Your relationships: "
    , let relationships = config.userInfo |> .relationships |> Utils.mustMapValues in
      if D.isEmpty relationships then
        H.text "nobody yet!"
      else
        H.ul []
        <| List.map (\(u, rel) -> H.li []
            [ Utils.renderUser u
            , H.text ": "
            , if rel.trustedByYou then
                H.span []
                  [ H.text "trusted "
                  , H.button
                      [ HE.onClick (config.setTrusted {state | working=True, notification=H.text ""} {whoDepr=Nothing, who=u, trusted=False})
                      , HA.disabled state.working
                      ] [H.text "Remove trust"]
                  ]
              else
                H.text " untrusted"
            ])
        <| D.toList relationships
    ]
