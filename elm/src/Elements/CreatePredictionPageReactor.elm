module Elements.CreatePredictionPageReactor exposing (main)

import Browser

import Elements.CreatePredictionPage as Page
import Json.Encode as JE

import Bytes.Encode
import Biatob.Proto.Mvp as Pb
import Utils


mockUser : Pb.UserId
mockUser = {kind=Just <| Pb.KindUsername "testuser"}

mockAuthToken : Pb.AuthToken
mockAuthToken =
  { hmacOfRest = Bytes.Encode.encode <| Bytes.Encode.string ""
  , owner = Just mockUser
  , mintedUnixtime = 0
  , expiresUnixtime = 2^50
  }

main =
  Browser.element
    { init = \() -> Page.init (JE.object [("authTokenPbB64", JE.string <| Utils.encodePbB64 <| Pb.toAuthTokenEncoder mockAuthToken)])
    , subscriptions = Page.subscriptions
    , view = Page.view
    , update = Page.update
    }
