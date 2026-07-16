module Api.Json exposing
    ( encodeAuthSuccess, encodeAuthToken, encodeGenericUserInfo, encodeHTTPValidationError, encodeHashedPassword, encodeInvitation, encodeLogInUsernameError
    , encodeLogInUsernameRequest, encodeLogInUsernameResultError, encodeLogInUsernameResultOk, encodeLoginTypePassword, encodeRelationship, encodeValidationError
    , decodeAuthSuccess, decodeAuthToken, decodeGenericUserInfo, decodeHTTPValidationError, decodeHashedPassword, decodeInvitation, decodeLogInUsernameError
    , decodeLogInUsernameRequest, decodeLogInUsernameResultError, decodeLogInUsernameResultOk, decodeLoginTypePassword, decodeRelationship, decodeValidationError
    )

{-|
## Encoders

@docs encodeAuthSuccess, encodeAuthToken, encodeGenericUserInfo, encodeHTTPValidationError, encodeHashedPassword, encodeInvitation
@docs encodeLogInUsernameError, encodeLogInUsernameRequest, encodeLogInUsernameResultError, encodeLogInUsernameResultOk, encodeLoginTypePassword, encodeRelationship
@docs encodeValidationError

## Decoders

@docs decodeAuthSuccess, decodeAuthToken, decodeGenericUserInfo, decodeHTTPValidationError, decodeHashedPassword, decodeInvitation
@docs decodeLogInUsernameError, decodeLogInUsernameRequest, decodeLogInUsernameResultError, decodeLogInUsernameResultOk, decodeLoginTypePassword, decodeRelationship
@docs decodeValidationError
-}


import Api.Types
import Bytes
import Dict
import Json.Decode
import Json.Encode
import OpenApi.Common


encodeAuthSuccess : Api.Types.AuthSuccess -> Json.Encode.Value
encodeAuthSuccess rec =
    Json.Encode.object
        [ ( "token", encodeAuthToken rec.token )
        , ( "user_info", encodeGenericUserInfo rec.user_info )
        ]


encodeAuthToken : Api.Types.AuthToken -> Json.Encode.Value
encodeAuthToken rec =
    Json.Encode.object
        [ ( "expires_unixtime", Json.Encode.float rec.expires_unixtime )
        , ( "hmac_of_rest", OpenApi.Common.encodeStringByte rec.hmac_of_rest )
        , ( "minted_unixtime", Json.Encode.float rec.minted_unixtime )
        , ( "owner", Json.Encode.string rec.owner )
        ]


encodeGenericUserInfo : Api.Types.GenericUserInfo -> Json.Encode.Value
encodeGenericUserInfo rec =
    Json.Encode.object
        [ ( "email_address", Json.Encode.string rec.email_address )
        , ( "invitations"
          , Json.Encode.dict Basics.identity encodeInvitation rec.invitations
          )
        , ( "login_type"
          , case rec.login_type of
                OpenApi.Common.Null ->
                    Json.Encode.null
            
                OpenApi.Common.Present value ->
                    encodeLoginTypePassword value
          )
        , ( "relationships"
          , Json.Encode.dict
                Basics.identity
                encodeRelationship
                rec.relationships
          )
        ]


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


encodeHashedPassword : Api.Types.HashedPassword -> Json.Encode.Value
encodeHashedPassword rec =
    Json.Encode.object
        [ ( "salt", OpenApi.Common.encodeStringByte rec.salt )
        , ( "scrypt", OpenApi.Common.encodeStringByte rec.scrypt )
        ]


encodeInvitation : Api.Types.Invitation -> Json.Encode.Value
encodeInvitation rec =
    Json.Encode.object []


encodeLogInUsernameError : Api.Types.LogInUsernameError -> Json.Encode.Value
encodeLogInUsernameError rec =
    Json.Encode.object [ ( "catchall", Json.Encode.string rec.catchall ) ]


encodeLogInUsernameRequest : Api.Types.LogInUsernameRequest -> Json.Encode.Value
encodeLogInUsernameRequest rec =
    Json.Encode.object
        [ ( "password", Json.Encode.string rec.password )
        , ( "username", Json.Encode.string rec.username )
        ]


encodeLogInUsernameResultError :
    Api.Types.LogInUsernameResultError -> Json.Encode.Value
encodeLogInUsernameResultError rec =
    Json.Encode.object
        (List.filterMap
             Basics.identity
             [ Just ( "error", encodeLogInUsernameError rec.error )
             , Maybe.map
                 (\mapUnpack ->
                    ( "log_in_username_result", Json.Encode.string mapUnpack )
                 )
                 rec.log_in_username_result
             ]
        )


encodeLogInUsernameResultOk :
    Api.Types.LogInUsernameResultOk -> Json.Encode.Value
encodeLogInUsernameResultOk rec =
    Json.Encode.object
        (List.filterMap
             Basics.identity
             [ Maybe.map
                 (\mapUnpack ->
                    ( "log_in_username_result", Json.Encode.string mapUnpack )
                 )
                 rec.log_in_username_result
             , Just ( "ok", encodeAuthSuccess rec.ok )
             ]
        )


encodeLoginTypePassword : Api.Types.LoginTypePassword -> Json.Encode.Value
encodeLoginTypePassword rec =
    Json.Encode.object
        (List.filterMap
             Basics.identity
             [ Just
                 ( "login_password", encodeHashedPassword rec.login_password )
             , Maybe.map
                 (\mapUnpack ->
                    ( "login_type_kind", Json.Encode.string mapUnpack )
                 )
                 rec.login_type_kind
             ]
        )


encodeRelationship : Api.Types.Relationship -> Json.Encode.Value
encodeRelationship rec =
    Json.Encode.object
        [ ( "trusted_by_you", Json.Encode.bool rec.trusted_by_you )
        , ( "trusts_you", Json.Encode.bool rec.trusts_you )
        ]


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


decodeAuthSuccess : Json.Decode.Decoder Api.Types.AuthSuccess
decodeAuthSuccess =
    Json.Decode.succeed
        (\token user_info -> { token = token, user_info = user_info })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "token" decodeAuthToken)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "user_info" decodeGenericUserInfo)


decodeAuthToken : Json.Decode.Decoder Api.Types.AuthToken
decodeAuthToken =
    Json.Decode.succeed
        (\expires_unixtime hmac_of_rest minted_unixtime owner ->
             { expires_unixtime = expires_unixtime
             , hmac_of_rest = hmac_of_rest
             , minted_unixtime = minted_unixtime
             , owner = owner
             }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "expires_unixtime" Json.Decode.float)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "hmac_of_rest" OpenApi.Common.decodeStringByte
               )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "minted_unixtime" Json.Decode.float)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "owner" Json.Decode.string)


decodeGenericUserInfo : Json.Decode.Decoder Api.Types.GenericUserInfo
decodeGenericUserInfo =
    Json.Decode.succeed
        (\email_address invitations login_type relationships ->
             { email_address = email_address
             , invitations = invitations
             , login_type = login_type
             , relationships = relationships
             }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "email_address" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field
                    "invitations"
                    (Json.Decode.dict decodeInvitation)
               )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field
                    "login_type"
                    (Json.Decode.oneOf
                         [ Json.Decode.map
                             OpenApi.Common.Present
                             decodeLoginTypePassword
                         , Json.Decode.null (OpenApi.Common.Null)
                         ]
                    )
               )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field
                    "relationships"
                    (Json.Decode.dict decodeRelationship)
               )


decodeHTTPValidationError : Json.Decode.Decoder Api.Types.HTTPValidationError
decodeHTTPValidationError =
    Json.Decode.succeed (\detail -> { detail = detail })
        |> OpenApi.Common.jsonDecodeAndMap
               (OpenApi.Common.decodeOptionalField
                    "detail"
                    (Json.Decode.list decodeValidationError)
               )


decodeHashedPassword : Json.Decode.Decoder Api.Types.HashedPassword
decodeHashedPassword =
    Json.Decode.succeed (\salt scrypt -> { salt = salt, scrypt = scrypt })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "salt" OpenApi.Common.decodeStringByte)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "scrypt" OpenApi.Common.decodeStringByte)


decodeInvitation : Json.Decode.Decoder Api.Types.Invitation
decodeInvitation =
    Json.Decode.succeed {}


decodeLogInUsernameError : Json.Decode.Decoder Api.Types.LogInUsernameError
decodeLogInUsernameError =
    Json.Decode.succeed (\catchall -> { catchall = catchall })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "catchall" Json.Decode.string)


decodeLogInUsernameRequest : Json.Decode.Decoder Api.Types.LogInUsernameRequest
decodeLogInUsernameRequest =
    Json.Decode.succeed
        (\password username -> { password = password, username = username })
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "password" Json.Decode.string)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "username" Json.Decode.string)


decodeLogInUsernameResultError :
    Json.Decode.Decoder Api.Types.LogInUsernameResultError
decodeLogInUsernameResultError =
    Json.Decode.succeed
        (\error log_in_username_result ->
             { error = error, log_in_username_result = log_in_username_result }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "error" decodeLogInUsernameError)
        |> OpenApi.Common.jsonDecodeAndMap
               (OpenApi.Common.decodeOptionalField
                    "log_in_username_result"
                    (Json.Decode.andThen
                         (\andThenUnpack ->
                              if andThenUnpack == "error" then
                                  Json.Decode.succeed andThenUnpack
                              
                              else
                                  Json.Decode.fail
                                      ("Unexpected value: expected \"error\" got " ++
                                           Json.Encode.encode
                                               0
                                               (Json.Encode.string andThenUnpack
                                               )
                                      )
                         )
                         Json.Decode.string
                    )
               )


decodeLogInUsernameResultOk :
    Json.Decode.Decoder Api.Types.LogInUsernameResultOk
decodeLogInUsernameResultOk =
    Json.Decode.succeed
        (\log_in_username_result ok ->
             { log_in_username_result = log_in_username_result, ok = ok }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (OpenApi.Common.decodeOptionalField
                    "log_in_username_result"
                    (Json.Decode.andThen
                         (\andThenUnpack ->
                              if andThenUnpack == "ok" then
                                  Json.Decode.succeed andThenUnpack
                              
                              else
                                  Json.Decode.fail
                                      ("Unexpected value: expected \"ok\" got " ++
                                           Json.Encode.encode
                                               0
                                               (Json.Encode.string andThenUnpack
                                               )
                                      )
                         )
                         Json.Decode.string
                    )
               )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "ok" decodeAuthSuccess)


decodeLoginTypePassword : Json.Decode.Decoder Api.Types.LoginTypePassword
decodeLoginTypePassword =
    Json.Decode.succeed
        (\login_password login_type_kind ->
             { login_password = login_password
             , login_type_kind = login_type_kind
             }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "login_password" decodeHashedPassword)
        |> OpenApi.Common.jsonDecodeAndMap
               (OpenApi.Common.decodeOptionalField
                    "login_type_kind"
                    (Json.Decode.andThen
                         (\andThenUnpack ->
                              if andThenUnpack == "login_password" then
                                  Json.Decode.succeed andThenUnpack
                              
                              else
                                  Json.Decode.fail
                                      ("Unexpected value: expected \"login_password\" got " ++
                                           Json.Encode.encode
                                               0
                                               (Json.Encode.string andThenUnpack
                                               )
                                      )
                         )
                         Json.Decode.string
                    )
               )


decodeRelationship : Json.Decode.Decoder Api.Types.Relationship
decodeRelationship =
    Json.Decode.succeed
        (\trusted_by_you trusts_you ->
             { trusted_by_you = trusted_by_you, trusts_you = trusts_you }
        )
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "trusted_by_you" Json.Decode.bool)
        |> OpenApi.Common.jsonDecodeAndMap
               (Json.Decode.field "trusts_you" Json.Decode.bool)


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