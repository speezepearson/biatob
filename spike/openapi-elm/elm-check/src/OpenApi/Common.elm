module OpenApi.Common exposing
    ( encodeStringByte, toParamStringStringByte
    , decodeStringByte
    , Nullable(..), Error(..), jsonDecodeAndMap, decodeOptionalField
    , bytesResolverCustom, expectBytesCustom, stringResolverCustom, expectStringCustom, jsonResolverCustom, expectJsonCustom, base64ResolverCustom
    , expectBase64Custom
    )

{-|
## Encoders

@docs encodeStringByte, toParamStringStringByte

## Decoders

@docs decodeStringByte

## Common

@docs Nullable, Error, jsonDecodeAndMap, decodeOptionalField

## elm/http

@docs bytesResolverCustom, expectBytesCustom, stringResolverCustom, expectStringCustom, jsonResolverCustom, expectJsonCustom
@docs base64ResolverCustom, expectBase64Custom
-}


import Base64
import Bytes
import Bytes.Decode
import Dict
import Http
import Json.Decode
import Json.Encode


encodeStringByte : Bytes.Bytes -> Json.Encode.Value
encodeStringByte value =
    Json.Encode.string (Maybe.withDefault "" (Base64.fromBytes value))


toParamStringStringByte : Bytes.Bytes -> String
toParamStringStringByte value =
    Maybe.withDefault "" (Base64.fromBytes value)


decodeStringByte : Json.Decode.Decoder Bytes.Bytes
decodeStringByte =
    Json.Decode.andThen
        (\andThenUnpack ->
             case Base64.toBytes andThenUnpack of
                 Nothing ->
                     Json.Decode.fail "Invalid base64 data"
             
                 Just bytes ->
                     Json.Decode.succeed bytes
        )
        Json.Decode.string


type Nullable value
    = Null
    | Present value


type Error err body
    = BadUrl String
    | Timeout
    | NetworkError
    | KnownBadStatus Int err
    | UnknownBadStatus Http.Metadata body
    | BadErrorBody Http.Metadata body
    | BadBody Http.Metadata body


{-| Chain JSON decoders, when `Json.Decode.map8` isn't enough. -}
jsonDecodeAndMap :
    Json.Decode.Decoder a
    -> Json.Decode.Decoder (a -> value)
    -> Json.Decode.Decoder value
jsonDecodeAndMap dx df =
    Json.Decode.map2 (|>) dx df


{-| Decode an optional field

    decodeString (decodeOptionalField "x" int) "{ "x": 3 }"
    --> Ok (Just 3)

    decodeString (decodeOptionalField "x" int) "{ "x": true }"
    --> Err ...

    decodeString (decodeOptionalField "x" int) "{ "y": 4 }"
    --> Ok Nothing
-}
decodeOptionalField :
    String -> Json.Decode.Decoder t -> Json.Decode.Decoder (Maybe t)
decodeOptionalField key fieldDecoder =
    Json.Decode.andThen
        (\andThenUnpack ->
             if andThenUnpack then
                 Json.Decode.field
                     key
                     (Json.Decode.oneOf
                          [ Json.Decode.map Just fieldDecoder
                          , Json.Decode.null Nothing
                          ]
                     )
             
             else
                 Json.Decode.succeed Nothing
        )
        (Json.Decode.oneOf
             [ Json.Decode.map
                 (\_ -> True)
                 (Json.Decode.field key Json.Decode.value)
             , Json.Decode.succeed False
             ]
        )


responseToResult :
    Dict.Dict String (Json.Decode.Decoder err)
    -> (body -> String)
    -> (Http.Metadata -> body -> Result (Error err body) value)
    -> Http.Response body
    -> Result (Error err body) value
responseToResult errorDecoders bodyToString onSuccess response =
    case response of
        Http.BadUrl_ arg_0 ->
            Result.Err (BadUrl arg_0)
    
        Http.Timeout_ ->
            Result.Err (Timeout)
    
        Http.NetworkError_ ->
            Result.Err (NetworkError)
    
        Http.BadStatus_ httpMetadata body ->
            case Dict.get (String.fromInt httpMetadata.statusCode) errorDecoders
            of
                Nothing ->
                    Result.Err (UnknownBadStatus httpMetadata body)
            
                Just err ->
                    case Json.Decode.decodeString err (bodyToString body) of
                        Ok res ->
                            Result.Err
                                (KnownBadStatus httpMetadata.statusCode res)
                    
                        Err _ ->
                            Result.Err (BadErrorBody httpMetadata body)
    
        Http.GoodStatus_ httpMetadata body ->
            onSuccess httpMetadata body


bytesResolverCustom :
    Dict.Dict String (Json.Decode.Decoder err)
    -> Http.Resolver (Error err Bytes.Bytes) Bytes.Bytes
bytesResolverCustom errorDecoders =
    Http.bytesResolver
        (responseToResult
             errorDecoders
             (\body ->
                  Maybe.withDefault
                      ""
                      (Bytes.Decode.decode
                           (Bytes.Decode.string (Bytes.width body))
                           body
                      )
             )
             (\metadata body -> Result.Ok body)
        )


expectBytesCustom :
    Dict.Dict String (Json.Decode.Decoder err)
    -> (Result (Error err Bytes.Bytes) Bytes.Bytes -> msg)
    -> Http.Expect msg
expectBytesCustom errorDecoders toMsg =
    Http.expectBytesResponse
        toMsg
        (responseToResult
             errorDecoders
             (\body ->
                  Maybe.withDefault
                      ""
                      (Bytes.Decode.decode
                           (Bytes.Decode.string (Bytes.width body))
                           body
                      )
             )
             (\metadata body -> Result.Ok body)
        )


stringResolverCustom :
    Dict.Dict String (Json.Decode.Decoder err)
    -> Http.Resolver (Error err String) String
stringResolverCustom errorDecoders =
    Http.stringResolver
        (responseToResult
             errorDecoders
             Basics.identity
             (\metadata body -> Result.Ok body)
        )


expectStringCustom :
    Dict.Dict String (Json.Decode.Decoder err)
    -> (Result (Error err String) String -> msg)
    -> Http.Expect msg
expectStringCustom errorDecoders toMsg =
    Http.expectStringResponse
        toMsg
        (responseToResult
             errorDecoders
             Basics.identity
             (\metadata body -> Result.Ok body)
        )


jsonResolverCustom :
    Dict.Dict String (Json.Decode.Decoder err)
    -> Json.Decode.Decoder success
    -> Http.Resolver (Error err String) success
jsonResolverCustom errorDecoders successDecoder =
    Http.stringResolver
        (responseToResult
             errorDecoders
             Basics.identity
             (\metadata body ->
                  case Json.Decode.decodeString successDecoder body of
                      Ok res ->
                          Result.Ok res
                  
                      Err _ ->
                          Result.Err (BadBody metadata body)
             )
        )


expectJsonCustom :
    Dict.Dict String (Json.Decode.Decoder err)
    -> Json.Decode.Decoder success
    -> (Result (Error err String) success -> msg)
    -> Http.Expect msg
expectJsonCustom errorDecoders successDecoder toMsg =
    Http.expectStringResponse
        toMsg
        (responseToResult
             errorDecoders
             Basics.identity
             (\metadata body ->
                  case Json.Decode.decodeString successDecoder body of
                      Ok res ->
                          Result.Ok res
                  
                      Err _ ->
                          Result.Err (BadBody metadata body)
             )
        )


base64ResolverCustom :
    Dict.Dict String (Json.Decode.Decoder err)
    -> Http.Resolver (Error err String) Bytes.Bytes
base64ResolverCustom errorDecoders =
    Http.stringResolver
        (responseToResult
             errorDecoders
             Basics.identity
             (\metadata body ->
                  Result.fromMaybe (BadBody metadata body) (Base64.toBytes body)
             )
        )


expectBase64Custom :
    Dict.Dict String (Json.Decode.Decoder err)
    -> (Result (Error err String) Bytes.Bytes -> msg)
    -> Http.Expect msg
expectBase64Custom errorDecoders toMsg =
    Http.expectStringResponse
        toMsg
        (responseToResult
             errorDecoders
             Basics.identity
             (\metadata body ->
                  Result.fromMaybe (BadBody metadata body) (Base64.toBytes body)
             )
        )