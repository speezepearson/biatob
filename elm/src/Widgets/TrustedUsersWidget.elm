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

view : Config msg -> State -> Html msg
view config state =
  H.div [HA.class "row"]
    [ state.notification |> H.map never
    , Utils.b "Your relationships: "
    , H.div [HA.class "col-md-8"] <| List.singleton <| let relationships = config.userInfo |> .relationships |> Utils.mustMapValues in
      if D.isEmpty relationships then
        H.text "nobody yet!"
      else
        H.table [HA.class "table table-sm"]
        [ H.thead [] <| List.singleton <| H.tr []
          [ H.th [HA.scope "col", HA.class "col-1"] [H.text "Username"]
          , H.th [HA.scope "col", HA.class "col-1"] [H.text "Status"]
          , H.th [HA.scope "col", HA.class "col-1"] [H.text "Actions"]
          ]
        , D.toList relationships
          |> List.map (\(u, rel) -> H.tr []
            [ H.td [] [Utils.renderUser u]
            , H.td [] [H.text <| if rel.trustedByYou then "trusted" else "untrusted"]
            , H.td []
              [ if rel.trustedByYou then
                  H.button
                  [ HE.onClick (config.setTrusted {state | working=True, notification=H.text ""} {whoDepr=Nothing, who=u, trusted=False})
                  , HA.disabled state.working
                  , HA.class "btn btn-sm btn-outline-primary"
                  ] [H.text "Mark untrusted"]
                else
                  H.button
                  [ HE.onClick (config.setTrusted {state | working=True, notification=H.text ""} {whoDepr=Nothing, who=u, trusted=True})
                  , HA.disabled state.working
                  , HA.class "btn btn-sm btn-outline-primary"
                  ] [H.text "Mark trusted"]
              ]
            ])
          |> H.tbody []
        ]
    ]
