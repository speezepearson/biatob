module RoundTripTest exposing (suite)

{-| Feeds the generated Elm decoders the *actual* JSON emitted by the FastAPI
app in ../app.py (captured verbatim in ../sample_ok.json and ../sample_err.json).

The point of the spike: can Elm consume a Pydantic-shaped `oneOf` response and
`case` on it like it does today with protobuf's `oneof`?
-}

import Api.Json
import Api.Types exposing (LogInUsernameResultError_Or_LogInUsernameResultOk(..))
import Bytes
import Dict
import Expect
import Json.Decode as JD
import Test exposing (Test, describe, test)


{-| Verbatim from `curl`ing the FastAPI app -- see ../sample_ok.json -}
sampleOk : String
sampleOk =
    """
    {
      "log_in_username_result": "ok",
      "ok": {
        "token": {
          "hmac_of_rest": "AAH+/4A=",
          "owner": "spike",
          "minted_unixtime": 1600000000.0,
          "expires_unixtime": 1600086400.0
        },
        "user_info": {
          "email_address": "spike@example.com",
          "invitations": { "some-nonce": {} },
          "relationships": {
            "alice": { "trusts_you": true, "trusted_by_you": false }
          },
          "login_type": {
            "login_type_kind": "login_password",
            "login_password": { "salt": "3q2+7w==", "scrypt": "AQID" }
          }
        }
      }
    }
    """


{-| Verbatim -- see ../sample_err.json -}
sampleErr : String
sampleErr =
    """
    { "log_in_username_result": "error", "error": { "catchall": "bad password" } }
    """


{-| The union decoder as assembled by the generator in Api/Api.elm. -}
responseDecoder : JD.Decoder LogInUsernameResultError_Or_LogInUsernameResultOk
responseDecoder =
    JD.oneOf
        [ JD.map LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultError
            Api.Json.decodeLogInUsernameResultError
        , JD.map LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultOk
            Api.Json.decodeLogInUsernameResultOk
        ]


suite : Test
suite =
    describe "generated decoders vs. real FastAPI output"
        [ test "Ok arm dispatches to the Ok constructor" <|
            \_ ->
                case JD.decodeString responseDecoder sampleOk of
                    Ok (LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultOk r) ->
                        Expect.equal "spike" r.ok.token.owner

                    other ->
                        Expect.fail ("expected Ok arm, got: " ++ Debug.toString other)
        , test "Error arm dispatches to the Error constructor" <|
            \_ ->
                case JD.decodeString responseDecoder sampleErr of
                    Ok (LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultError r) ->
                        Expect.equal "bad password" r.error.catchall

                    other ->
                        Expect.fail ("expected Error arm, got: " ++ Debug.toString other)
        , test "base64 bytes decode to real Bytes of the right width" <|
            \_ ->
                case JD.decodeString responseDecoder sampleOk of
                    Ok (LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultOk r) ->
                        -- b"\x00\x01\xfe\xff\x80" is 5 bytes
                        Expect.equal 5 (Bytes.width r.ok.token.hmac_of_rest)

                    other ->
                        Expect.fail ("expected Ok arm, got: " ++ Debug.toString other)
        , test "map<string, Relationship> survives" <|
            \_ ->
                case JD.decodeString responseDecoder sampleOk of
                    Ok (LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultOk r) ->
                        r.ok.user_info.relationships
                            |> Dict.get "alice"
                            |> Maybe.map .trusts_you
                            |> Expect.equal (Just True)

                    other ->
                        Expect.fail ("expected Ok arm, got: " ++ Debug.toString other)
        ]
