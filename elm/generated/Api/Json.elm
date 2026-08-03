module Api.Json exposing
    ( encodeAcceptInvitationRequest, encodeAuthSuccess, encodeCertaintyRange, encodeChangePasswordRequest, encodeCheckInvitationRequest, encodeCheckInvitationResponse, encodeCreatePredictionRequest
    , encodeCreatePredictionResponse, encodeEmpty, encodeFollowRequest, encodeGenericUserInfo, encodeGetPredictionRequest, encodeGetSettingsRequest, encodeGetUserRequest
    , encodeHTTPValidationError, encodeInvitation, encodeListMyStakesRequest, encodeListPredictionsRequest, encodeLogInUsernameRequest, encodePredictionFollowingStatus, encodePredictionViewPrivacy
    , encodePredictionsById, encodeRegisterUsernameRequest, encodeRelationship, encodeResolution, encodeResolutionEvent, encodeResolveRequest, encodeSavedCreatedPredictionFormState
    , encodeSendInvitationRequest, encodeSendVerificationEmailRequest, encodeSetTrustedRequest, encodeSignOutRequest, encodeStakeRequest, encodeTrade, encodeTradeState
    , encodeUserPredictionView, encodeValidationError, encodeWhoamiRequest, encodeWhoamiResponse
    , decodeAcceptInvitationRequest, decodeAuthSuccess, decodeCertaintyRange, decodeChangePasswordRequest, decodeCheckInvitationRequest, decodeCheckInvitationResponse, decodeCreatePredictionRequest
    , decodeCreatePredictionResponse, decodeEmpty, decodeFollowRequest, decodeGenericUserInfo, decodeGetPredictionRequest, decodeGetSettingsRequest, decodeGetUserRequest
    , decodeHTTPValidationError, decodeInvitation, decodeListMyStakesRequest, decodeListPredictionsRequest, decodeLogInUsernameRequest, decodePredictionFollowingStatus, decodePredictionViewPrivacy
    , decodePredictionsById, decodeRegisterUsernameRequest, decodeRelationship, decodeResolution, decodeResolutionEvent, decodeResolveRequest, decodeSavedCreatedPredictionFormState
    , decodeSendInvitationRequest, decodeSendVerificationEmailRequest, decodeSetTrustedRequest, decodeSignOutRequest, decodeStakeRequest, decodeTrade, decodeTradeState
    , decodeUserPredictionView, decodeValidationError, decodeWhoamiRequest, decodeWhoamiResponse
    )

{-|
## Encoders

@docs encodeAcceptInvitationRequest, encodeAuthSuccess, encodeCertaintyRange, encodeChangePasswordRequest, encodeCheckInvitationRequest, encodeCheckInvitationResponse
@docs encodeCreatePredictionRequest, encodeCreatePredictionResponse, encodeEmpty, encodeFollowRequest, encodeGenericUserInfo, encodeGetPredictionRequest
@docs encodeGetSettingsRequest, encodeGetUserRequest, encodeHTTPValidationError, encodeInvitation, encodeListMyStakesRequest, encodeListPredictionsRequest
@docs encodeLogInUsernameRequest, encodePredictionFollowingStatus, encodePredictionViewPrivacy, encodePredictionsById, encodeRegisterUsernameRequest, encodeRelationship
@docs encodeResolution, encodeResolutionEvent, encodeResolveRequest, encodeSavedCreatedPredictionFormState, encodeSendInvitationRequest, encodeSendVerificationEmailRequest
@docs encodeSetTrustedRequest, encodeSignOutRequest, encodeStakeRequest, encodeTrade, encodeTradeState, encodeUserPredictionView
@docs encodeValidationError, encodeWhoamiRequest, encodeWhoamiResponse

## Decoders

@docs decodeAcceptInvitationRequest, decodeAuthSuccess, decodeCertaintyRange, decodeChangePasswordRequest, decodeCheckInvitationRequest, decodeCheckInvitationResponse
@docs decodeCreatePredictionRequest, decodeCreatePredictionResponse, decodeEmpty, decodeFollowRequest, decodeGenericUserInfo, decodeGetPredictionRequest
@docs decodeGetSettingsRequest, decodeGetUserRequest, decodeHTTPValidationError, decodeInvitation, decodeListMyStakesRequest, decodeListPredictionsRequest
@docs decodeLogInUsernameRequest, decodePredictionFollowingStatus, decodePredictionViewPrivacy, decodePredictionsById, decodeRegisterUsernameRequest, decodeRelationship
@docs decodeResolution, decodeResolutionEvent, decodeResolveRequest, decodeSavedCreatedPredictionFormState, decodeSendInvitationRequest, decodeSendVerificationEmailRequest
@docs decodeSetTrustedRequest, decodeSignOutRequest, decodeStakeRequest, decodeTrade, decodeTradeState, decodeUserPredictionView
@docs decodeValidationError, decodeWhoamiRequest, decodeWhoamiResponse
-}


import Api.Types
import Dict
import Json.Decode
import Json.Encode
import OpenApi.Common


encodeAcceptInvitationRequest :
    Api.Types.AcceptInvitationRequest -> Json.Encode.Value
encodeAcceptInvitationRequest rec =
    Json.Encode.object [ ( "nonce", Json.Encode.string rec.nonce ) ]


encodeAuthSuccess : Api.Types.AuthSuccess -> Json.Encode.Value
encodeAuthSuccess rec =
    Json.Encode.object
        [ ( "owner", Json.Encode.string rec.owner )
        , ( "userInfo", encodeGenericUserInfo rec.userInfo )
        ]


encodeCertaintyRange : Api.Types.CertaintyRange -> Json.Encode.Value
encodeCertaintyRange rec =
    Json.Encode.object
        [ ( "high", Json.Encode.float rec.high )
        , ( "low", Json.Encode.float rec.low )
        ]


encodeChangePasswordRequest :
    Api.Types.ChangePasswordRequest -> Json.Encode.Value
encodeChangePasswordRequest rec =
    Json.Encode.object
        [ ( "newPassword", Json.Encode.string rec.newPassword )
        , ( "oldPassword", Json.Encode.string rec.oldPassword )
        ]


encodeCheckInvitationRequest :
    Api.Types.CheckInvitationRequest -> Json.Encode.Value
encodeCheckInvitationRequest rec =
    Json.Encode.object [ ( "nonce", Json.Encode.string rec.nonce ) ]


encodeCheckInvitationResponse :
    Api.Types.CheckInvitationResponse -> Json.Encode.Value
encodeCheckInvitationResponse rec =
    Json.Encode.object
        [ ( "inviter", Json.Encode.string rec.inviter )
        , ( "recipient", Json.Encode.string rec.recipient )
        ]


encodeCreatePredictionRequest :
    Api.Types.CreatePredictionRequest -> Json.Encode.Value
encodeCreatePredictionRequest rec =
    Json.Encode.object
        [ ( "certainty", encodeCertaintyRange rec.certainty )
        , ( "maximumStakeCents", Json.Encode.int rec.maximumStakeCents )
        , ( "openSeconds", Json.Encode.int rec.openSeconds )
        , ( "prediction", Json.Encode.string rec.prediction )
        , ( "resolvesAtUnixtime", Json.Encode.float rec.resolvesAtUnixtime )
        , ( "specialRules", Json.Encode.string rec.specialRules )
        , ( "viewPrivacy", encodePredictionViewPrivacy rec.viewPrivacy )
        ]


encodeCreatePredictionResponse :
    Api.Types.CreatePredictionResponse -> Json.Encode.Value
encodeCreatePredictionResponse rec =
    Json.Encode.object
        [ ( "newPredictionId", Json.Encode.string rec.newPredictionId ) ]


encodeEmpty : Api.Types.Empty -> Json.Encode.Value
encodeEmpty rec =
    Json.Encode.object []


encodeFollowRequest : Api.Types.FollowRequest -> Json.Encode.Value
encodeFollowRequest rec =
    Json.Encode.object
        [ ( "follow", Json.Encode.bool rec.follow )
        , ( "predictionId", Json.Encode.string rec.predictionId )
        ]


encodeGenericUserInfo : Api.Types.GenericUserInfo -> Json.Encode.Value
encodeGenericUserInfo rec =
    Json.Encode.object
        [ ( "emailAddress", Json.Encode.string rec.emailAddress )
        , ( "invitations"
          , Json.Encode.dict Basics.identity encodeInvitation rec.invitations
          )
        , ( "relationships"
          , Json.Encode.dict
                Basics.identity
                encodeRelationship
                rec.relationships
          )
        ]


encodeGetPredictionRequest : Api.Types.GetPredictionRequest -> Json.Encode.Value
encodeGetPredictionRequest rec =
    Json.Encode.object
        [ ( "predictionId", Json.Encode.string rec.predictionId ) ]


encodeGetSettingsRequest : Api.Types.GetSettingsRequest -> Json.Encode.Value
encodeGetSettingsRequest rec =
    Json.Encode.object
        [ ( "includeRelationshipsWithUsers"
          , Json.Encode.list
                Json.Encode.string
                rec.includeRelationshipsWithUsers
          )
        ]


encodeGetUserRequest : Api.Types.GetUserRequest -> Json.Encode.Value
encodeGetUserRequest rec =
    Json.Encode.object [ ( "who", Json.Encode.string rec.who ) ]


encodeHTTPValidationError : Api.Types.HTTPValidationError -> Json.Encode.Value
encodeHTTPValidationError rec =
    Json.Encode.object
        (List.filterMap
             Basics.identity
             [ Maybe.map
                 (\mapUnpack ->
                    ( "detail"
                    , Json.Encode.list encodeValidationError mapUnpack
                    )
                 )
                 rec.detail
             ]
        )


encodeInvitation : Api.Types.Invitation -> Json.Encode.Value
encodeInvitation rec =
    Json.Encode.object []


encodeListMyStakesRequest : Api.Types.ListMyStakesRequest -> Json.Encode.Value
encodeListMyStakesRequest rec =
    Json.Encode.object []


encodeListPredictionsRequest :
    Api.Types.ListPredictionsRequest -> Json.Encode.Value
encodeListPredictionsRequest rec =
    Json.Encode.object [ ( "creator", Json.Encode.string rec.creator ) ]


encodeLogInUsernameRequest : Api.Types.LogInUsernameRequest -> Json.Encode.Value
encodeLogInUsernameRequest rec =
    Json.Encode.object
        [ ( "password", Json.Encode.string rec.password )
        , ( "username", Json.Encode.string rec.username )
        ]


encodePredictionFollowingStatus :
    Api.Types.PredictionFollowingStatus -> Json.Encode.Value
encodePredictionFollowingStatus rec =
    Json.Encode.string (Api.Types.predictionFollowingStatusToString rec)


encodePredictionViewPrivacy :
    Api.Types.PredictionViewPrivacy -> Json.Encode.Value
encodePredictionViewPrivacy rec =
    Json.Encode.string (Api.Types.predictionViewPrivacyToString rec)


encodePredictionsById : Api.Types.PredictionsById -> Json.Encode.Value
encodePredictionsById rec =
    Json.Encode.object
        [ ( "predictions"
          , Json.Encode.dict
                Basics.identity
                encodeUserPredictionView
                rec.predictions
          )
        ]


encodeRegisterUsernameRequest :
    Api.Types.RegisterUsernameRequest -> Json.Encode.Value
encodeRegisterUsernameRequest rec =
    Json.Encode.object
        [ ( "password", Json.Encode.string rec.password )
        , ( "proofOfEmailToken", Json.Encode.string rec.proofOfEmailToken )
        , ( "username", Json.Encode.string rec.username )
        ]


encodeRelationship : Api.Types.Relationship -> Json.Encode.Value
encodeRelationship rec =
    Json.Encode.object
        [ ( "trustedByYou", Json.Encode.bool rec.trustedByYou )
        , ( "trustsYou", Json.Encode.bool rec.trustsYou )
        ]


encodeResolution : Api.Types.Resolution -> Json.Encode.Value
encodeResolution rec =
    Json.Encode.string (Api.Types.resolutionToString rec)


encodeResolutionEvent : Api.Types.ResolutionEvent -> Json.Encode.Value
encodeResolutionEvent (Api.Types.ResolutionEvent val) =
    Json.Encode.object
        (List.filterMap
             Basics.identity
             [ Just ( "notes", Json.Encode.string val.notes )
             , Maybe.map
                 (\mapUnpack ->
                    ( "priorRevision"
                    , case mapUnpack of
                        OpenApi.Common.Null ->
                            Json.Encode.null
                      
                        OpenApi.Common.Present value ->
                            encodeResolutionEvent value
                    )
                 )
                 val.priorRevision
             , Just ( "resolution", encodeResolution val.resolution )
             , Just ( "unixtime", Json.Encode.float val.unixtime )
             ]
        )


encodeResolveRequest : Api.Types.ResolveRequest -> Json.Encode.Value
encodeResolveRequest rec =
    Json.Encode.object
        [ ( "notes", Json.Encode.string rec.notes )
        , ( "predictionId", Json.Encode.string rec.predictionId )
        , ( "resolution", encodeResolution rec.resolution )
        ]


encodeSavedCreatedPredictionFormState :
    Api.Types.SavedCreatedPredictionFormState -> Json.Encode.Value
encodeSavedCreatedPredictionFormState rec =
    Json.Encode.object
        [ ( "highPField", Json.Encode.string rec.highPField )
        , ( "lowPField", Json.Encode.string rec.lowPField )
        , ( "openForSecondsField", Json.Encode.string rec.openForSecondsField )
        , ( "openForUnitField", Json.Encode.string rec.openForUnitField )
        , ( "predictionField", Json.Encode.string rec.predictionField )
        , ( "resolvesAtField", Json.Encode.string rec.resolvesAtField )
        , ( "specialRulesField", Json.Encode.string rec.specialRulesField )
        , ( "stakeField", Json.Encode.string rec.stakeField )
        , ( "viewPrivacyField", Json.Encode.string rec.viewPrivacyField )
        ]


encodeSendInvitationRequest :
    Api.Types.SendInvitationRequest -> Json.Encode.Value
encodeSendInvitationRequest rec =
    Json.Encode.object [ ( "recipient", Json.Encode.string rec.recipient ) ]


encodeSendVerificationEmailRequest :
    Api.Types.SendVerificationEmailRequest -> Json.Encode.Value
encodeSendVerificationEmailRequest rec =
    Json.Encode.object
        [ ( "emailAddress", Json.Encode.string rec.emailAddress ) ]


encodeSetTrustedRequest : Api.Types.SetTrustedRequest -> Json.Encode.Value
encodeSetTrustedRequest rec =
    Json.Encode.object
        [ ( "trusted", Json.Encode.bool rec.trusted )
        , ( "who", Json.Encode.string rec.who )
        ]


encodeSignOutRequest : Api.Types.SignOutRequest -> Json.Encode.Value
encodeSignOutRequest rec =
    Json.Encode.object []


encodeStakeRequest : Api.Types.StakeRequest -> Json.Encode.Value
encodeStakeRequest rec =
    Json.Encode.object
        [ ( "bettorIsASkeptic", Json.Encode.bool rec.bettorIsASkeptic )
        , ( "bettorStakeCents", Json.Encode.int rec.bettorStakeCents )
        , ( "predictionId", Json.Encode.string rec.predictionId )
        ]


encodeTrade : Api.Types.Trade -> Json.Encode.Value
encodeTrade rec =
    Json.Encode.object
        [ ( "bettor", Json.Encode.string rec.bettor )
        , ( "bettorIsASkeptic", Json.Encode.bool rec.bettorIsASkeptic )
        , ( "bettorStakeCents", Json.Encode.int rec.bettorStakeCents )
        , ( "creatorStakeCents", Json.Encode.int rec.creatorStakeCents )
        , ( "notes", Json.Encode.string rec.notes )
        , ( "state", encodeTradeState rec.state )
        , ( "transactedUnixtime", Json.Encode.float rec.transactedUnixtime )
        , ( "updatedUnixtime", Json.Encode.float rec.updatedUnixtime )
        ]


encodeTradeState : Api.Types.TradeState -> Json.Encode.Value
encodeTradeState rec =
    Json.Encode.string (Api.Types.tradeStateToString rec)


encodeUserPredictionView : Api.Types.UserPredictionView -> Json.Encode.Value
encodeUserPredictionView rec =
    Json.Encode.object
        (List.filterMap
             Basics.identity
             [ Just ( "certainty", encodeCertaintyRange rec.certainty )
             , Just ( "closesUnixtime", Json.Encode.float rec.closesUnixtime )
             , Just ( "createdUnixtime", Json.Encode.float rec.createdUnixtime )
             , Just ( "creator", Json.Encode.string rec.creator )
             , Just
                 ( "maximumStakeCents", Json.Encode.int rec.maximumStakeCents )
             , Just ( "prediction", Json.Encode.string rec.prediction )
             , Just
                 ( "remainingStakeCentsVsBelievers"
                 , Json.Encode.int rec.remainingStakeCentsVsBelievers
                 )
             , Just
                 ( "remainingStakeCentsVsSkeptics"
                 , Json.Encode.int rec.remainingStakeCentsVsSkeptics
                 )
             , Maybe.map
                 (\mapUnpack ->
                    ( "resolution"
                    , case mapUnpack of
                        OpenApi.Common.Null ->
                            Json.Encode.null
                      
                        OpenApi.Common.Present value ->
                            encodeResolutionEvent value
                    )
                 )
                 rec.resolution
             , Just
                 ( "resolvesAtUnixtime"
                 , Json.Encode.float rec.resolvesAtUnixtime
                 )
             , Just ( "specialRules", Json.Encode.string rec.specialRules )
             , Just
                 ( "yourFollowingStatus"
                 , encodePredictionFollowingStatus rec.yourFollowingStatus
                 )
             , Just
                 ( "yourTrades", Json.Encode.list encodeTrade rec.yourTrades )
             ]
        )


encodeValidationError : Api.Types.ValidationError -> Json.Encode.Value
encodeValidationError rec =
    Json.Encode.object
        (List.filterMap
             Basics.identity
             [ Maybe.map
                 (\mapUnpack -> ( "ctx", Json.Encode.object [] ))
                 rec.ctx
             , Maybe.map
                 (\mapUnpack -> ( "input", Basics.identity mapUnpack ))
                 rec.input
             , Just
                 ( "loc"
                 , Json.Encode.list
                       (\rec0 ->
                            case rec0 of
                                Api.Types.Int_Or_String__Int content ->
                                    Json.Encode.int content
                            
                                Api.Types.Int_Or_String__String content ->
                                    Json.Encode.string content
                       )
                       rec.loc
                 )
             , Just ( "msg", Json.Encode.string rec.msg )
             , Just ( "type", Json.Encode.string rec.type_ )
             ]
        )


encodeWhoamiRequest : Api.Types.WhoamiRequest -> Json.Encode.Value
encodeWhoamiRequest rec =
    Json.Encode.object []


encodeWhoamiResponse : Api.Types.WhoamiResponse -> Json.Encode.Value
encodeWhoamiResponse rec =
    Json.Encode.object [ ( "username", Json.Encode.string rec.username ) ]


decodeAcceptInvitationRequest :
    Json.Decode.Decoder Api.Types.AcceptInvitationRequest
decodeAcceptInvitationRequest =
    Json.Decode.succeed (\nonce -> { nonce = nonce })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "nonce" Json.Decode.string)


decodeAuthSuccess : Json.Decode.Decoder Api.Types.AuthSuccess
decodeAuthSuccess =
    Json.Decode.succeed
        (\owner userInfo -> { owner = owner, userInfo = userInfo })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "owner" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "userInfo" decodeGenericUserInfo)


decodeCertaintyRange : Json.Decode.Decoder Api.Types.CertaintyRange
decodeCertaintyRange =
    Json.Decode.succeed (\high low -> { high = high, low = low })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "high" Json.Decode.float)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "low" Json.Decode.float)


decodeChangePasswordRequest :
    Json.Decode.Decoder Api.Types.ChangePasswordRequest
decodeChangePasswordRequest =
    Json.Decode.succeed
        (\newPassword oldPassword ->
             { newPassword = newPassword, oldPassword = oldPassword }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "newPassword" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "oldPassword" Json.Decode.string)


decodeCheckInvitationRequest :
    Json.Decode.Decoder Api.Types.CheckInvitationRequest
decodeCheckInvitationRequest =
    Json.Decode.succeed (\nonce -> { nonce = nonce })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "nonce" Json.Decode.string)


decodeCheckInvitationResponse :
    Json.Decode.Decoder Api.Types.CheckInvitationResponse
decodeCheckInvitationResponse =
    Json.Decode.succeed
        (\inviter recipient -> { inviter = inviter, recipient = recipient })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "inviter" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "recipient" Json.Decode.string)


decodeCreatePredictionRequest :
    Json.Decode.Decoder Api.Types.CreatePredictionRequest
decodeCreatePredictionRequest =
    Json.Decode.succeed
        (\certainty maximumStakeCents openSeconds prediction resolvesAtUnixtime specialRules viewPrivacy ->
             { certainty = certainty
             , maximumStakeCents = maximumStakeCents
             , openSeconds = openSeconds
             , prediction = prediction
             , resolvesAtUnixtime = resolvesAtUnixtime
             , specialRules = specialRules
             , viewPrivacy = viewPrivacy
             }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "certainty" decodeCertaintyRange)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "maximumStakeCents" Json.Decode.int)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "openSeconds" Json.Decode.int)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "prediction" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "resolvesAtUnixtime" Json.Decode.float)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "specialRules" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "viewPrivacy" decodePredictionViewPrivacy)


decodeCreatePredictionResponse :
    Json.Decode.Decoder Api.Types.CreatePredictionResponse
decodeCreatePredictionResponse =
    Json.Decode.succeed
        (\newPredictionId -> { newPredictionId = newPredictionId })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "newPredictionId" Json.Decode.string)


decodeEmpty : Json.Decode.Decoder Api.Types.Empty
decodeEmpty =
    Json.Decode.succeed {}


decodeFollowRequest : Json.Decode.Decoder Api.Types.FollowRequest
decodeFollowRequest =
    Json.Decode.succeed
        (\follow predictionId ->
             { follow = follow, predictionId = predictionId }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "follow" Json.Decode.bool)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "predictionId" Json.Decode.string)


decodeGenericUserInfo : Json.Decode.Decoder Api.Types.GenericUserInfo
decodeGenericUserInfo =
    Json.Decode.succeed
        (\emailAddress invitations relationships ->
             { emailAddress = emailAddress
             , invitations = invitations
             , relationships = relationships
             }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "emailAddress" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field
                    "invitations"
                    (Json.Decode.dict decodeInvitation)
               )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field
                    "relationships"
                    (Json.Decode.dict decodeRelationship)
               )


decodeGetPredictionRequest : Json.Decode.Decoder Api.Types.GetPredictionRequest
decodeGetPredictionRequest =
    Json.Decode.succeed (\predictionId -> { predictionId = predictionId })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "predictionId" Json.Decode.string)


decodeGetSettingsRequest : Json.Decode.Decoder Api.Types.GetSettingsRequest
decodeGetSettingsRequest =
    Json.Decode.succeed
        (\includeRelationshipsWithUsers ->
             { includeRelationshipsWithUsers = includeRelationshipsWithUsers }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field
                    "includeRelationshipsWithUsers"
                    (Json.Decode.list Json.Decode.string)
               )


decodeGetUserRequest : Json.Decode.Decoder Api.Types.GetUserRequest
decodeGetUserRequest =
    Json.Decode.succeed (\who -> { who = who })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "who" Json.Decode.string)


decodeHTTPValidationError : Json.Decode.Decoder Api.Types.HTTPValidationError
decodeHTTPValidationError =
    Json.Decode.succeed (\detail -> { detail = detail })
        |> OpenApi.Common.jsonDecodeAndMap
               (OpenApi.Common.decodeOptionalField
                    "detail"
                    (Json.Decode.list decodeValidationError)
               )


decodeInvitation : Json.Decode.Decoder Api.Types.Invitation
decodeInvitation =
    Json.Decode.succeed {}


decodeListMyStakesRequest : Json.Decode.Decoder Api.Types.ListMyStakesRequest
decodeListMyStakesRequest =
    Json.Decode.succeed {}


decodeListPredictionsRequest :
    Json.Decode.Decoder Api.Types.ListPredictionsRequest
decodeListPredictionsRequest =
    Json.Decode.succeed (\creator -> { creator = creator })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "creator" Json.Decode.string)


decodeLogInUsernameRequest : Json.Decode.Decoder Api.Types.LogInUsernameRequest
decodeLogInUsernameRequest =
    Json.Decode.succeed
        (\password username -> { password = password, username = username })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "password" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "username" Json.Decode.string)


decodePredictionFollowingStatus :
    Json.Decode.Decoder Api.Types.PredictionFollowingStatus
decodePredictionFollowingStatus =
    Json.Decode.andThen
        (\andThenUnpack ->
             case Api.Types.predictionFollowingStatusFromString andThenUnpack of
                 Maybe.Just a ->
                     Json.Decode.succeed a
             
                 Maybe.Nothing ->
                     Json.Decode.fail
                         (andThenUnpack ++
                              " is not a valid PredictionFollowingStatus"
                         )
        )
        Json.Decode.string


decodePredictionViewPrivacy :
    Json.Decode.Decoder Api.Types.PredictionViewPrivacy
decodePredictionViewPrivacy =
    Json.Decode.andThen
        (\andThenUnpack ->
             case Api.Types.predictionViewPrivacyFromString andThenUnpack of
                 Maybe.Just a ->
                     Json.Decode.succeed a
             
                 Maybe.Nothing ->
                     Json.Decode.fail
                         (andThenUnpack ++
                              " is not a valid PredictionViewPrivacy"
                         )
        )
        Json.Decode.string


decodePredictionsById : Json.Decode.Decoder Api.Types.PredictionsById
decodePredictionsById =
    Json.Decode.succeed (\predictions -> { predictions = predictions })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field
                    "predictions"
                    (Json.Decode.dict decodeUserPredictionView)
               )


decodeRegisterUsernameRequest :
    Json.Decode.Decoder Api.Types.RegisterUsernameRequest
decodeRegisterUsernameRequest =
    Json.Decode.succeed
        (\password proofOfEmailToken username ->
             { password = password
             , proofOfEmailToken = proofOfEmailToken
             , username = username
             }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "password" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "proofOfEmailToken" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "username" Json.Decode.string)


decodeRelationship : Json.Decode.Decoder Api.Types.Relationship
decodeRelationship =
    Json.Decode.succeed
        (\trustedByYou trustsYou ->
             { trustedByYou = trustedByYou, trustsYou = trustsYou }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "trustedByYou" Json.Decode.bool)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "trustsYou" Json.Decode.bool)


decodeResolution : Json.Decode.Decoder Api.Types.Resolution
decodeResolution =
    Json.Decode.andThen
        (\andThenUnpack ->
             case Api.Types.resolutionFromString andThenUnpack of
                 Maybe.Just a ->
                     Json.Decode.succeed a
             
                 Maybe.Nothing ->
                     Json.Decode.fail
                         (andThenUnpack ++ " is not a valid Resolution")
        )
        Json.Decode.string


decodeResolutionEvent : Json.Decode.Decoder Api.Types.ResolutionEvent
decodeResolutionEvent =
    Json.Decode.map
        Api.Types.ResolutionEvent
        (Json.Decode.lazy
             (\lazyUnpack ->
                  Json.Decode.succeed
                      (\notes priorRevision resolution unixtime ->
                           { notes = notes
                           , priorRevision = priorRevision
                           , resolution = resolution
                           , unixtime = unixtime
                           }
                      )
                      |> OpenApi.Common.jsonDecodeAndMap
                             (Json.Decode.field "notes" Json.Decode.string)
                      |> OpenApi.Common.jsonDecodeAndMap
                             (OpenApi.Common.decodeOptionalField
                                  "priorRevision"
                                  (Json.Decode.oneOf
                                       [ Json.Decode.map
                                           OpenApi.Common.Present
                                           decodeResolutionEvent
                                       , Json.Decode.null (OpenApi.Common.Null)
                                       ]
                                  )
                             )
                      |> OpenApi.Common.jsonDecodeAndMap
                             (Json.Decode.field "resolution" decodeResolution)
                      |> OpenApi.Common.jsonDecodeAndMap
                             (Json.Decode.field "unixtime" Json.Decode.float)
             )
        )


decodeResolveRequest : Json.Decode.Decoder Api.Types.ResolveRequest
decodeResolveRequest =
    Json.Decode.succeed
        (\notes predictionId resolution ->
             { notes = notes
             , predictionId = predictionId
             , resolution = resolution
             }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "notes" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "predictionId" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "resolution" decodeResolution)


decodeSavedCreatedPredictionFormState :
    Json.Decode.Decoder Api.Types.SavedCreatedPredictionFormState
decodeSavedCreatedPredictionFormState =
    Json.Decode.succeed
        (\highPField lowPField openForSecondsField openForUnitField predictionField resolvesAtField specialRulesField stakeField viewPrivacyField ->
             { highPField = highPField
             , lowPField = lowPField
             , openForSecondsField = openForSecondsField
             , openForUnitField = openForUnitField
             , predictionField = predictionField
             , resolvesAtField = resolvesAtField
             , specialRulesField = specialRulesField
             , stakeField = stakeField
             , viewPrivacyField = viewPrivacyField
             }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "highPField" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "lowPField" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "openForSecondsField" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "openForUnitField" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "predictionField" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "resolvesAtField" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "specialRulesField" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "stakeField" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "viewPrivacyField" Json.Decode.string)


decodeSendInvitationRequest :
    Json.Decode.Decoder Api.Types.SendInvitationRequest
decodeSendInvitationRequest =
    Json.Decode.succeed (\recipient -> { recipient = recipient })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "recipient" Json.Decode.string)


decodeSendVerificationEmailRequest :
    Json.Decode.Decoder Api.Types.SendVerificationEmailRequest
decodeSendVerificationEmailRequest =
    Json.Decode.succeed (\emailAddress -> { emailAddress = emailAddress })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "emailAddress" Json.Decode.string)


decodeSetTrustedRequest : Json.Decode.Decoder Api.Types.SetTrustedRequest
decodeSetTrustedRequest =
    Json.Decode.succeed (\trusted who -> { trusted = trusted, who = who })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "trusted" Json.Decode.bool)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "who" Json.Decode.string)


decodeSignOutRequest : Json.Decode.Decoder Api.Types.SignOutRequest
decodeSignOutRequest =
    Json.Decode.succeed {}


decodeStakeRequest : Json.Decode.Decoder Api.Types.StakeRequest
decodeStakeRequest =
    Json.Decode.succeed
        (\bettorIsASkeptic bettorStakeCents predictionId ->
             { bettorIsASkeptic = bettorIsASkeptic
             , bettorStakeCents = bettorStakeCents
             , predictionId = predictionId
             }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "bettorIsASkeptic" Json.Decode.bool)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "bettorStakeCents" Json.Decode.int)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "predictionId" Json.Decode.string)


decodeTrade : Json.Decode.Decoder Api.Types.Trade
decodeTrade =
    Json.Decode.succeed
        (\bettor bettorIsASkeptic bettorStakeCents creatorStakeCents notes state transactedUnixtime updatedUnixtime ->
             { bettor = bettor
             , bettorIsASkeptic = bettorIsASkeptic
             , bettorStakeCents = bettorStakeCents
             , creatorStakeCents = creatorStakeCents
             , notes = notes
             , state = state
             , transactedUnixtime = transactedUnixtime
             , updatedUnixtime = updatedUnixtime
             }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "bettor" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "bettorIsASkeptic" Json.Decode.bool)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "bettorStakeCents" Json.Decode.int)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "creatorStakeCents" Json.Decode.int)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "notes" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "state" decodeTradeState)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "transactedUnixtime" Json.Decode.float)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "updatedUnixtime" Json.Decode.float)


decodeTradeState : Json.Decode.Decoder Api.Types.TradeState
decodeTradeState =
    Json.Decode.andThen
        (\andThenUnpack ->
             case Api.Types.tradeStateFromString andThenUnpack of
                 Maybe.Just a ->
                     Json.Decode.succeed a
             
                 Maybe.Nothing ->
                     Json.Decode.fail
                         (andThenUnpack ++ " is not a valid TradeState")
        )
        Json.Decode.string


decodeUserPredictionView : Json.Decode.Decoder Api.Types.UserPredictionView
decodeUserPredictionView =
    Json.Decode.succeed
        (\certainty closesUnixtime createdUnixtime creator maximumStakeCents prediction remainingStakeCentsVsBelievers remainingStakeCentsVsSkeptics resolution resolvesAtUnixtime specialRules yourFollowingStatus yourTrades ->
             { certainty = certainty
             , closesUnixtime = closesUnixtime
             , createdUnixtime = createdUnixtime
             , creator = creator
             , maximumStakeCents = maximumStakeCents
             , prediction = prediction
             , remainingStakeCentsVsBelievers = remainingStakeCentsVsBelievers
             , remainingStakeCentsVsSkeptics = remainingStakeCentsVsSkeptics
             , resolution = resolution
             , resolvesAtUnixtime = resolvesAtUnixtime
             , specialRules = specialRules
             , yourFollowingStatus = yourFollowingStatus
             , yourTrades = yourTrades
             }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "certainty" decodeCertaintyRange)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "closesUnixtime" Json.Decode.float)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "createdUnixtime" Json.Decode.float)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "creator" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "maximumStakeCents" Json.Decode.int)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "prediction" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field
                    "remainingStakeCentsVsBelievers"
                    Json.Decode.int
               )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field
                    "remainingStakeCentsVsSkeptics"
                    Json.Decode.int
               )
        |> OpenApi.Common.jsonDecodeAndMap
               (OpenApi.Common.decodeOptionalField
                    "resolution"
                    (Json.Decode.oneOf
                         [ Json.Decode.map
                             OpenApi.Common.Present
                             decodeResolutionEvent
                         , Json.Decode.null (OpenApi.Common.Null)
                         ]
                    )
               )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "resolvesAtUnixtime" Json.Decode.float)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "specialRules" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field
                    "yourFollowingStatus"
                    decodePredictionFollowingStatus
               )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "yourTrades" (Json.Decode.list decodeTrade))


decodeValidationError : Json.Decode.Decoder Api.Types.ValidationError
decodeValidationError =
    Json.Decode.succeed
        (\ctx input loc msg type_ ->
             { ctx = ctx, input = input, loc = loc, msg = msg, type_ = type_ }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (OpenApi.Common.decodeOptionalField
                    "ctx"
                    (Json.Decode.succeed {})
               )
        |> OpenApi.Common.jsonDecodeAndMap
               (OpenApi.Common.decodeOptionalField "input" Json.Decode.value)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field
                    "loc"
                    (Json.Decode.list
                         (Json.Decode.oneOf
                              [ Json.Decode.map
                                  Api.Types.Int_Or_String__Int
                                  Json.Decode.int
                              , Json.Decode.map
                                  Api.Types.Int_Or_String__String
                                  Json.Decode.string
                              ]
                         )
                    )
               )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "msg" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "type" Json.Decode.string)


decodeWhoamiRequest : Json.Decode.Decoder Api.Types.WhoamiRequest
decodeWhoamiRequest =
    Json.Decode.succeed {}


decodeWhoamiResponse : Json.Decode.Decoder Api.Types.WhoamiResponse
decodeWhoamiResponse =
    Json.Decode.succeed (\username -> { username = username })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "username" Json.Decode.string)