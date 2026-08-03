module Api.Types exposing
    ( AcceptInvitationRequest, AuthSuccess, CertaintyRange, ChangePasswordRequest, CheckInvitationRequest, CheckInvitationResponse, CreatePredictionRequest
    , CreatePredictionResponse, Empty, FollowRequest, GenericUserInfo, GetPredictionRequest, GetSettingsRequest, GetUserRequest
    , HTTPValidationError, Invitation, ListMyStakesRequest, ListPredictionsRequest, LogInUsernameRequest, PredictionsById, RegisterUsernameRequest
    , Relationship, ResolutionEvent(..), ResolveRequest, SendInvitationRequest, SendVerificationEmailRequest, SetTrustedRequest, SignOutRequest
    , StakeRequest, Trade, UserPredictionView, ValidationError, WhoamiRequest, WhoamiResponse
    , PredictionFollowingStatus(..), PredictionViewPrivacy(..), Resolution(..), TradeState(..), predictionFollowingStatusFromString, predictionFollowingStatusToString, predictionFollowingStatusVariants
    , predictionViewPrivacyFromString, predictionViewPrivacyToString, predictionViewPrivacyVariants, resolutionFromString, resolutionToString, resolutionVariants, tradeStateFromString
    , tradeStateToString, tradeStateVariants
    , Int_Or_String(..)
    )

{-|
## Aliases

@docs AcceptInvitationRequest, AuthSuccess, CertaintyRange, ChangePasswordRequest, CheckInvitationRequest, CheckInvitationResponse
@docs CreatePredictionRequest, CreatePredictionResponse, Empty, FollowRequest, GenericUserInfo, GetPredictionRequest
@docs GetSettingsRequest, GetUserRequest, HTTPValidationError, Invitation, ListMyStakesRequest, ListPredictionsRequest
@docs LogInUsernameRequest, PredictionsById, RegisterUsernameRequest, Relationship, ResolutionEvent, ResolveRequest
@docs SendInvitationRequest, SendVerificationEmailRequest, SetTrustedRequest, SignOutRequest, StakeRequest, Trade
@docs UserPredictionView, ValidationError, WhoamiRequest, WhoamiResponse

## Enum

@docs PredictionFollowingStatus, PredictionViewPrivacy, Resolution, TradeState, predictionFollowingStatusFromString, predictionFollowingStatusToString
@docs predictionFollowingStatusVariants, predictionViewPrivacyFromString, predictionViewPrivacyToString, predictionViewPrivacyVariants, resolutionFromString, resolutionToString
@docs resolutionVariants, tradeStateFromString, tradeStateToString, tradeStateVariants

## One of

@docs Int_Or_String
-}


import Dict
import Json.Encode
import OpenApi.Common


type alias AcceptInvitationRequest =
    { nonce : String }


type alias AuthSuccess =
    { owner : String, userInfo : GenericUserInfo }


type alias CertaintyRange =
    { high : Float, low : Float }


type alias ChangePasswordRequest =
    { newPassword : String, oldPassword : String }


type alias CheckInvitationRequest =
    { nonce : String }


type alias CheckInvitationResponse =
    { inviter : String, recipient : String }


type alias CreatePredictionRequest =
    { certainty : CertaintyRange
    , maximumStakeCents : Int
    , openSeconds : Int
    , prediction : String
    , resolvesAtUnixtime : Float
    , specialRules : String
    , viewPrivacy : PredictionViewPrivacy
    }


type alias CreatePredictionResponse =
    { newPredictionId : String }


{-| The body of an endpoint whose only output is 'it worked'. -}
type alias Empty =
    {}


type alias FollowRequest =
    { follow : Bool, predictionId : String }


type alias GenericUserInfo =
    { emailAddress : String
    , invitations : Dict.Dict String Invitation
    , relationships : Dict.Dict String Relationship
    }


type alias GetPredictionRequest =
    { predictionId : String }


type alias GetSettingsRequest =
    { includeRelationshipsWithUsers : List String }


type alias GetUserRequest =
    { who : String }


type alias HTTPValidationError =
    { detail : Maybe (List ValidationError) }


{-| Deliberately empty -- presence in the map is the whole signal. -}
type alias Invitation =
    {}


type alias ListMyStakesRequest =
    {}


type alias ListPredictionsRequest =
    { creator : String }


type alias LogInUsernameRequest =
    { password : String, username : String }


type alias PredictionsById =
    { predictions : Dict.Dict String UserPredictionView }


type alias RegisterUsernameRequest =
    { password : String, proofOfEmailToken : String, username : String }


type alias Relationship =
    { trustedByYou : Bool, trustsYou : Bool }


type ResolutionEvent
    = ResolutionEvent
        { notes : String
        , priorRevision : Maybe (OpenApi.Common.Nullable ResolutionEvent)
        , resolution : Resolution
        , unixtime : Float
        }


type alias ResolveRequest =
    { notes : String, predictionId : String, resolution : Resolution }


type alias SendInvitationRequest =
    { recipient : String }


type alias SendVerificationEmailRequest =
    { emailAddress : String }


type alias SetTrustedRequest =
    { trusted : Bool, who : String }


type alias SignOutRequest =
    {}


type alias StakeRequest =
    { bettorIsASkeptic : Bool, bettorStakeCents : Int, predictionId : String }


type alias Trade =
    { bettor : String
    , bettorIsASkeptic : Bool
    , bettorStakeCents : Int
    , creatorStakeCents : Int
    , notes : String
    , state : TradeState
    , transactedUnixtime : Float
    , updatedUnixtime : Float
    }


type alias UserPredictionView =
    { certainty : CertaintyRange
    , closesUnixtime : Float
    , createdUnixtime : Float
    , creator : String
    , maximumStakeCents : Int
    , prediction : String
    , remainingStakeCentsVsBelievers : Int
    , remainingStakeCentsVsSkeptics : Int
    , resolution : Maybe (OpenApi.Common.Nullable ResolutionEvent)
    , resolvesAtUnixtime : Float
    , specialRules : String
    , yourFollowingStatus : PredictionFollowingStatus
    , yourTrades : List Trade
    }


type alias ValidationError =
    { ctx : Maybe {}
    , input : Maybe Json.Encode.Value
    , loc : List Int_Or_String
    , msg : String
    , type_ : String
    }


type alias WhoamiRequest =
    {}


type alias WhoamiResponse =
    { username : String }


type PredictionFollowingStatus
    = PredictionFollowingStatus__PREDICTIONFOLLOWINGFOLLOWING
    | PredictionFollowingStatus__PREDICTIONFOLLOWINGMANDATORYBECAUSESTAKED
    | PredictionFollowingStatus__PREDICTIONFOLLOWINGNOTFOLLOWING


type PredictionViewPrivacy
    = PredictionViewPrivacy__PREDICTIONVIEWPRIVACYANYBODY
    | PredictionViewPrivacy__PREDICTIONVIEWPRIVACYANYBODYWITHTHELINK


type Resolution
    = Resolution__RESOLUTIONINVALID
    | Resolution__RESOLUTIONNO
    | Resolution__RESOLUTIONNONEYET
    | Resolution__RESOLUTIONYES


type TradeState
    = TradeState__TRADESTATEACTIVE
    | TradeState__TRADESTATEDEQUEUEFAILED
    | TradeState__TRADESTATEDISAVOWED
    | TradeState__TRADESTATEQUEUED


predictionFollowingStatusFromString : String -> Maybe PredictionFollowingStatus
predictionFollowingStatusFromString value =
    case value of
        "PREDICTION_FOLLOWING_FOLLOWING" ->
            Just PredictionFollowingStatus__PREDICTIONFOLLOWINGFOLLOWING
    
        "PREDICTION_FOLLOWING_MANDATORY_BECAUSE_STAKED" ->
            Just
                PredictionFollowingStatus__PREDICTIONFOLLOWINGMANDATORYBECAUSESTAKED
    
        "PREDICTION_FOLLOWING_NOT_FOLLOWING" ->
            Just PredictionFollowingStatus__PREDICTIONFOLLOWINGNOTFOLLOWING
    
        _ ->
            Nothing


predictionFollowingStatusToString : PredictionFollowingStatus -> String
predictionFollowingStatusToString value =
    case value of
        PredictionFollowingStatus__PREDICTIONFOLLOWINGFOLLOWING ->
            "PREDICTION_FOLLOWING_FOLLOWING"
    
        PredictionFollowingStatus__PREDICTIONFOLLOWINGMANDATORYBECAUSESTAKED ->
            "PREDICTION_FOLLOWING_MANDATORY_BECAUSE_STAKED"
    
        PredictionFollowingStatus__PREDICTIONFOLLOWINGNOTFOLLOWING ->
            "PREDICTION_FOLLOWING_NOT_FOLLOWING"


predictionFollowingStatusVariants : List PredictionFollowingStatus
predictionFollowingStatusVariants =
    [ PredictionFollowingStatus__PREDICTIONFOLLOWINGFOLLOWING
    , PredictionFollowingStatus__PREDICTIONFOLLOWINGMANDATORYBECAUSESTAKED
    , PredictionFollowingStatus__PREDICTIONFOLLOWINGNOTFOLLOWING
    ]


predictionViewPrivacyFromString : String -> Maybe PredictionViewPrivacy
predictionViewPrivacyFromString value =
    case value of
        "PREDICTION_VIEW_PRIVACY_ANYBODY" ->
            Just PredictionViewPrivacy__PREDICTIONVIEWPRIVACYANYBODY
    
        "PREDICTION_VIEW_PRIVACY_ANYBODY_WITH_THE_LINK" ->
            Just PredictionViewPrivacy__PREDICTIONVIEWPRIVACYANYBODYWITHTHELINK
    
        _ ->
            Nothing


predictionViewPrivacyToString : PredictionViewPrivacy -> String
predictionViewPrivacyToString value =
    case value of
        PredictionViewPrivacy__PREDICTIONVIEWPRIVACYANYBODY ->
            "PREDICTION_VIEW_PRIVACY_ANYBODY"
    
        PredictionViewPrivacy__PREDICTIONVIEWPRIVACYANYBODYWITHTHELINK ->
            "PREDICTION_VIEW_PRIVACY_ANYBODY_WITH_THE_LINK"


predictionViewPrivacyVariants : List PredictionViewPrivacy
predictionViewPrivacyVariants =
    [ PredictionViewPrivacy__PREDICTIONVIEWPRIVACYANYBODY
    , PredictionViewPrivacy__PREDICTIONVIEWPRIVACYANYBODYWITHTHELINK
    ]


resolutionFromString : String -> Maybe Resolution
resolutionFromString value =
    case value of
        "RESOLUTION_INVALID" ->
            Just Resolution__RESOLUTIONINVALID
    
        "RESOLUTION_NO" ->
            Just Resolution__RESOLUTIONNO
    
        "RESOLUTION_NONE_YET" ->
            Just Resolution__RESOLUTIONNONEYET
    
        "RESOLUTION_YES" ->
            Just Resolution__RESOLUTIONYES
    
        _ ->
            Nothing


resolutionToString : Resolution -> String
resolutionToString value =
    case value of
        Resolution__RESOLUTIONINVALID ->
            "RESOLUTION_INVALID"
    
        Resolution__RESOLUTIONNO ->
            "RESOLUTION_NO"
    
        Resolution__RESOLUTIONNONEYET ->
            "RESOLUTION_NONE_YET"
    
        Resolution__RESOLUTIONYES ->
            "RESOLUTION_YES"


resolutionVariants : List Resolution
resolutionVariants =
    [ Resolution__RESOLUTIONINVALID
    , Resolution__RESOLUTIONNO
    , Resolution__RESOLUTIONNONEYET
    , Resolution__RESOLUTIONYES
    ]


tradeStateFromString : String -> Maybe TradeState
tradeStateFromString value =
    case value of
        "TRADE_STATE_ACTIVE" ->
            Just TradeState__TRADESTATEACTIVE
    
        "TRADE_STATE_DEQUEUE_FAILED" ->
            Just TradeState__TRADESTATEDEQUEUEFAILED
    
        "TRADE_STATE_DISAVOWED" ->
            Just TradeState__TRADESTATEDISAVOWED
    
        "TRADE_STATE_QUEUED" ->
            Just TradeState__TRADESTATEQUEUED
    
        _ ->
            Nothing


tradeStateToString : TradeState -> String
tradeStateToString value =
    case value of
        TradeState__TRADESTATEACTIVE ->
            "TRADE_STATE_ACTIVE"
    
        TradeState__TRADESTATEDEQUEUEFAILED ->
            "TRADE_STATE_DEQUEUE_FAILED"
    
        TradeState__TRADESTATEDISAVOWED ->
            "TRADE_STATE_DISAVOWED"
    
        TradeState__TRADESTATEQUEUED ->
            "TRADE_STATE_QUEUED"


tradeStateVariants : List TradeState
tradeStateVariants =
    [ TradeState__TRADESTATEACTIVE
    , TradeState__TRADESTATEDEQUEUEFAILED
    , TradeState__TRADESTATEDISAVOWED
    , TradeState__TRADESTATEQUEUED
    ]


type Int_Or_String
    = Int_Or_String__Int Int
    | Int_Or_String__String String