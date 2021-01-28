{- !!! DO NOT EDIT THIS FILE MANUALLY !!! -}


module Biatob.Proto.Mvp exposing
    ( Void(..), Pronouns(..), Resolution(..), Position, AuthKind(..), Auth, AuthErrorKind(..), AuthError, SignUpRequest, SignupResult(..), SignUpResponse, SignUpResponseError, CertaintyRange, PrivacyKind(..), MarketPrivacy, MarketPrivacyEmails, CreateMarketRequest, CreateMarketResult(..), CreateMarketResponse, CreateMarketResponseError, GetMarketRequest, GetMarketResult(..), GetMarketResponse, GetMarketResponseMarket, GetMarketResponseError, UserInfo, StakeRequest, StakeResult(..), StakeResponse, StakeResponseError, GetUserRequest, GetUserResult(..), GetUserResponse, GetUserResponseUser, GetUserResponseError, MarkTrustedRequest, Result(..), MarkTrustedResponse, MarkTrustedResponseError
    , positionDecoder, authDecoder, authErrorDecoder, signUpRequestDecoder, signUpResponseDecoder, certaintyRangeDecoder, marketPrivacyDecoder, createMarketRequestDecoder, createMarketResponseDecoder, getMarketRequestDecoder, getMarketResponseDecoder, userInfoDecoder, stakeRequestDecoder, stakeResponseDecoder, getUserRequestDecoder, getUserResponseDecoder, markTrustedRequestDecoder, markTrustedResponseDecoder
    , toPositionEncoder, toAuthEncoder, toAuthErrorEncoder, toSignUpRequestEncoder, toSignUpResponseEncoder, toCertaintyRangeEncoder, toMarketPrivacyEncoder, toCreateMarketRequestEncoder, toCreateMarketResponseEncoder, toGetMarketRequestEncoder, toGetMarketResponseEncoder, toUserInfoEncoder, toStakeRequestEncoder, toStakeResponseEncoder, toGetUserRequestEncoder, toGetUserResponseEncoder, toMarkTrustedRequestEncoder, toMarkTrustedResponseEncoder
    )

{-| ProtoBuf module: `Biatob.Proto.Mvp`

This module was generated automatically using

  - [`protoc-gen-elm`](https://www.npmjs.com/package/protoc-gen-elm) 1.0.0-beta-2
  - `protoc` unknown version
  - the following specification file: `protobuf/mvp.proto`

To run it use [`elm-protocol-buffers`](https://package.elm-lang.org/packages/eriktim/elm-protocol-buffers/1.1.0) version 1.1.0 or higher.


# Model

@docs Void, Pronouns, Resolution, Position, AuthKind, Auth, AuthErrorKind, AuthError, SignUpRequest, SignupResult, SignUpResponse, SignUpResponseError, CertaintyRange, PrivacyKind, MarketPrivacy, MarketPrivacyEmails, CreateMarketRequest, CreateMarketResult, CreateMarketResponse, CreateMarketResponseError, GetMarketRequest, GetMarketResult, GetMarketResponse, GetMarketResponseMarket, GetMarketResponseError, UserInfo, StakeRequest, StakeResult, StakeResponse, StakeResponseError, GetUserRequest, GetUserResult, GetUserResponse, GetUserResponseUser, GetUserResponseError, MarkTrustedRequest, Result, MarkTrustedResponse, MarkTrustedResponseError


# Decoder

@docs positionDecoder, authDecoder, authErrorDecoder, signUpRequestDecoder, signUpResponseDecoder, certaintyRangeDecoder, marketPrivacyDecoder, createMarketRequestDecoder, createMarketResponseDecoder, getMarketRequestDecoder, getMarketResponseDecoder, userInfoDecoder, stakeRequestDecoder, stakeResponseDecoder, getUserRequestDecoder, getUserResponseDecoder, markTrustedRequestDecoder, markTrustedResponseDecoder


# Encoder

@docs toPositionEncoder, toAuthEncoder, toAuthErrorEncoder, toSignUpRequestEncoder, toSignUpResponseEncoder, toCertaintyRangeEncoder, toMarketPrivacyEncoder, toCreateMarketRequestEncoder, toCreateMarketResponseEncoder, toGetMarketRequestEncoder, toGetMarketResponseEncoder, toUserInfoEncoder, toStakeRequestEncoder, toStakeResponseEncoder, toGetUserRequestEncoder, toGetUserResponseEncoder, toMarkTrustedRequestEncoder, toMarkTrustedResponseEncoder

-}

import Protobuf.Decode as Decode
import Protobuf.Encode as Encode



-- MODEL


{-| `Void` enumeration
-}
type Void
    = Void
    | VoidUnrecognized_ Int


{-| `Pronouns` enumeration
-}
type Pronouns
    = TheyThem
    | SheHer
    | HeHim
    | PronounsUnrecognized_ Int


{-| `Resolution` enumeration
-}
type Resolution
    = ResolutionNoneYet
    | ResolutionYes
    | ResolutionNo
    | ResolutionUnrecognized_ Int


{-| `Position` message
-}
type alias Position =
    { winCentsIfYes : Int
    , winCentsIfNo : Int
    }


{-| AuthKind
-}
type AuthKind
    = AuthKindMagicToken String


{-| `Auth` message
-}
type alias Auth =
    { authKind : Maybe AuthKind
    }


{-| AuthErrorKind
-}
type AuthErrorKind
    = AuthErrorKindInvalidToken Void


{-| `AuthError` message
-}
type alias AuthError =
    { authErrorKind : Maybe AuthErrorKind
    }


{-| `SignUpRequest` message
-}
type alias SignUpRequest =
    { email : String
    , password : String
    , displayName : String
    , pronouns : Pronouns
    }


{-| SignupResult
-}
type SignupResult
    = SignupResultOk Void
    | SignupResultError SignUpResponseError


{-| `SignUpResponse` message
-}
type alias SignUpResponse =
    { signupResult : Maybe SignupResult
    }


{-| `SignUpResponseError` message
-}
type alias SignUpResponseError =
    { catchall : String
    , emailAlreadyRegistered : Void
    }


{-| `CertaintyRange` message
-}
type alias CertaintyRange =
    { low : Float
    , high : Float
    }


{-| PrivacyKind
-}
type PrivacyKind
    = PrivacyKindAllTrustedByAuthor Void
    | PrivacyKindSpecificUsers MarketPrivacyEmails


{-| `MarketPrivacy` message
-}
type alias MarketPrivacy =
    { privacyKind : Maybe PrivacyKind
    }


{-| `MarketPrivacyEmails` message
-}
type alias MarketPrivacyEmails =
    { emails : List String
    }


{-| `CreateMarketRequest` message
-}
type alias CreateMarketRequest =
    { auth : Maybe Auth
    , question : String
    , privacy : Maybe MarketPrivacy
    , certainty : Maybe CertaintyRange
    , maximumStakeCents : Int
    , openSeconds : Int
    , specialRules : String
    }


{-| CreateMarketResult
-}
type CreateMarketResult
    = CreateMarketResultNewMarketId Int
    | CreateMarketResultError CreateMarketResponseError


{-| `CreateMarketResponse` message
-}
type alias CreateMarketResponse =
    { createMarketResult : Maybe CreateMarketResult
    }


{-| `CreateMarketResponseError` message
-}
type alias CreateMarketResponseError =
    { catchall : String
    , authError : Maybe AuthError
    }


{-| `GetMarketRequest` message
-}
type alias GetMarketRequest =
    { auth : Maybe Auth
    , marketId : Int
    }


{-| GetMarketResult
-}
type GetMarketResult
    = GetMarketResultMarket GetMarketResponseMarket
    | GetMarketResultError GetMarketResponseError


{-| `GetMarketResponse` message
-}
type alias GetMarketResponse =
    { getMarketResult : Maybe GetMarketResult
    }


{-| `GetMarketResponseMarket` message
-}
type alias GetMarketResponseMarket =
    { question : String
    , certainty : Maybe CertaintyRange
    , maximumStakeCents : Int
    , remainingYesStakeCents : Int
    , remainingNoStakeCents : Int
    , createdUnixtime : Int
    , closesUnixtime : Int
    , specialRules : String
    , creator : Maybe UserInfo
    , resolution : Resolution
    }


{-| `GetMarketResponseError` message
-}
type alias GetMarketResponseError =
    { catchall : String
    , authError : Maybe AuthError
    }


{-| `UserInfo` message
-}
type alias UserInfo =
    { displayName : String
    , pronouns : Pronouns
    }


{-| `StakeRequest` message
-}
type alias StakeRequest =
    { auth : Maybe Auth
    , marketId : Int
    , expectedResolution : Bool
    , stake : Int
    }


{-| StakeResult
-}
type StakeResult
    = StakeResultOk Void
    | StakeResultError StakeResponseError


{-| `StakeResponse` message
-}
type alias StakeResponse =
    { stakeResult : Maybe StakeResult
    }


{-| `StakeResponseError` message
-}
type alias StakeResponseError =
    { catchall : String
    , authError : Maybe AuthError
    }


{-| `GetUserRequest` message
-}
type alias GetUserRequest =
    { auth : Maybe Auth
    , email : String
    }


{-| GetUserResult
-}
type GetUserResult
    = GetUserResultUser GetUserResponseUser
    | GetUserResultError GetUserResponseError


{-| `GetUserResponse` message
-}
type alias GetUserResponse =
    { getUserResult : Maybe GetUserResult
    }


{-| `GetUserResponseUser` message
-}
type alias GetUserResponseUser =
    { trustedByRequester : Bool
    , trustsRequester : Bool
    }


{-| `GetUserResponseError` message
-}
type alias GetUserResponseError =
    { catchall : String
    , authError : Maybe AuthError
    }


{-| `MarkTrustedRequest` message
-}
type alias MarkTrustedRequest =
    { auth : Maybe Auth
    , emailToTrust : String
    }


{-| Result
-}
type Result
    = ResultOk Void
    | ResultError MarkTrustedResponseError


{-| `MarkTrustedResponse` message
-}
type alias MarkTrustedResponse =
    { result : Maybe Result
    }


{-| `MarkTrustedResponseError` message
-}
type alias MarkTrustedResponseError =
    { catchall : String
    , authError : Maybe AuthError
    }



-- DECODER


voidDecoder : Decode.Decoder Void
voidDecoder =
    Decode.int32
        |> Decode.map
            (\value ->
                case value of
                    0 ->
                        Void

                    v ->
                        VoidUnrecognized_ v
            )


pronounsDecoder : Decode.Decoder Pronouns
pronounsDecoder =
    Decode.int32
        |> Decode.map
            (\value ->
                case value of
                    0 ->
                        TheyThem

                    1 ->
                        SheHer

                    2 ->
                        HeHim

                    v ->
                        PronounsUnrecognized_ v
            )


resolutionDecoder : Decode.Decoder Resolution
resolutionDecoder =
    Decode.int32
        |> Decode.map
            (\value ->
                case value of
                    0 ->
                        ResolutionNoneYet

                    1 ->
                        ResolutionYes

                    2 ->
                        ResolutionNo

                    v ->
                        ResolutionUnrecognized_ v
            )


{-| `Position` decoder
-}
positionDecoder : Decode.Decoder Position
positionDecoder =
    Decode.message (Position 0 0)
        [ Decode.optional 1 Decode.int32 setWinCentsIfYes
        , Decode.optional 2 Decode.int32 setWinCentsIfNo
        ]


{-| `Auth` decoder
-}
authDecoder : Decode.Decoder Auth
authDecoder =
    Decode.message (Auth Nothing)
        [ Decode.oneOf
            [ ( 1, Decode.map AuthKindMagicToken Decode.string )
            ]
            setAuthKind
        ]


{-| `AuthError` decoder
-}
authErrorDecoder : Decode.Decoder AuthError
authErrorDecoder =
    Decode.message (AuthError Nothing)
        [ Decode.oneOf
            [ ( 1, Decode.map AuthErrorKindInvalidToken voidDecoder )
            ]
            setAuthErrorKind
        ]


{-| `SignUpRequest` decoder
-}
signUpRequestDecoder : Decode.Decoder SignUpRequest
signUpRequestDecoder =
    Decode.message (SignUpRequest "" "" "" TheyThem)
        [ Decode.optional 1 Decode.string setEmail
        , Decode.optional 2 Decode.string setPassword
        , Decode.optional 3 Decode.string setDisplayName
        , Decode.optional 4 pronounsDecoder setPronouns
        ]


{-| `SignUpResponse` decoder
-}
signUpResponseDecoder : Decode.Decoder SignUpResponse
signUpResponseDecoder =
    Decode.message (SignUpResponse Nothing)
        [ Decode.oneOf
            [ ( 1, Decode.map SignupResultOk voidDecoder )
            , ( 2, Decode.map SignupResultError signUpResponseErrorDecoder )
            ]
            setSignupResult
        ]


signUpResponseErrorDecoder : Decode.Decoder SignUpResponseError
signUpResponseErrorDecoder =
    Decode.message (SignUpResponseError "" Void)
        [ Decode.optional 1 Decode.string setCatchall
        , Decode.optional 2 voidDecoder setEmailAlreadyRegistered
        ]


{-| `CertaintyRange` decoder
-}
certaintyRangeDecoder : Decode.Decoder CertaintyRange
certaintyRangeDecoder =
    Decode.message (CertaintyRange 0 0)
        [ Decode.optional 1 Decode.float setLow
        , Decode.optional 2 Decode.float setHigh
        ]


{-| `MarketPrivacy` decoder
-}
marketPrivacyDecoder : Decode.Decoder MarketPrivacy
marketPrivacyDecoder =
    Decode.message (MarketPrivacy Nothing)
        [ Decode.oneOf
            [ ( 1, Decode.map PrivacyKindAllTrustedByAuthor voidDecoder )
            , ( 2, Decode.map PrivacyKindSpecificUsers marketPrivacyEmailsDecoder )
            ]
            setPrivacyKind
        ]


marketPrivacyEmailsDecoder : Decode.Decoder MarketPrivacyEmails
marketPrivacyEmailsDecoder =
    Decode.message (MarketPrivacyEmails [])
        [ Decode.repeated 1 Decode.string .emails setEmails
        ]


{-| `CreateMarketRequest` decoder
-}
createMarketRequestDecoder : Decode.Decoder CreateMarketRequest
createMarketRequestDecoder =
    Decode.message (CreateMarketRequest Nothing "" Nothing Nothing 0 0 "")
        [ Decode.optional 1 (Decode.map Just authDecoder) setAuth
        , Decode.optional 2 Decode.string setQuestion
        , Decode.optional 3 (Decode.map Just marketPrivacyDecoder) setPrivacy
        , Decode.optional 4 (Decode.map Just certaintyRangeDecoder) setCertainty
        , Decode.optional 5 Decode.uint32 setMaximumStakeCents
        , Decode.optional 6 Decode.uint32 setOpenSeconds
        , Decode.optional 7 Decode.string setSpecialRules
        ]


{-| `CreateMarketResponse` decoder
-}
createMarketResponseDecoder : Decode.Decoder CreateMarketResponse
createMarketResponseDecoder =
    Decode.message (CreateMarketResponse Nothing)
        [ Decode.oneOf
            [ ( 1, Decode.map CreateMarketResultNewMarketId Decode.uint32 )
            , ( 2, Decode.map CreateMarketResultError createMarketResponseErrorDecoder )
            ]
            setCreateMarketResult
        ]


createMarketResponseErrorDecoder : Decode.Decoder CreateMarketResponseError
createMarketResponseErrorDecoder =
    Decode.message (CreateMarketResponseError "" Nothing)
        [ Decode.optional 1 Decode.string setCatchall
        , Decode.optional 2 (Decode.map Just authErrorDecoder) setAuthError
        ]


{-| `GetMarketRequest` decoder
-}
getMarketRequestDecoder : Decode.Decoder GetMarketRequest
getMarketRequestDecoder =
    Decode.message (GetMarketRequest Nothing 0)
        [ Decode.optional 1 (Decode.map Just authDecoder) setAuth
        , Decode.optional 2 Decode.uint32 setMarketId
        ]


{-| `GetMarketResponse` decoder
-}
getMarketResponseDecoder : Decode.Decoder GetMarketResponse
getMarketResponseDecoder =
    Decode.message (GetMarketResponse Nothing)
        [ Decode.oneOf
            [ ( 1, Decode.map GetMarketResultMarket getMarketResponseMarketDecoder )
            , ( 2, Decode.map GetMarketResultError getMarketResponseErrorDecoder )
            ]
            setGetMarketResult
        ]


getMarketResponseMarketDecoder : Decode.Decoder GetMarketResponseMarket
getMarketResponseMarketDecoder =
    Decode.message (GetMarketResponseMarket "" Nothing 0 0 0 0 0 "" Nothing ResolutionNoneYet)
        [ Decode.optional 1 Decode.string setQuestion
        , Decode.optional 2 (Decode.map Just certaintyRangeDecoder) setCertainty
        , Decode.optional 3 Decode.uint32 setMaximumStakeCents
        , Decode.optional 4 Decode.uint32 setRemainingYesStakeCents
        , Decode.optional 5 Decode.uint32 setRemainingNoStakeCents
        , Decode.optional 6 Decode.uint32 setCreatedUnixtime
        , Decode.optional 7 Decode.uint32 setClosesUnixtime
        , Decode.optional 8 Decode.string setSpecialRules
        , Decode.optional 9 (Decode.map Just userInfoDecoder) setCreator
        , Decode.optional 10 resolutionDecoder setResolution
        ]


getMarketResponseErrorDecoder : Decode.Decoder GetMarketResponseError
getMarketResponseErrorDecoder =
    Decode.message (GetMarketResponseError "" Nothing)
        [ Decode.optional 1 Decode.string setCatchall
        , Decode.optional 2 (Decode.map Just authErrorDecoder) setAuthError
        ]


{-| `UserInfo` decoder
-}
userInfoDecoder : Decode.Decoder UserInfo
userInfoDecoder =
    Decode.message (UserInfo "" TheyThem)
        [ Decode.optional 1 Decode.string setDisplayName
        , Decode.optional 2 pronounsDecoder setPronouns
        ]


{-| `StakeRequest` decoder
-}
stakeRequestDecoder : Decode.Decoder StakeRequest
stakeRequestDecoder =
    Decode.message (StakeRequest Nothing 0 False 0)
        [ Decode.optional 1 (Decode.map Just authDecoder) setAuth
        , Decode.optional 2 Decode.uint32 setMarketId
        , Decode.optional 3 Decode.bool setExpectedResolution
        , Decode.optional 4 Decode.uint32 setStake
        ]


{-| `StakeResponse` decoder
-}
stakeResponseDecoder : Decode.Decoder StakeResponse
stakeResponseDecoder =
    Decode.message (StakeResponse Nothing)
        [ Decode.oneOf
            [ ( 1, Decode.map StakeResultOk voidDecoder )
            , ( 2, Decode.map StakeResultError stakeResponseErrorDecoder )
            ]
            setStakeResult
        ]


stakeResponseErrorDecoder : Decode.Decoder StakeResponseError
stakeResponseErrorDecoder =
    Decode.message (StakeResponseError "" Nothing)
        [ Decode.optional 1 Decode.string setCatchall
        , Decode.optional 2 (Decode.map Just authErrorDecoder) setAuthError
        ]


{-| `GetUserRequest` decoder
-}
getUserRequestDecoder : Decode.Decoder GetUserRequest
getUserRequestDecoder =
    Decode.message (GetUserRequest Nothing "")
        [ Decode.optional 1 (Decode.map Just authDecoder) setAuth
        , Decode.optional 2 Decode.string setEmail
        ]


{-| `GetUserResponse` decoder
-}
getUserResponseDecoder : Decode.Decoder GetUserResponse
getUserResponseDecoder =
    Decode.message (GetUserResponse Nothing)
        [ Decode.oneOf
            [ ( 1, Decode.map GetUserResultUser getUserResponseUserDecoder )
            , ( 2, Decode.map GetUserResultError getUserResponseErrorDecoder )
            ]
            setGetUserResult
        ]


getUserResponseUserDecoder : Decode.Decoder GetUserResponseUser
getUserResponseUserDecoder =
    Decode.message (GetUserResponseUser False False)
        [ Decode.optional 1 Decode.bool setTrustedByRequester
        , Decode.optional 2 Decode.bool setTrustsRequester
        ]


getUserResponseErrorDecoder : Decode.Decoder GetUserResponseError
getUserResponseErrorDecoder =
    Decode.message (GetUserResponseError "" Nothing)
        [ Decode.optional 1 Decode.string setCatchall
        , Decode.optional 2 (Decode.map Just authErrorDecoder) setAuthError
        ]


{-| `MarkTrustedRequest` decoder
-}
markTrustedRequestDecoder : Decode.Decoder MarkTrustedRequest
markTrustedRequestDecoder =
    Decode.message (MarkTrustedRequest Nothing "")
        [ Decode.optional 1 (Decode.map Just authDecoder) setAuth
        , Decode.optional 2 Decode.string setEmailToTrust
        ]


{-| `MarkTrustedResponse` decoder
-}
markTrustedResponseDecoder : Decode.Decoder MarkTrustedResponse
markTrustedResponseDecoder =
    Decode.message (MarkTrustedResponse Nothing)
        [ Decode.oneOf
            [ ( 1, Decode.map ResultOk voidDecoder )
            , ( 2, Decode.map ResultError markTrustedResponseErrorDecoder )
            ]
            setResult
        ]


markTrustedResponseErrorDecoder : Decode.Decoder MarkTrustedResponseError
markTrustedResponseErrorDecoder =
    Decode.message (MarkTrustedResponseError "" Nothing)
        [ Decode.optional 1 Decode.string setCatchall
        , Decode.optional 2 (Decode.map Just authErrorDecoder) setAuthError
        ]



-- ENCODER


toVoidEncoder : Void -> Encode.Encoder
toVoidEncoder value =
    Encode.int32 <|
        case value of
            Void ->
                0

            VoidUnrecognized_ v ->
                v


toPronounsEncoder : Pronouns -> Encode.Encoder
toPronounsEncoder value =
    Encode.int32 <|
        case value of
            TheyThem ->
                0

            SheHer ->
                1

            HeHim ->
                2

            PronounsUnrecognized_ v ->
                v


toResolutionEncoder : Resolution -> Encode.Encoder
toResolutionEncoder value =
    Encode.int32 <|
        case value of
            ResolutionNoneYet ->
                0

            ResolutionYes ->
                1

            ResolutionNo ->
                2

            ResolutionUnrecognized_ v ->
                v


{-| `Position` encoder
-}
toPositionEncoder : Position -> Encode.Encoder
toPositionEncoder model =
    Encode.message
        [ ( 1, Encode.int32 model.winCentsIfYes )
        , ( 2, Encode.int32 model.winCentsIfNo )
        ]


toAuthKindEncoder : AuthKind -> ( Int, Encode.Encoder )
toAuthKindEncoder model =
    case model of
        AuthKindMagicToken value ->
            ( 1, Encode.string value )


{-| `Auth` encoder
-}
toAuthEncoder : Auth -> Encode.Encoder
toAuthEncoder model =
    Encode.message
        [ Maybe.withDefault ( 0, Encode.none ) <| Maybe.map toAuthKindEncoder model.authKind
        ]


toAuthErrorKindEncoder : AuthErrorKind -> ( Int, Encode.Encoder )
toAuthErrorKindEncoder model =
    case model of
        AuthErrorKindInvalidToken value ->
            ( 1, toVoidEncoder value )


{-| `AuthError` encoder
-}
toAuthErrorEncoder : AuthError -> Encode.Encoder
toAuthErrorEncoder model =
    Encode.message
        [ Maybe.withDefault ( 0, Encode.none ) <| Maybe.map toAuthErrorKindEncoder model.authErrorKind
        ]


{-| `SignUpRequest` encoder
-}
toSignUpRequestEncoder : SignUpRequest -> Encode.Encoder
toSignUpRequestEncoder model =
    Encode.message
        [ ( 1, Encode.string model.email )
        , ( 2, Encode.string model.password )
        , ( 3, Encode.string model.displayName )
        , ( 4, toPronounsEncoder model.pronouns )
        ]


toSignupResultEncoder : SignupResult -> ( Int, Encode.Encoder )
toSignupResultEncoder model =
    case model of
        SignupResultOk value ->
            ( 1, toVoidEncoder value )

        SignupResultError value ->
            ( 2, toSignUpResponseErrorEncoder value )


{-| `SignUpResponse` encoder
-}
toSignUpResponseEncoder : SignUpResponse -> Encode.Encoder
toSignUpResponseEncoder model =
    Encode.message
        [ Maybe.withDefault ( 0, Encode.none ) <| Maybe.map toSignupResultEncoder model.signupResult
        ]


toSignUpResponseErrorEncoder : SignUpResponseError -> Encode.Encoder
toSignUpResponseErrorEncoder model =
    Encode.message
        [ ( 1, Encode.string model.catchall )
        , ( 2, toVoidEncoder model.emailAlreadyRegistered )
        ]


{-| `CertaintyRange` encoder
-}
toCertaintyRangeEncoder : CertaintyRange -> Encode.Encoder
toCertaintyRangeEncoder model =
    Encode.message
        [ ( 1, Encode.float model.low )
        , ( 2, Encode.float model.high )
        ]


toPrivacyKindEncoder : PrivacyKind -> ( Int, Encode.Encoder )
toPrivacyKindEncoder model =
    case model of
        PrivacyKindAllTrustedByAuthor value ->
            ( 1, toVoidEncoder value )

        PrivacyKindSpecificUsers value ->
            ( 2, toMarketPrivacyEmailsEncoder value )


{-| `MarketPrivacy` encoder
-}
toMarketPrivacyEncoder : MarketPrivacy -> Encode.Encoder
toMarketPrivacyEncoder model =
    Encode.message
        [ Maybe.withDefault ( 0, Encode.none ) <| Maybe.map toPrivacyKindEncoder model.privacyKind
        ]


toMarketPrivacyEmailsEncoder : MarketPrivacyEmails -> Encode.Encoder
toMarketPrivacyEmailsEncoder model =
    Encode.message
        [ ( 1, Encode.list Encode.string model.emails )
        ]


{-| `CreateMarketRequest` encoder
-}
toCreateMarketRequestEncoder : CreateMarketRequest -> Encode.Encoder
toCreateMarketRequestEncoder model =
    Encode.message
        [ ( 1, (Maybe.withDefault Encode.none << Maybe.map toAuthEncoder) model.auth )
        , ( 2, Encode.string model.question )
        , ( 3, (Maybe.withDefault Encode.none << Maybe.map toMarketPrivacyEncoder) model.privacy )
        , ( 4, (Maybe.withDefault Encode.none << Maybe.map toCertaintyRangeEncoder) model.certainty )
        , ( 5, Encode.uint32 model.maximumStakeCents )
        , ( 6, Encode.uint32 model.openSeconds )
        , ( 7, Encode.string model.specialRules )
        ]


toCreateMarketResultEncoder : CreateMarketResult -> ( Int, Encode.Encoder )
toCreateMarketResultEncoder model =
    case model of
        CreateMarketResultNewMarketId value ->
            ( 1, Encode.uint32 value )

        CreateMarketResultError value ->
            ( 2, toCreateMarketResponseErrorEncoder value )


{-| `CreateMarketResponse` encoder
-}
toCreateMarketResponseEncoder : CreateMarketResponse -> Encode.Encoder
toCreateMarketResponseEncoder model =
    Encode.message
        [ Maybe.withDefault ( 0, Encode.none ) <| Maybe.map toCreateMarketResultEncoder model.createMarketResult
        ]


toCreateMarketResponseErrorEncoder : CreateMarketResponseError -> Encode.Encoder
toCreateMarketResponseErrorEncoder model =
    Encode.message
        [ ( 1, Encode.string model.catchall )
        , ( 2, (Maybe.withDefault Encode.none << Maybe.map toAuthErrorEncoder) model.authError )
        ]


{-| `GetMarketRequest` encoder
-}
toGetMarketRequestEncoder : GetMarketRequest -> Encode.Encoder
toGetMarketRequestEncoder model =
    Encode.message
        [ ( 1, (Maybe.withDefault Encode.none << Maybe.map toAuthEncoder) model.auth )
        , ( 2, Encode.uint32 model.marketId )
        ]


toGetMarketResultEncoder : GetMarketResult -> ( Int, Encode.Encoder )
toGetMarketResultEncoder model =
    case model of
        GetMarketResultMarket value ->
            ( 1, toGetMarketResponseMarketEncoder value )

        GetMarketResultError value ->
            ( 2, toGetMarketResponseErrorEncoder value )


{-| `GetMarketResponse` encoder
-}
toGetMarketResponseEncoder : GetMarketResponse -> Encode.Encoder
toGetMarketResponseEncoder model =
    Encode.message
        [ Maybe.withDefault ( 0, Encode.none ) <| Maybe.map toGetMarketResultEncoder model.getMarketResult
        ]


toGetMarketResponseMarketEncoder : GetMarketResponseMarket -> Encode.Encoder
toGetMarketResponseMarketEncoder model =
    Encode.message
        [ ( 1, Encode.string model.question )
        , ( 2, (Maybe.withDefault Encode.none << Maybe.map toCertaintyRangeEncoder) model.certainty )
        , ( 3, Encode.uint32 model.maximumStakeCents )
        , ( 4, Encode.uint32 model.remainingYesStakeCents )
        , ( 5, Encode.uint32 model.remainingNoStakeCents )
        , ( 6, Encode.uint32 model.createdUnixtime )
        , ( 7, Encode.uint32 model.closesUnixtime )
        , ( 8, Encode.string model.specialRules )
        , ( 9, (Maybe.withDefault Encode.none << Maybe.map toUserInfoEncoder) model.creator )
        , ( 10, toResolutionEncoder model.resolution )
        ]


toGetMarketResponseErrorEncoder : GetMarketResponseError -> Encode.Encoder
toGetMarketResponseErrorEncoder model =
    Encode.message
        [ ( 1, Encode.string model.catchall )
        , ( 2, (Maybe.withDefault Encode.none << Maybe.map toAuthErrorEncoder) model.authError )
        ]


{-| `UserInfo` encoder
-}
toUserInfoEncoder : UserInfo -> Encode.Encoder
toUserInfoEncoder model =
    Encode.message
        [ ( 1, Encode.string model.displayName )
        , ( 2, toPronounsEncoder model.pronouns )
        ]


{-| `StakeRequest` encoder
-}
toStakeRequestEncoder : StakeRequest -> Encode.Encoder
toStakeRequestEncoder model =
    Encode.message
        [ ( 1, (Maybe.withDefault Encode.none << Maybe.map toAuthEncoder) model.auth )
        , ( 2, Encode.uint32 model.marketId )
        , ( 3, Encode.bool model.expectedResolution )
        , ( 4, Encode.uint32 model.stake )
        ]


toStakeResultEncoder : StakeResult -> ( Int, Encode.Encoder )
toStakeResultEncoder model =
    case model of
        StakeResultOk value ->
            ( 1, toVoidEncoder value )

        StakeResultError value ->
            ( 2, toStakeResponseErrorEncoder value )


{-| `StakeResponse` encoder
-}
toStakeResponseEncoder : StakeResponse -> Encode.Encoder
toStakeResponseEncoder model =
    Encode.message
        [ Maybe.withDefault ( 0, Encode.none ) <| Maybe.map toStakeResultEncoder model.stakeResult
        ]


toStakeResponseErrorEncoder : StakeResponseError -> Encode.Encoder
toStakeResponseErrorEncoder model =
    Encode.message
        [ ( 1, Encode.string model.catchall )
        , ( 2, (Maybe.withDefault Encode.none << Maybe.map toAuthErrorEncoder) model.authError )
        ]


{-| `GetUserRequest` encoder
-}
toGetUserRequestEncoder : GetUserRequest -> Encode.Encoder
toGetUserRequestEncoder model =
    Encode.message
        [ ( 1, (Maybe.withDefault Encode.none << Maybe.map toAuthEncoder) model.auth )
        , ( 2, Encode.string model.email )
        ]


toGetUserResultEncoder : GetUserResult -> ( Int, Encode.Encoder )
toGetUserResultEncoder model =
    case model of
        GetUserResultUser value ->
            ( 1, toGetUserResponseUserEncoder value )

        GetUserResultError value ->
            ( 2, toGetUserResponseErrorEncoder value )


{-| `GetUserResponse` encoder
-}
toGetUserResponseEncoder : GetUserResponse -> Encode.Encoder
toGetUserResponseEncoder model =
    Encode.message
        [ Maybe.withDefault ( 0, Encode.none ) <| Maybe.map toGetUserResultEncoder model.getUserResult
        ]


toGetUserResponseUserEncoder : GetUserResponseUser -> Encode.Encoder
toGetUserResponseUserEncoder model =
    Encode.message
        [ ( 1, Encode.bool model.trustedByRequester )
        , ( 2, Encode.bool model.trustsRequester )
        ]


toGetUserResponseErrorEncoder : GetUserResponseError -> Encode.Encoder
toGetUserResponseErrorEncoder model =
    Encode.message
        [ ( 1, Encode.string model.catchall )
        , ( 2, (Maybe.withDefault Encode.none << Maybe.map toAuthErrorEncoder) model.authError )
        ]


{-| `MarkTrustedRequest` encoder
-}
toMarkTrustedRequestEncoder : MarkTrustedRequest -> Encode.Encoder
toMarkTrustedRequestEncoder model =
    Encode.message
        [ ( 1, (Maybe.withDefault Encode.none << Maybe.map toAuthEncoder) model.auth )
        , ( 2, Encode.string model.emailToTrust )
        ]


toResultEncoder : Result -> ( Int, Encode.Encoder )
toResultEncoder model =
    case model of
        ResultOk value ->
            ( 1, toVoidEncoder value )

        ResultError value ->
            ( 2, toMarkTrustedResponseErrorEncoder value )


{-| `MarkTrustedResponse` encoder
-}
toMarkTrustedResponseEncoder : MarkTrustedResponse -> Encode.Encoder
toMarkTrustedResponseEncoder model =
    Encode.message
        [ Maybe.withDefault ( 0, Encode.none ) <| Maybe.map toResultEncoder model.result
        ]


toMarkTrustedResponseErrorEncoder : MarkTrustedResponseError -> Encode.Encoder
toMarkTrustedResponseErrorEncoder model =
    Encode.message
        [ ( 1, Encode.string model.catchall )
        , ( 2, (Maybe.withDefault Encode.none << Maybe.map toAuthErrorEncoder) model.authError )
        ]



-- SETTERS


setWinCentsIfYes : a -> { b | winCentsIfYes : a } -> { b | winCentsIfYes : a }
setWinCentsIfYes value model =
    { model | winCentsIfYes = value }


setWinCentsIfNo : a -> { b | winCentsIfNo : a } -> { b | winCentsIfNo : a }
setWinCentsIfNo value model =
    { model | winCentsIfNo = value }


setAuthKind : a -> { b | authKind : a } -> { b | authKind : a }
setAuthKind value model =
    { model | authKind = value }


setAuthErrorKind : a -> { b | authErrorKind : a } -> { b | authErrorKind : a }
setAuthErrorKind value model =
    { model | authErrorKind = value }


setEmail : a -> { b | email : a } -> { b | email : a }
setEmail value model =
    { model | email = value }


setPassword : a -> { b | password : a } -> { b | password : a }
setPassword value model =
    { model | password = value }


setDisplayName : a -> { b | displayName : a } -> { b | displayName : a }
setDisplayName value model =
    { model | displayName = value }


setPronouns : a -> { b | pronouns : a } -> { b | pronouns : a }
setPronouns value model =
    { model | pronouns = value }


setSignupResult : a -> { b | signupResult : a } -> { b | signupResult : a }
setSignupResult value model =
    { model | signupResult = value }


setCatchall : a -> { b | catchall : a } -> { b | catchall : a }
setCatchall value model =
    { model | catchall = value }


setEmailAlreadyRegistered : a -> { b | emailAlreadyRegistered : a } -> { b | emailAlreadyRegistered : a }
setEmailAlreadyRegistered value model =
    { model | emailAlreadyRegistered = value }


setLow : a -> { b | low : a } -> { b | low : a }
setLow value model =
    { model | low = value }


setHigh : a -> { b | high : a } -> { b | high : a }
setHigh value model =
    { model | high = value }


setPrivacyKind : a -> { b | privacyKind : a } -> { b | privacyKind : a }
setPrivacyKind value model =
    { model | privacyKind = value }


setEmails : a -> { b | emails : a } -> { b | emails : a }
setEmails value model =
    { model | emails = value }


setAuth : a -> { b | auth : a } -> { b | auth : a }
setAuth value model =
    { model | auth = value }


setQuestion : a -> { b | question : a } -> { b | question : a }
setQuestion value model =
    { model | question = value }


setPrivacy : a -> { b | privacy : a } -> { b | privacy : a }
setPrivacy value model =
    { model | privacy = value }


setCertainty : a -> { b | certainty : a } -> { b | certainty : a }
setCertainty value model =
    { model | certainty = value }


setMaximumStakeCents : a -> { b | maximumStakeCents : a } -> { b | maximumStakeCents : a }
setMaximumStakeCents value model =
    { model | maximumStakeCents = value }


setOpenSeconds : a -> { b | openSeconds : a } -> { b | openSeconds : a }
setOpenSeconds value model =
    { model | openSeconds = value }


setSpecialRules : a -> { b | specialRules : a } -> { b | specialRules : a }
setSpecialRules value model =
    { model | specialRules = value }


setCreateMarketResult : a -> { b | createMarketResult : a } -> { b | createMarketResult : a }
setCreateMarketResult value model =
    { model | createMarketResult = value }


setAuthError : a -> { b | authError : a } -> { b | authError : a }
setAuthError value model =
    { model | authError = value }


setMarketId : a -> { b | marketId : a } -> { b | marketId : a }
setMarketId value model =
    { model | marketId = value }


setGetMarketResult : a -> { b | getMarketResult : a } -> { b | getMarketResult : a }
setGetMarketResult value model =
    { model | getMarketResult = value }


setRemainingYesStakeCents : a -> { b | remainingYesStakeCents : a } -> { b | remainingYesStakeCents : a }
setRemainingYesStakeCents value model =
    { model | remainingYesStakeCents = value }


setRemainingNoStakeCents : a -> { b | remainingNoStakeCents : a } -> { b | remainingNoStakeCents : a }
setRemainingNoStakeCents value model =
    { model | remainingNoStakeCents = value }


setCreatedUnixtime : a -> { b | createdUnixtime : a } -> { b | createdUnixtime : a }
setCreatedUnixtime value model =
    { model | createdUnixtime = value }


setClosesUnixtime : a -> { b | closesUnixtime : a } -> { b | closesUnixtime : a }
setClosesUnixtime value model =
    { model | closesUnixtime = value }


setCreator : a -> { b | creator : a } -> { b | creator : a }
setCreator value model =
    { model | creator = value }


setResolution : a -> { b | resolution : a } -> { b | resolution : a }
setResolution value model =
    { model | resolution = value }


setExpectedResolution : a -> { b | expectedResolution : a } -> { b | expectedResolution : a }
setExpectedResolution value model =
    { model | expectedResolution = value }


setStake : a -> { b | stake : a } -> { b | stake : a }
setStake value model =
    { model | stake = value }


setStakeResult : a -> { b | stakeResult : a } -> { b | stakeResult : a }
setStakeResult value model =
    { model | stakeResult = value }


setGetUserResult : a -> { b | getUserResult : a } -> { b | getUserResult : a }
setGetUserResult value model =
    { model | getUserResult = value }


setTrustedByRequester : a -> { b | trustedByRequester : a } -> { b | trustedByRequester : a }
setTrustedByRequester value model =
    { model | trustedByRequester = value }


setTrustsRequester : a -> { b | trustsRequester : a } -> { b | trustsRequester : a }
setTrustsRequester value model =
    { model | trustsRequester = value }


setEmailToTrust : a -> { b | emailToTrust : a } -> { b | emailToTrust : a }
setEmailToTrust value model =
    { model | emailToTrust = value }


setResult : a -> { b | result : a } -> { b | result : a }
setResult value model =
    { model | result = value }
