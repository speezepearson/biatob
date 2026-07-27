module Api.Api exposing ( logInUsername, logInUsernameTask )

{-|
## Operations

@docs logInUsername, logInUsernameTask
-}


import Api.Json
import Api.Types
import Dict
import Http
import Json.Decode
import Json.Encode
import OpenApi.Common
import Task
import Url.Builder


{-| Log In Username -}
logInUsername :
    { toMsg :
        Result (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.LogInUsernameResultError_Or_LogInUsernameResultOk
        -> msg
    , body : Api.Types.LogInUsernameRequest
    }
    -> Cmd msg
logInUsername config =
    Http.request
        { url = Url.Builder.absolute [ "api", "LogInUsername" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                (Json.Decode.oneOf
                     [ Json.Decode.map
                         Api.Types.LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultError
                         Api.Json.decodeLogInUsernameResultError
                     , Json.Decode.map
                         Api.Types.LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultOk
                         Api.Json.decodeLogInUsernameResultOk
                     ]
                )
                config.toMsg
        , body = Http.jsonBody (Api.Json.encodeLogInUsernameRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Log In Username -}
logInUsernameTask :
    { body : Api.Types.LogInUsernameRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.LogInUsernameResultError_Or_LogInUsernameResultOk
logInUsernameTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "LogInUsername" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                (Json.Decode.oneOf
                     [ Json.Decode.map
                         Api.Types.LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultError
                         Api.Json.decodeLogInUsernameResultError
                     , Json.Decode.map
                         Api.Types.LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultOk
                         Api.Json.decodeLogInUsernameResultOk
                     ]
                )
        , body = Http.jsonBody (Api.Json.encodeLogInUsernameRequest config.body)
        , timeout = Nothing
        }