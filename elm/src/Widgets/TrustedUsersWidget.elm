module Widgets.TrustedUsersWidget exposing (..)

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Dict as D

import Biatob.Proto.Mvp as Pb
import Utils

import API
import Time
import Utils exposing (Username)

type alias Config msg =
  { setState : State -> msg
  , setTrusted : State -> Pb.SetTrustedRequest -> msg
  , copy : String -> msg
  , userInfo : Pb.GenericUserInfo
  , timeZone : Time.Zone
  , httpOrigin : String
  }
type alias State =
  { setTrustedRequestStatuses : D.Dict Username SetTrustedRequestStatus
  }

type SetTrustedRequestStatus = AwaitingResponse | Succeeded | Failed String

init : State
init =
  { setTrustedRequestStatuses = D.empty
  }

handleSetTrustedResponse : Username -> Result Http.Error Pb.SetTrustedResponse -> State -> State
handleSetTrustedResponse who res state =
    { state | setTrustedRequestStatuses = state.setTrustedRequestStatuses |> D.update who (Maybe.map (always <| case API.simplifySetTrustedResponse res of
                Ok _ -> Succeeded
                Err e -> Failed e
              ))
    }

view : Config msg -> State -> Html msg
view config state =
  H.div [HA.class "row"]
    [ Utils.b "Your relationships: "
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
                  [ HE.onClick (config.setTrusted {state | setTrustedRequestStatuses = state.setTrustedRequestStatuses |> D.insert u AwaitingResponse} {who=u, trusted=False})
                  , HA.disabled <| D.get u state.setTrustedRequestStatuses == Just AwaitingResponse
                  , HA.class "btn btn-sm py-0 btn-outline-primary"
                  ] [H.text "Mark untrusted"]
                else
                  H.button
                  [ HE.onClick (config.setTrusted {state | setTrustedRequestStatuses = state.setTrustedRequestStatuses |> D.insert u AwaitingResponse} {who=u, trusted=True})
                  , HA.disabled <| D.get u state.setTrustedRequestStatuses == Just AwaitingResponse
                  , HA.class "btn btn-sm py-0 btn-outline-primary"
                  ] [H.text "Mark trusted"]
              , H.text " "
              , case D.get u state.setTrustedRequestStatuses of
                  Nothing -> H.text ""
                  Just AwaitingResponse -> H.text ""
                  Just Succeeded -> Utils.greenText <| if rel.trustedByYou then "Marked trusted!" else "Marked untrusted!"
                  Just (Failed e) -> Utils.redText e
              ]
            ])
          |> H.tbody []
        ]
    ]
