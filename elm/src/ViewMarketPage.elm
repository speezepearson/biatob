module ViewMarketPage exposing (..)

import Http

import Protobuf.Decode as PD
import Protobuf.Encode as PE

import Biatob.Proto.Mvp as Pb

getMarket : { authToken : String , marketId : Int } -> Cmd Msg
getMarket {authToken, marketId} =
  let
    req : Pb.GetMarketRequest
    req =
      { auth = Just { authKind = Just (Pb.AuthKindMagicToken authToken) }
      , marketId = marketId
      }
  in
    Http.post
        { url = "/api/get_market"
        , body = Http.bytesBody "application/octet-stream" <| PE.encode <| Pb.toGetMarketRequestEncoder req
        , expect = PD.expectBytes (always Ignore) Pb.getMarketResponseDecoder
        }
