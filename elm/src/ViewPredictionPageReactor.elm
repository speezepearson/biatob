module ViewPredictionPageReactor exposing (main)

import Browser

import ViewPredictionPage as Page
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

    -- , linkToAuthority = Utils.mustDecodeFromFlags JD.string "linkToAuthority" flags
    -- , prediction = Utils.mustDecodePbFromFlags Pb.userPredictionViewDecoder "predictionPbB64" flags
    -- , predictionId = Utils.mustDecodeFromFlags JD.int "predictionId" flags
    -- , auth = Utils.decodePbFromFlags Pb.authTokenDecoder "authTokenPbB64" flags

mockPrediction : Pb.UserPredictionView
mockPrediction =
  { prediction = "at least 50% of U.S. COVID-19 cases will be B117 or a derivative strain, as reported by the CDC"
  , certainty = Just {low = 0.8, high = 0.9}
  , maximumStakeCents = 10000
  , remainingStakeCentsVsBelievers = 10000
  , remainingStakeCentsVsSkeptics = 5000
  , createdUnixtime = 0
  , closesUnixtime = 60*60*24*365*100
  , specialRules = "If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the prediction is unresolvable."
  , creator = Just {displayName = "Spencer", isSelf=False, trustsYou=True, isTrusted=True}
  , resolutions = []
  , yourTrades = []
  , resolvesAtUnixtime = 60*60*24*365*101
  }


main =
  Browser.element
    { init = \() -> Page.init (JE.object [ ("authTokenPbB64", JE.string <| Utils.encodePbB64 <| Pb.toAuthTokenEncoder mockAuthToken)
                                         , ("predictionPbB64", JE.string <| Utils.encodePbB64 <| Pb.toUserPredictionViewEncoder mockPrediction)
                                         , ("predictionId", JE.int 12345)
                                         ])
    , subscriptions = Page.subscriptions
    , view = Page.view
    , update = Page.update
    }
