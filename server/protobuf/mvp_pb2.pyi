# @generated by generate_proto_mypy_stubs.py.  Do not edit!
import sys
from google.protobuf.descriptor import (
    Descriptor as google___protobuf___descriptor___Descriptor,
    EnumDescriptor as google___protobuf___descriptor___EnumDescriptor,
)

from google.protobuf.internal.containers import (
    RepeatedScalarFieldContainer as google___protobuf___internal___containers___RepeatedScalarFieldContainer,
)

from google.protobuf.message import (
    Message as google___protobuf___message___Message,
)

from typing import (
    Iterable as typing___Iterable,
    List as typing___List,
    Optional as typing___Optional,
    Text as typing___Text,
    Tuple as typing___Tuple,
    Union as typing___Union,
    cast as typing___cast,
)

from typing_extensions import (
    Literal as typing_extensions___Literal,
)


builtin___bool = bool
builtin___bytes = bytes
builtin___float = float
builtin___int = int
builtin___str = str
if sys.version_info < (3,):
    builtin___buffer = buffer
    builtin___unicode = unicode


class Void(builtin___int):
    DESCRIPTOR: google___protobuf___descriptor___EnumDescriptor = ...
    @classmethod
    def Name(cls, number: builtin___int) -> builtin___str: ...
    @classmethod
    def Value(cls, name: builtin___str) -> 'Void': ...
    @classmethod
    def keys(cls) -> typing___List[builtin___str]: ...
    @classmethod
    def values(cls) -> typing___List['Void']: ...
    @classmethod
    def items(cls) -> typing___List[typing___Tuple[builtin___str, 'Void']]: ...
    VOID = typing___cast('Void', 0)
VOID = typing___cast('Void', 0)
global___Void = Void

class Pronouns(builtin___int):
    DESCRIPTOR: google___protobuf___descriptor___EnumDescriptor = ...
    @classmethod
    def Name(cls, number: builtin___int) -> builtin___str: ...
    @classmethod
    def Value(cls, name: builtin___str) -> 'Pronouns': ...
    @classmethod
    def keys(cls) -> typing___List[builtin___str]: ...
    @classmethod
    def values(cls) -> typing___List['Pronouns']: ...
    @classmethod
    def items(cls) -> typing___List[typing___Tuple[builtin___str, 'Pronouns']]: ...
    THEY_THEM = typing___cast('Pronouns', 0)
    SHE_HER = typing___cast('Pronouns', 1)
    HE_HIM = typing___cast('Pronouns', 2)
THEY_THEM = typing___cast('Pronouns', 0)
SHE_HER = typing___cast('Pronouns', 1)
HE_HIM = typing___cast('Pronouns', 2)
global___Pronouns = Pronouns

class Resolution(builtin___int):
    DESCRIPTOR: google___protobuf___descriptor___EnumDescriptor = ...
    @classmethod
    def Name(cls, number: builtin___int) -> builtin___str: ...
    @classmethod
    def Value(cls, name: builtin___str) -> 'Resolution': ...
    @classmethod
    def keys(cls) -> typing___List[builtin___str]: ...
    @classmethod
    def values(cls) -> typing___List['Resolution']: ...
    @classmethod
    def items(cls) -> typing___List[typing___Tuple[builtin___str, 'Resolution']]: ...
    RESOLUTION_NONE_YET = typing___cast('Resolution', 0)
    RESOLUTION_YES = typing___cast('Resolution', 1)
    RESOLUTION_NO = typing___cast('Resolution', 2)
RESOLUTION_NONE_YET = typing___cast('Resolution', 0)
RESOLUTION_YES = typing___cast('Resolution', 1)
RESOLUTION_NO = typing___cast('Resolution', 2)
global___Resolution = Resolution

class Position(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    win_cents_if_yes = ... # type: builtin___int
    win_cents_if_no = ... # type: builtin___int

    def __init__(self,
        *,
        win_cents_if_yes : typing___Optional[builtin___int] = None,
        win_cents_if_no : typing___Optional[builtin___int] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> Position: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> Position: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"win_cents_if_no",b"win_cents_if_no",u"win_cents_if_yes",b"win_cents_if_yes"]) -> None: ...
global___Position = Position

class Auth(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    magic_token = ... # type: typing___Text

    def __init__(self,
        *,
        magic_token : typing___Optional[typing___Text] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> Auth: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> Auth: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"auth_kind",b"auth_kind",u"magic_token",b"magic_token"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"auth_kind",b"auth_kind",u"magic_token",b"magic_token"]) -> None: ...
    def WhichOneof(self, oneof_group: typing_extensions___Literal[u"auth_kind",b"auth_kind"]) -> typing_extensions___Literal["magic_token"]: ...
global___Auth = Auth

class AuthError(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    invalid_token = ... # type: global___Void

    def __init__(self,
        *,
        invalid_token : typing___Optional[global___Void] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> AuthError: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> AuthError: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"auth_error_kind",b"auth_error_kind",u"invalid_token",b"invalid_token"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"auth_error_kind",b"auth_error_kind",u"invalid_token",b"invalid_token"]) -> None: ...
    def WhichOneof(self, oneof_group: typing_extensions___Literal[u"auth_error_kind",b"auth_error_kind"]) -> typing_extensions___Literal["invalid_token"]: ...
global___AuthError = AuthError

class SignUpRequest(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    email = ... # type: typing___Text
    password = ... # type: typing___Text
    display_name = ... # type: typing___Text
    pronouns = ... # type: global___Pronouns

    def __init__(self,
        *,
        email : typing___Optional[typing___Text] = None,
        password : typing___Optional[typing___Text] = None,
        display_name : typing___Optional[typing___Text] = None,
        pronouns : typing___Optional[global___Pronouns] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> SignUpRequest: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> SignUpRequest: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"display_name",b"display_name",u"email",b"email",u"password",b"password",u"pronouns",b"pronouns"]) -> None: ...
global___SignUpRequest = SignUpRequest

class SignUpResponse(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    class Error(google___protobuf___message___Message):
        DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
        catchall = ... # type: typing___Text
        email_already_registered = ... # type: global___Void

        def __init__(self,
            *,
            catchall : typing___Optional[typing___Text] = None,
            email_already_registered : typing___Optional[global___Void] = None,
            ) -> None: ...
        if sys.version_info >= (3,):
            @classmethod
            def FromString(cls, s: builtin___bytes) -> SignUpResponse.Error: ...
        else:
            @classmethod
            def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> SignUpResponse.Error: ...
        def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def ClearField(self, field_name: typing_extensions___Literal[u"catchall",b"catchall",u"email_already_registered",b"email_already_registered"]) -> None: ...
    global___Error = Error

    ok = ... # type: global___Void

    @property
    def error(self) -> global___SignUpResponse.Error: ...

    def __init__(self,
        *,
        ok : typing___Optional[global___Void] = None,
        error : typing___Optional[global___SignUpResponse.Error] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> SignUpResponse: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> SignUpResponse: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"error",b"error",u"ok",b"ok",u"signup_result",b"signup_result"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"error",b"error",u"ok",b"ok",u"signup_result",b"signup_result"]) -> None: ...
    def WhichOneof(self, oneof_group: typing_extensions___Literal[u"signup_result",b"signup_result"]) -> typing_extensions___Literal["ok","error"]: ...
global___SignUpResponse = SignUpResponse

class CertaintyRange(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    low = ... # type: builtin___float
    high = ... # type: builtin___float

    def __init__(self,
        *,
        low : typing___Optional[builtin___float] = None,
        high : typing___Optional[builtin___float] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> CertaintyRange: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> CertaintyRange: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"high",b"high",u"low",b"low"]) -> None: ...
global___CertaintyRange = CertaintyRange

class MarketPrivacy(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    class Emails(google___protobuf___message___Message):
        DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
        emails = ... # type: google___protobuf___internal___containers___RepeatedScalarFieldContainer[typing___Text]

        def __init__(self,
            *,
            emails : typing___Optional[typing___Iterable[typing___Text]] = None,
            ) -> None: ...
        if sys.version_info >= (3,):
            @classmethod
            def FromString(cls, s: builtin___bytes) -> MarketPrivacy.Emails: ...
        else:
            @classmethod
            def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> MarketPrivacy.Emails: ...
        def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def ClearField(self, field_name: typing_extensions___Literal[u"emails",b"emails"]) -> None: ...
    global___Emails = Emails

    all_trusted_by_author = ... # type: global___Void

    @property
    def specific_users(self) -> global___MarketPrivacy.Emails: ...

    def __init__(self,
        *,
        all_trusted_by_author : typing___Optional[global___Void] = None,
        specific_users : typing___Optional[global___MarketPrivacy.Emails] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> MarketPrivacy: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> MarketPrivacy: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"all_trusted_by_author",b"all_trusted_by_author",u"privacy_kind",b"privacy_kind",u"specific_users",b"specific_users"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"all_trusted_by_author",b"all_trusted_by_author",u"privacy_kind",b"privacy_kind",u"specific_users",b"specific_users"]) -> None: ...
    def WhichOneof(self, oneof_group: typing_extensions___Literal[u"privacy_kind",b"privacy_kind"]) -> typing_extensions___Literal["all_trusted_by_author","specific_users"]: ...
global___MarketPrivacy = MarketPrivacy

class CreateMarketRequest(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    question = ... # type: typing___Text
    maximum_stake_cents = ... # type: builtin___int
    open_seconds = ... # type: builtin___int
    special_rules = ... # type: typing___Text

    @property
    def auth(self) -> global___Auth: ...

    @property
    def privacy(self) -> global___MarketPrivacy: ...

    @property
    def certainty(self) -> global___CertaintyRange: ...

    def __init__(self,
        *,
        auth : typing___Optional[global___Auth] = None,
        question : typing___Optional[typing___Text] = None,
        privacy : typing___Optional[global___MarketPrivacy] = None,
        certainty : typing___Optional[global___CertaintyRange] = None,
        maximum_stake_cents : typing___Optional[builtin___int] = None,
        open_seconds : typing___Optional[builtin___int] = None,
        special_rules : typing___Optional[typing___Text] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> CreateMarketRequest: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> CreateMarketRequest: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"auth",b"auth",u"certainty",b"certainty",u"privacy",b"privacy"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"auth",b"auth",u"certainty",b"certainty",u"maximum_stake_cents",b"maximum_stake_cents",u"open_seconds",b"open_seconds",u"privacy",b"privacy",u"question",b"question",u"special_rules",b"special_rules"]) -> None: ...
global___CreateMarketRequest = CreateMarketRequest

class CreateMarketResponse(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    class Error(google___protobuf___message___Message):
        DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
        catchall = ... # type: typing___Text

        @property
        def auth_error(self) -> global___AuthError: ...

        def __init__(self,
            *,
            catchall : typing___Optional[typing___Text] = None,
            auth_error : typing___Optional[global___AuthError] = None,
            ) -> None: ...
        if sys.version_info >= (3,):
            @classmethod
            def FromString(cls, s: builtin___bytes) -> CreateMarketResponse.Error: ...
        else:
            @classmethod
            def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> CreateMarketResponse.Error: ...
        def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def HasField(self, field_name: typing_extensions___Literal[u"auth_error",b"auth_error"]) -> builtin___bool: ...
        def ClearField(self, field_name: typing_extensions___Literal[u"auth_error",b"auth_error",u"catchall",b"catchall"]) -> None: ...
    global___Error = Error

    new_market_id = ... # type: builtin___int

    @property
    def error(self) -> global___CreateMarketResponse.Error: ...

    def __init__(self,
        *,
        new_market_id : typing___Optional[builtin___int] = None,
        error : typing___Optional[global___CreateMarketResponse.Error] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> CreateMarketResponse: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> CreateMarketResponse: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"create_market_result",b"create_market_result",u"error",b"error",u"new_market_id",b"new_market_id"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"create_market_result",b"create_market_result",u"error",b"error",u"new_market_id",b"new_market_id"]) -> None: ...
    def WhichOneof(self, oneof_group: typing_extensions___Literal[u"create_market_result",b"create_market_result"]) -> typing_extensions___Literal["new_market_id","error"]: ...
global___CreateMarketResponse = CreateMarketResponse

class GetMarketRequest(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    market_id = ... # type: builtin___int

    @property
    def auth(self) -> global___Auth: ...

    def __init__(self,
        *,
        auth : typing___Optional[global___Auth] = None,
        market_id : typing___Optional[builtin___int] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> GetMarketRequest: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> GetMarketRequest: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"auth",b"auth"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"auth",b"auth",u"market_id",b"market_id"]) -> None: ...
global___GetMarketRequest = GetMarketRequest

class GetMarketResponse(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    class Market(google___protobuf___message___Message):
        DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
        question = ... # type: typing___Text
        maximum_stake_cents = ... # type: builtin___int
        remaining_yes_stake_cents = ... # type: builtin___int
        remaining_no_stake_cents = ... # type: builtin___int
        created_unixtime = ... # type: builtin___int
        closes_unixtime = ... # type: builtin___int
        special_rules = ... # type: typing___Text
        resolution = ... # type: global___Resolution

        @property
        def certainty(self) -> global___CertaintyRange: ...

        @property
        def creator(self) -> global___UserInfo: ...

        def __init__(self,
            *,
            question : typing___Optional[typing___Text] = None,
            certainty : typing___Optional[global___CertaintyRange] = None,
            maximum_stake_cents : typing___Optional[builtin___int] = None,
            remaining_yes_stake_cents : typing___Optional[builtin___int] = None,
            remaining_no_stake_cents : typing___Optional[builtin___int] = None,
            created_unixtime : typing___Optional[builtin___int] = None,
            closes_unixtime : typing___Optional[builtin___int] = None,
            special_rules : typing___Optional[typing___Text] = None,
            creator : typing___Optional[global___UserInfo] = None,
            resolution : typing___Optional[global___Resolution] = None,
            ) -> None: ...
        if sys.version_info >= (3,):
            @classmethod
            def FromString(cls, s: builtin___bytes) -> GetMarketResponse.Market: ...
        else:
            @classmethod
            def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> GetMarketResponse.Market: ...
        def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def HasField(self, field_name: typing_extensions___Literal[u"certainty",b"certainty",u"creator",b"creator"]) -> builtin___bool: ...
        def ClearField(self, field_name: typing_extensions___Literal[u"certainty",b"certainty",u"closes_unixtime",b"closes_unixtime",u"created_unixtime",b"created_unixtime",u"creator",b"creator",u"maximum_stake_cents",b"maximum_stake_cents",u"question",b"question",u"remaining_no_stake_cents",b"remaining_no_stake_cents",u"remaining_yes_stake_cents",b"remaining_yes_stake_cents",u"resolution",b"resolution",u"special_rules",b"special_rules"]) -> None: ...
    global___Market = Market

    class Error(google___protobuf___message___Message):
        DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
        catchall = ... # type: typing___Text

        @property
        def auth_error(self) -> global___AuthError: ...

        def __init__(self,
            *,
            catchall : typing___Optional[typing___Text] = None,
            auth_error : typing___Optional[global___AuthError] = None,
            ) -> None: ...
        if sys.version_info >= (3,):
            @classmethod
            def FromString(cls, s: builtin___bytes) -> GetMarketResponse.Error: ...
        else:
            @classmethod
            def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> GetMarketResponse.Error: ...
        def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def HasField(self, field_name: typing_extensions___Literal[u"auth_error",b"auth_error"]) -> builtin___bool: ...
        def ClearField(self, field_name: typing_extensions___Literal[u"auth_error",b"auth_error",u"catchall",b"catchall"]) -> None: ...
    global___Error = Error


    @property
    def market(self) -> global___GetMarketResponse.Market: ...

    @property
    def error(self) -> global___GetMarketResponse.Error: ...

    def __init__(self,
        *,
        market : typing___Optional[global___GetMarketResponse.Market] = None,
        error : typing___Optional[global___GetMarketResponse.Error] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> GetMarketResponse: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> GetMarketResponse: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"error",b"error",u"get_market_result",b"get_market_result",u"market",b"market"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"error",b"error",u"get_market_result",b"get_market_result",u"market",b"market"]) -> None: ...
    def WhichOneof(self, oneof_group: typing_extensions___Literal[u"get_market_result",b"get_market_result"]) -> typing_extensions___Literal["market","error"]: ...
global___GetMarketResponse = GetMarketResponse

class UserInfo(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    display_name = ... # type: typing___Text
    pronouns = ... # type: global___Pronouns

    def __init__(self,
        *,
        display_name : typing___Optional[typing___Text] = None,
        pronouns : typing___Optional[global___Pronouns] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> UserInfo: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> UserInfo: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"display_name",b"display_name",u"pronouns",b"pronouns"]) -> None: ...
global___UserInfo = UserInfo

class StakeRequest(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    market_id = ... # type: builtin___int
    expected_resolution = ... # type: builtin___bool
    stake = ... # type: builtin___int

    @property
    def auth(self) -> global___Auth: ...

    def __init__(self,
        *,
        auth : typing___Optional[global___Auth] = None,
        market_id : typing___Optional[builtin___int] = None,
        expected_resolution : typing___Optional[builtin___bool] = None,
        stake : typing___Optional[builtin___int] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> StakeRequest: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> StakeRequest: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"auth",b"auth"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"auth",b"auth",u"expected_resolution",b"expected_resolution",u"market_id",b"market_id",u"stake",b"stake"]) -> None: ...
global___StakeRequest = StakeRequest

class StakeResponse(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    class Error(google___protobuf___message___Message):
        DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
        catchall = ... # type: typing___Text

        @property
        def auth_error(self) -> global___AuthError: ...

        def __init__(self,
            *,
            catchall : typing___Optional[typing___Text] = None,
            auth_error : typing___Optional[global___AuthError] = None,
            ) -> None: ...
        if sys.version_info >= (3,):
            @classmethod
            def FromString(cls, s: builtin___bytes) -> StakeResponse.Error: ...
        else:
            @classmethod
            def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> StakeResponse.Error: ...
        def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def HasField(self, field_name: typing_extensions___Literal[u"auth_error",b"auth_error"]) -> builtin___bool: ...
        def ClearField(self, field_name: typing_extensions___Literal[u"auth_error",b"auth_error",u"catchall",b"catchall"]) -> None: ...
    global___Error = Error

    ok = ... # type: global___Void

    @property
    def error(self) -> global___StakeResponse.Error: ...

    def __init__(self,
        *,
        ok : typing___Optional[global___Void] = None,
        error : typing___Optional[global___StakeResponse.Error] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> StakeResponse: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> StakeResponse: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"error",b"error",u"ok",b"ok",u"stake_result",b"stake_result"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"error",b"error",u"ok",b"ok",u"stake_result",b"stake_result"]) -> None: ...
    def WhichOneof(self, oneof_group: typing_extensions___Literal[u"stake_result",b"stake_result"]) -> typing_extensions___Literal["ok","error"]: ...
global___StakeResponse = StakeResponse

class GetUserRequest(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    email = ... # type: typing___Text

    @property
    def auth(self) -> global___Auth: ...

    def __init__(self,
        *,
        auth : typing___Optional[global___Auth] = None,
        email : typing___Optional[typing___Text] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> GetUserRequest: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> GetUserRequest: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"auth",b"auth"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"auth",b"auth",u"email",b"email"]) -> None: ...
global___GetUserRequest = GetUserRequest

class GetUserResponse(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    class User(google___protobuf___message___Message):
        DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
        trusted_by_requester = ... # type: builtin___bool
        trusts_requester = ... # type: builtin___bool

        def __init__(self,
            *,
            trusted_by_requester : typing___Optional[builtin___bool] = None,
            trusts_requester : typing___Optional[builtin___bool] = None,
            ) -> None: ...
        if sys.version_info >= (3,):
            @classmethod
            def FromString(cls, s: builtin___bytes) -> GetUserResponse.User: ...
        else:
            @classmethod
            def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> GetUserResponse.User: ...
        def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def ClearField(self, field_name: typing_extensions___Literal[u"trusted_by_requester",b"trusted_by_requester",u"trusts_requester",b"trusts_requester"]) -> None: ...
    global___User = User

    class Error(google___protobuf___message___Message):
        DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
        catchall = ... # type: typing___Text

        @property
        def auth_error(self) -> global___AuthError: ...

        def __init__(self,
            *,
            catchall : typing___Optional[typing___Text] = None,
            auth_error : typing___Optional[global___AuthError] = None,
            ) -> None: ...
        if sys.version_info >= (3,):
            @classmethod
            def FromString(cls, s: builtin___bytes) -> GetUserResponse.Error: ...
        else:
            @classmethod
            def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> GetUserResponse.Error: ...
        def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def HasField(self, field_name: typing_extensions___Literal[u"auth_error",b"auth_error"]) -> builtin___bool: ...
        def ClearField(self, field_name: typing_extensions___Literal[u"auth_error",b"auth_error",u"catchall",b"catchall"]) -> None: ...
    global___Error = Error


    @property
    def user(self) -> global___GetUserResponse.User: ...

    @property
    def error(self) -> global___GetUserResponse.Error: ...

    def __init__(self,
        *,
        user : typing___Optional[global___GetUserResponse.User] = None,
        error : typing___Optional[global___GetUserResponse.Error] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> GetUserResponse: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> GetUserResponse: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"error",b"error",u"get_user_result",b"get_user_result",u"user",b"user"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"error",b"error",u"get_user_result",b"get_user_result",u"user",b"user"]) -> None: ...
    def WhichOneof(self, oneof_group: typing_extensions___Literal[u"get_user_result",b"get_user_result"]) -> typing_extensions___Literal["user","error"]: ...
global___GetUserResponse = GetUserResponse

class MarkTrustedRequest(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    email_to_trust = ... # type: typing___Text

    @property
    def auth(self) -> global___Auth: ...

    def __init__(self,
        *,
        auth : typing___Optional[global___Auth] = None,
        email_to_trust : typing___Optional[typing___Text] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> MarkTrustedRequest: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> MarkTrustedRequest: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"auth",b"auth"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"auth",b"auth",u"email_to_trust",b"email_to_trust"]) -> None: ...
global___MarkTrustedRequest = MarkTrustedRequest

class MarkTrustedResponse(google___protobuf___message___Message):
    DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
    class Error(google___protobuf___message___Message):
        DESCRIPTOR: google___protobuf___descriptor___Descriptor = ...
        catchall = ... # type: typing___Text

        @property
        def auth_error(self) -> global___AuthError: ...

        def __init__(self,
            *,
            catchall : typing___Optional[typing___Text] = None,
            auth_error : typing___Optional[global___AuthError] = None,
            ) -> None: ...
        if sys.version_info >= (3,):
            @classmethod
            def FromString(cls, s: builtin___bytes) -> MarkTrustedResponse.Error: ...
        else:
            @classmethod
            def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> MarkTrustedResponse.Error: ...
        def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
        def HasField(self, field_name: typing_extensions___Literal[u"auth_error",b"auth_error"]) -> builtin___bool: ...
        def ClearField(self, field_name: typing_extensions___Literal[u"auth_error",b"auth_error",u"catchall",b"catchall"]) -> None: ...
    global___Error = Error

    ok = ... # type: global___Void

    @property
    def error(self) -> global___MarkTrustedResponse.Error: ...

    def __init__(self,
        *,
        ok : typing___Optional[global___Void] = None,
        error : typing___Optional[global___MarkTrustedResponse.Error] = None,
        ) -> None: ...
    if sys.version_info >= (3,):
        @classmethod
        def FromString(cls, s: builtin___bytes) -> MarkTrustedResponse: ...
    else:
        @classmethod
        def FromString(cls, s: typing___Union[builtin___bytes, builtin___buffer, builtin___unicode]) -> MarkTrustedResponse: ...
    def MergeFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def CopyFrom(self, other_msg: google___protobuf___message___Message) -> None: ...
    def HasField(self, field_name: typing_extensions___Literal[u"error",b"error",u"ok",b"ok",u"result",b"result"]) -> builtin___bool: ...
    def ClearField(self, field_name: typing_extensions___Literal[u"error",b"error",u"ok",b"ok",u"result",b"result"]) -> None: ...
    def WhichOneof(self, oneof_group: typing_extensions___Literal[u"result",b"result"]) -> typing_extensions___Literal["ok","error"]: ...
global___MarkTrustedResponse = MarkTrustedResponse
