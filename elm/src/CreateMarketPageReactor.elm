module CreateMarketPageReactor exposing (main)

import Browser

import CreateMarketPage as Page
import Html as H exposing (Html)
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
  , expiresUnixtime = 2^64
  }

main =
  Browser.element
    { init = \() -> Page.init (JE.object [("authTokenPbB64", JE.string <| Utils.encodePbB64 <| Pb.toAuthTokenEncoder mockAuthToken)])
    , subscriptions = \_ -> Sub.none
    , view = Page.view
    , update = Page.update
    }
