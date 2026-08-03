module Api.Api exposing
    ( formstate, formstateTask, acceptInvitation, acceptInvitationTask, changePassword, changePasswordTask
    , checkInvitation, checkInvitationTask, createPrediction, createPredictionTask, follow, followTask, getPrediction
    , getPredictionTask, getSettings, getSettingsTask, getUser, getUserTask, listMyStakes, listMyStakesTask
    , listPredictions, listPredictionsTask, logInUsername, logInUsernameTask, registerUsername, registerUsernameTask, resolve
    , resolveTask, sendInvitation, sendInvitationTask, sendVerificationEmail, sendVerificationEmailTask, setTrusted, setTrustedTask
    , signOut, signOutTask, stake, stakeTask, whoami, whoamiTask
    )

{-|
## Operations

@docs formstate, formstateTask, acceptInvitation, acceptInvitationTask, changePassword, changePasswordTask
@docs checkInvitation, checkInvitationTask, createPrediction, createPredictionTask, follow, followTask
@docs getPrediction, getPredictionTask, getSettings, getSettingsTask, getUser, getUserTask
@docs listMyStakes, listMyStakesTask, listPredictions, listPredictionsTask, logInUsername, logInUsernameTask
@docs registerUsername, registerUsernameTask, resolve, resolveTask, sendInvitation, sendInvitationTask
@docs sendVerificationEmail, sendVerificationEmailTask, setTrusted, setTrustedTask, signOut, signOutTask
@docs stake, stakeTask, whoami, whoamiTask
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


{-| <Lambda> -}
formstate config =
    Http.request
        { url = Url.Builder.absolute [ "_formstate" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [])
                Api.Json.decodeSavedCreatedPredictionFormState
                config.toMsg
        , body = Http.emptyBody
        , timeout = Nothing
        , tracker = Nothing
        }


{-| <Lambda> -}
formstateTask :
    {}
    -> Task.Task (OpenApi.Common.Error err String) Api.Types.SavedCreatedPredictionFormState
formstateTask config =
    Http.task
        { url = Url.Builder.absolute [ "_formstate" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [])
                Api.Json.decodeSavedCreatedPredictionFormState
        , body = Http.emptyBody
        , timeout = Nothing
        }


{-| H -}
acceptInvitation config =
    Http.request
        { url = Url.Builder.absolute [ "api", "AcceptInvitation" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeGenericUserInfo
                config.toMsg
        , body =
            Http.jsonBody (Api.Json.encodeAcceptInvitationRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
acceptInvitationTask :
    { body : Api.Types.AcceptInvitationRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.GenericUserInfo
acceptInvitationTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "AcceptInvitation" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeGenericUserInfo
        , body =
            Http.jsonBody (Api.Json.encodeAcceptInvitationRequest config.body)
        , timeout = Nothing
        }


{-| H -}
changePassword config =
    Http.request
        { url = Url.Builder.absolute [ "api", "ChangePassword" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeEmpty
                config.toMsg
        , body =
            Http.jsonBody (Api.Json.encodeChangePasswordRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
changePasswordTask :
    { body : Api.Types.ChangePasswordRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.Empty
changePasswordTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "ChangePassword" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeEmpty
        , body =
            Http.jsonBody (Api.Json.encodeChangePasswordRequest config.body)
        , timeout = Nothing
        }


{-| H -}
checkInvitation config =
    Http.request
        { url = Url.Builder.absolute [ "api", "CheckInvitation" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeCheckInvitationResponse
                config.toMsg
        , body =
            Http.jsonBody (Api.Json.encodeCheckInvitationRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
checkInvitationTask :
    { body : Api.Types.CheckInvitationRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.CheckInvitationResponse
checkInvitationTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "CheckInvitation" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeCheckInvitationResponse
        , body =
            Http.jsonBody (Api.Json.encodeCheckInvitationRequest config.body)
        , timeout = Nothing
        }


{-| H -}
createPrediction config =
    Http.request
        { url = Url.Builder.absolute [ "api", "CreatePrediction" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeCreatePredictionResponse
                config.toMsg
        , body =
            Http.jsonBody (Api.Json.encodeCreatePredictionRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
createPredictionTask :
    { body : Api.Types.CreatePredictionRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.CreatePredictionResponse
createPredictionTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "CreatePrediction" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeCreatePredictionResponse
        , body =
            Http.jsonBody (Api.Json.encodeCreatePredictionRequest config.body)
        , timeout = Nothing
        }


{-| H -}
follow config =
    Http.request
        { url = Url.Builder.absolute [ "api", "Follow" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeUserPredictionView
                config.toMsg
        , body = Http.jsonBody (Api.Json.encodeFollowRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
followTask :
    { body : Api.Types.FollowRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.UserPredictionView
followTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "Follow" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeUserPredictionView
        , body = Http.jsonBody (Api.Json.encodeFollowRequest config.body)
        , timeout = Nothing
        }


{-| H -}
getPrediction config =
    Http.request
        { url = Url.Builder.absolute [ "api", "GetPrediction" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeUserPredictionView
                config.toMsg
        , body = Http.jsonBody (Api.Json.encodeGetPredictionRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
getPredictionTask :
    { body : Api.Types.GetPredictionRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.UserPredictionView
getPredictionTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "GetPrediction" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeUserPredictionView
        , body = Http.jsonBody (Api.Json.encodeGetPredictionRequest config.body)
        , timeout = Nothing
        }


{-| H -}
getSettings config =
    Http.request
        { url = Url.Builder.absolute [ "api", "GetSettings" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeGenericUserInfo
                config.toMsg
        , body = Http.jsonBody (Api.Json.encodeGetSettingsRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
getSettingsTask :
    { body : Api.Types.GetSettingsRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.GenericUserInfo
getSettingsTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "GetSettings" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeGenericUserInfo
        , body = Http.jsonBody (Api.Json.encodeGetSettingsRequest config.body)
        , timeout = Nothing
        }


{-| H -}
getUser config =
    Http.request
        { url = Url.Builder.absolute [ "api", "GetUser" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeRelationship
                config.toMsg
        , body = Http.jsonBody (Api.Json.encodeGetUserRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
getUserTask :
    { body : Api.Types.GetUserRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.Relationship
getUserTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "GetUser" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeRelationship
        , body = Http.jsonBody (Api.Json.encodeGetUserRequest config.body)
        , timeout = Nothing
        }


{-| H -}
listMyStakes config =
    Http.request
        { url = Url.Builder.absolute [ "api", "ListMyStakes" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodePredictionsById
                config.toMsg
        , body = Http.jsonBody (Api.Json.encodeListMyStakesRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
listMyStakesTask :
    { body : Api.Types.ListMyStakesRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.PredictionsById
listMyStakesTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "ListMyStakes" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodePredictionsById
        , body = Http.jsonBody (Api.Json.encodeListMyStakesRequest config.body)
        , timeout = Nothing
        }


{-| H -}
listPredictions config =
    Http.request
        { url = Url.Builder.absolute [ "api", "ListPredictions" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodePredictionsById
                config.toMsg
        , body =
            Http.jsonBody (Api.Json.encodeListPredictionsRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
listPredictionsTask :
    { body : Api.Types.ListPredictionsRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.PredictionsById
listPredictionsTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "ListPredictions" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodePredictionsById
        , body =
            Http.jsonBody (Api.Json.encodeListPredictionsRequest config.body)
        , timeout = Nothing
        }


{-| H -}
logInUsername config =
    Http.request
        { url = Url.Builder.absolute [ "api", "LogInUsername" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeAuthSuccess
                config.toMsg
        , body = Http.jsonBody (Api.Json.encodeLogInUsernameRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
logInUsernameTask :
    { body : Api.Types.LogInUsernameRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.AuthSuccess
logInUsernameTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "LogInUsername" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeAuthSuccess
        , body = Http.jsonBody (Api.Json.encodeLogInUsernameRequest config.body)
        , timeout = Nothing
        }


{-| H -}
registerUsername config =
    Http.request
        { url = Url.Builder.absolute [ "api", "RegisterUsername" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeAuthSuccess
                config.toMsg
        , body =
            Http.jsonBody (Api.Json.encodeRegisterUsernameRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
registerUsernameTask :
    { body : Api.Types.RegisterUsernameRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.AuthSuccess
registerUsernameTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "RegisterUsername" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeAuthSuccess
        , body =
            Http.jsonBody (Api.Json.encodeRegisterUsernameRequest config.body)
        , timeout = Nothing
        }


{-| H -}
resolve config =
    Http.request
        { url = Url.Builder.absolute [ "api", "Resolve" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeUserPredictionView
                config.toMsg
        , body = Http.jsonBody (Api.Json.encodeResolveRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
resolveTask :
    { body : Api.Types.ResolveRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.UserPredictionView
resolveTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "Resolve" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeUserPredictionView
        , body = Http.jsonBody (Api.Json.encodeResolveRequest config.body)
        , timeout = Nothing
        }


{-| H -}
sendInvitation config =
    Http.request
        { url = Url.Builder.absolute [ "api", "SendInvitation" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeGenericUserInfo
                config.toMsg
        , body =
            Http.jsonBody (Api.Json.encodeSendInvitationRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
sendInvitationTask :
    { body : Api.Types.SendInvitationRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.GenericUserInfo
sendInvitationTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "SendInvitation" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeGenericUserInfo
        , body =
            Http.jsonBody (Api.Json.encodeSendInvitationRequest config.body)
        , timeout = Nothing
        }


{-| H -}
sendVerificationEmail config =
    Http.request
        { url = Url.Builder.absolute [ "api", "SendVerificationEmail" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeEmpty
                config.toMsg
        , body =
            Http.jsonBody
                (Api.Json.encodeSendVerificationEmailRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
sendVerificationEmailTask :
    { body : Api.Types.SendVerificationEmailRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.Empty
sendVerificationEmailTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "SendVerificationEmail" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeEmpty
        , body =
            Http.jsonBody
                (Api.Json.encodeSendVerificationEmailRequest config.body)
        , timeout = Nothing
        }


{-| H -}
setTrusted config =
    Http.request
        { url = Url.Builder.absolute [ "api", "SetTrusted" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeGenericUserInfo
                config.toMsg
        , body = Http.jsonBody (Api.Json.encodeSetTrustedRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
setTrustedTask :
    { body : Api.Types.SetTrustedRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.GenericUserInfo
setTrustedTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "SetTrusted" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeGenericUserInfo
        , body = Http.jsonBody (Api.Json.encodeSetTrustedRequest config.body)
        , timeout = Nothing
        }


{-| H -}
signOut config =
    Http.request
        { url = Url.Builder.absolute [ "api", "SignOut" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeEmpty
                config.toMsg
        , body = Http.jsonBody (Api.Json.encodeSignOutRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
signOutTask :
    { body : Api.Types.SignOutRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.Empty
signOutTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "SignOut" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeEmpty
        , body = Http.jsonBody (Api.Json.encodeSignOutRequest config.body)
        , timeout = Nothing
        }


{-| H -}
stake config =
    Http.request
        { url = Url.Builder.absolute [ "api", "Stake" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeUserPredictionView
                config.toMsg
        , body = Http.jsonBody (Api.Json.encodeStakeRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
stakeTask :
    { body : Api.Types.StakeRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.UserPredictionView
stakeTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "Stake" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeUserPredictionView
        , body = Http.jsonBody (Api.Json.encodeStakeRequest config.body)
        , timeout = Nothing
        }


{-| H -}
whoami config =
    Http.request
        { url = Url.Builder.absolute [ "api", "Whoami" ] []
        , method = "POST"
        , headers = []
        , expect =
            OpenApi.Common.expectJsonCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeWhoamiResponse
                config.toMsg
        , body = Http.jsonBody (Api.Json.encodeWhoamiRequest config.body)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| H -}
whoamiTask :
    { body : Api.Types.WhoamiRequest }
    -> Task.Task (OpenApi.Common.Error Api.Types.HTTPValidationError String) Api.Types.WhoamiResponse
whoamiTask config =
    Http.task
        { url = Url.Builder.absolute [ "api", "Whoami" ] []
        , method = "POST"
        , headers = []
        , resolver =
            OpenApi.Common.jsonResolverCustom
                (Dict.fromList [ ( "422", Api.Json.decodeHTTPValidationError ) ]
                )
                Api.Json.decodeWhoamiResponse
        , body = Http.jsonBody (Api.Json.encodeWhoamiRequest config.body)
        , timeout = Nothing
        }