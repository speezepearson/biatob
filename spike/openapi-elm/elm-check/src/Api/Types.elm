module Api.Types exposing
    ( AuthSuccess, AuthToken, GenericUserInfo, HTTPValidationError, HashedPassword, Invitation, LogInUsernameError
    , LogInUsernameRequest, LogInUsernameResultError, LogInUsernameResultOk, LoginTypePassword, Relationship, ValidationError
    , Int_Or_String(..), LogInUsernameResultError_Or_LogInUsernameResultOk(..)
    )

{-|
## Aliases

@docs AuthSuccess, AuthToken, GenericUserInfo, HTTPValidationError, HashedPassword, Invitation
@docs LogInUsernameError, LogInUsernameRequest, LogInUsernameResultError, LogInUsernameResultOk, LoginTypePassword, Relationship
@docs ValidationError

## One of

@docs Int_Or_String, LogInUsernameResultError_Or_LogInUsernameResultOk
-}


import Bytes
import Dict
import Json.Encode
import OpenApi.Common


type alias AuthSuccess =
    { token : AuthToken, user_info : GenericUserInfo }


type alias AuthToken =
    { expires_unixtime : Float
    , hmac_of_rest : Bytes.Bytes
    , minted_unixtime : Float
    , owner : String
    }


type alias GenericUserInfo =
    { email_address : String
    , invitations : Dict.Dict String Invitation
    , login_type : OpenApi.Common.Nullable LoginTypePassword
    , relationships : Dict.Dict String Relationship
    }


type alias HTTPValidationError =
    { detail : Maybe (List ValidationError) }


type alias HashedPassword =
    { salt : Bytes.Bytes, scrypt : Bytes.Bytes }


type alias Invitation =
    {}


type alias LogInUsernameError =
    { catchall : String }


type alias LogInUsernameRequest =
    { password : String, username : String }


type alias LogInUsernameResultError =
    { error : LogInUsernameError, log_in_username_result : Maybe String }


type alias LogInUsernameResultOk =
    { log_in_username_result : Maybe String, ok : AuthSuccess }


type alias LoginTypePassword =
    { login_password : HashedPassword, login_type_kind : Maybe String }


type alias Relationship =
    { trusted_by_you : Bool, trusts_you : Bool }


type alias ValidationError =
    { ctx : Maybe {}
    , input : Maybe Json.Encode.Value
    , loc : List Int_Or_String
    , msg : String
    , type_ : String
    }


type Int_Or_String
    = Int_Or_String__Int Int
    | Int_Or_String__String String


type LogInUsernameResultError_Or_LogInUsernameResultOk
    = LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultError
        LogInUsernameResultError
    | LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultOk
        LogInUsernameResultOk