module SmallInvitationWidget exposing (..)

import Browser

import Html as H exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Decode as JD

import Biatob.Proto.Mvp as Pb
import Utils

import Utils
import CopyWidget
import API

type alias Context msg =
  { httpOrigin : String
  , createInvitation : msg
  , copy : String -> msg
  , nevermind : msg
  , destination : Maybe String
  }
type alias Model =
  { invitationId : Maybe Pb.InvitationId
  , working : Bool
  , notification : Html ()
  }

setWorking : Model -> Model
setWorking model = { model | working = True , notification = H.text "" }
doneWorking : Html () -> Model -> Model
doneWorking notification model = { model | working = False , notification = notification }
setInvitation : Maybe Pb.InvitationId -> Model -> Model
setInvitation inv model = { model | invitationId = inv }

init : Model
init =
  { invitationId = Nothing
  , working = False
  , notification = H.text ""
  }

view : Context msg -> Model -> Html msg
view ctx model =
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
    [ case model.invitationId of
        Nothing -> H.text ""
        Just id ->
          CopyWidget.view ctx.copy (ctx.httpOrigin ++ Utils.invitationPath id ++ case ctx.destination of
             Just d -> "?dest="++d
             Nothing -> "" )
    , H.button
        [ HA.disabled model.working
        , HE.onClick ctx.createInvitation
        ]
        [ H.text <| if model.working then "Creating..." else if model.invitationId == Nothing then "Create invitation" else "Create another"
        ]
    , H.text " "
    , model.notification |> H.map (\_ -> ctx.nevermind)
    , H.text " "
    , help
    ]



type ReactorMsg = Ignore | Copy String | CreateInvitation
main =
  let
    ctx : Context ReactorMsg
    ctx =
      { httpOrigin = "http://example.com"
      , createInvitation = CreateInvitation
      , copy = Copy
      , nevermind = Ignore
      , destination = Just "/mydest"
      }

    reactorUpdate : ReactorMsg -> Model -> Model
    reactorUpdate msg model =
      case msg of
        Ignore -> model
        Copy _ -> model
        CreateInvitation -> model |> setInvitation (Just {inviter=Just {kind=Just <| Pb.KindUsername "myuser"}, nonce="mynonce"})

  in
  Browser.sandbox
  { init = init
  , view = view ctx
  , update = reactorUpdate
  }