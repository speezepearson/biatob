#! /usr/bin/env python3
# TODO: flock over the database file

import argparse
import asyncio
import base64
import contextlib
import copy
import datetime
import filelock  # type: ignore
import functools
import hashlib
import hmac
import io
import json
from pathlib import Path
import random
import re
import secrets
import string
import sys
import tempfile
import time
from typing import overload, Any, Mapping, Iterator, Optional, Container, NewType, Callable, NoReturn, Tuple, Iterable, Sequence, TypeVar, MutableSequence
import argparse
import logging
import os
from email.message import EmailMessage

import sqlalchemy
from google.protobuf.message import Message

from .api_server import *
from .core import *
from .emailer import *
from .http import *
from .web_server import *
from .protobuf import mvp_pb2
from . import sql_schema as schema

import structlog
logger = structlog.get_logger()


def user_exists(conn: sqlalchemy.engine.base.Connection, user: Username) -> bool:
 return conn.execute(sqlalchemy.select(schema.users).where(schema.users.c.username == user)).first() is not None

def trusts(conn: sqlalchemy.engine.base.Connection, a: Username, b: Username) -> bool:
  if a == b:
    return True

  row = conn.execute(sqlalchemy.select(schema.relationships.c.trusted).where(sqlalchemy.and_(schema.relationships.c.subject_username == a, schema.relationships.c.object_username == b))).first()
  if row is None:
    return False

  return bool(row['trusted'])

def view_prediction(conn: sqlalchemy.engine.base.Connection, viewer: Optional[Username], prediction_id: PredictionId) -> Optional[mvp_pb2.UserPredictionView]:
  row = conn.execute(sqlalchemy.select(schema.predictions).where(schema.predictions.c.prediction_id == prediction_id)).first()
  if row is None:
    return None

  creator_is_viewer = (viewer == row['creator'])

  resolution_rows = conn.execute(
    sqlalchemy.select(schema.resolutions)
    .where(schema.resolutions.c.prediction_id == prediction_id)
    .order_by(schema.resolutions.c.resolved_at_unixtime)
  ).fetchall()

  trade_rows = conn.execute(
    sqlalchemy.select(schema.trades)
    .where(sqlalchemy.and_(
      schema.trades.c.prediction_id == prediction_id,
      True if creator_is_viewer else (schema.trades.c.bettor == viewer)
    ))
    .order_by(schema.trades.c.transacted_at_unixtime)
  ).fetchall()

  remaining_stake_cents_vs_believers = row['maximum_stake_cents'] - conn.execute(
    sqlalchemy.select(sqlalchemy.sql.func.coalesce(sqlalchemy.sql.func.sum(schema.trades.c.creator_stake_cents), 0))
    .where(sqlalchemy.and_(
      schema.trades.c.prediction_id == prediction_id,
      sqlalchemy.not_(schema.trades.c.bettor_is_a_skeptic)
    ))
  ).scalar()
  remaining_stake_cents_vs_skeptics = row['maximum_stake_cents'] - conn.execute(
    sqlalchemy.select(sqlalchemy.sql.func.coalesce(sqlalchemy.sql.func.sum(schema.trades.c.creator_stake_cents), 0))
    .where(sqlalchemy.and_(
      schema.trades.c.prediction_id == prediction_id,
      schema.trades.c.bettor_is_a_skeptic
    ))
  ).scalar()

  return mvp_pb2.UserPredictionView(
    prediction=row['prediction'],
    certainty=mvp_pb2.CertaintyRange(low=row['certainty_low_p'], high=row['certainty_high_p']),
    maximum_stake_cents=row['maximum_stake_cents'],
    remaining_stake_cents_vs_believers=remaining_stake_cents_vs_believers,
    remaining_stake_cents_vs_skeptics=remaining_stake_cents_vs_skeptics,
    created_unixtime=row['created_at_unixtime'],
    closes_unixtime=row['closes_at_unixtime'],
    resolves_at_unixtime=row['resolves_at_unixtime'],
    special_rules=row['special_rules'],
    creator=mvp_pb2.UserUserView(
      username=row['creator'],
      is_trusted=trusts(conn, viewer, Username(row['creator'])) if (viewer is not None) else False,
      trusts_you=trusts(conn, Username(row['creator']), viewer) if (viewer is not None) else False,
    ),
    resolutions=[
      mvp_pb2.ResolutionEvent(
        unixtime=r['resolved_at_unixtime'],
        resolution=mvp_pb2.Resolution.Value(r['resolution'])
      )
      for r in resolution_rows
    ],
    your_trades=[
      mvp_pb2.Trade(
        bettor=t['bettor'],
        bettor_is_a_skeptic=t['bettor_is_a_skeptic'],
        creator_stake_cents=t['creator_stake_cents'],
        bettor_stake_cents=t['bettor_stake_cents'],
        transacted_unixtime=t['transacted_at_unixtime'],
      )
      for t in trade_rows
    ],
  )


def transactional(f):
  @functools.wraps(f)
  def wrapped(self: 'SqlServicer', *args, **kwargs):
    with self._conn.begin():
      return f(self, *args, **kwargs)
  return wrapped
def checks_token(f):
  @functools.wraps(f)
  def wrapped(self: 'SqlServicer', token: Optional[mvp_pb2.AuthToken], *args, **kwargs):
    token = self._token_mint.check_token(token)
    if (token is not None) and not user_exists(self._conn, token_owner(token)):
      raise ForgottenTokenError(token)
    structlog.contextvars.bind_contextvars(actor=token_owner(token))
    try:
      return f(self, token, *args, **kwargs)
    finally:
      structlog.contextvars.unbind_contextvars('actor')
  return wrapped
def log_action(f):
  @functools.wraps(f)
  def wrapped(*args, **kwargs):
    structlog.contextvars.bind_contextvars(servicer_action=f.__name__)
    try:
      return f(*args, **kwargs)
    finally:
      structlog.contextvars.unbind_contextvars('servicer_action')
  return wrapped

class SqlServicer(Servicer):
    def __init__(self, conn: sqlalchemy.engine.base.Connection, token_mint: TokenMint, emailer: Emailer, random_seed: Optional[int] = None, clock: Callable[[], float] = time.time) -> None:
        self._conn = conn
        self._token_mint = token_mint
        self._emailer = emailer
        self._rng = random.Random(random_seed)
        self._clock = clock

    @transactional
    @checks_token
    @log_action
    def Whoami(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.WhoamiRequest) -> mvp_pb2.WhoamiResponse:
        return mvp_pb2.WhoamiResponse(auth=token)

    @transactional
    @checks_token
    @log_action
    def SignOut(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SignOutRequest) -> mvp_pb2.SignOutResponse:
        if token is not None:
            self._token_mint.revoke_token(token)
        return mvp_pb2.SignOutResponse()

    @transactional
    @checks_token
    @log_action
    def RegisterUsername(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.RegisterUsernameRequest) -> mvp_pb2.RegisterUsernameResponse:
      if token is not None:
        logger.warn('logged-in user trying to register a username', new_username=request.username)
        return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall='already authenticated; first, log out'))
      username_problems = describe_username_problems(request.username)
      if username_problems is not None:
        logger.debug('trying to register bad username', username=request.username)
        return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall=username_problems))
      password_problems = describe_password_problems(request.password)
      if password_problems is not None:
        logger.debug('trying to register with a bad password', username=request.username)
        return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall=password_problems))

      if self._conn.execute(sqlalchemy.select(schema.users.c.username).where(schema.users.c.username == request.username)).first() is not None:
        logger.info('username taken', username=request.username)
        return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall='username taken'))

      logger.info('registering username', username=request.username)
      password_id = 'TODO(P0)' + str(time.time())
      hashed_password = new_hashed_password(request.password)
      self._conn.execute(sqlalchemy.insert(schema.passwords).values(
        login_password_id=password_id,
        salt=hashed_password.salt,
        scrypt=hashed_password.scrypt,
      ))
      self._conn.execute(sqlalchemy.insert(schema.users).values(
        username=request.username,
        login_password_id=password_id,
      ))

      login_response = self.LogInUsername(None, mvp_pb2.LogInUsernameRequest(username=request.username, password=request.password))
      if login_response.WhichOneof('log_in_username_result') != 'ok':
        logging.error('unable to log in as freshly-created user', username=request.username, response=login_response)
        return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall='somehow failed to log you into your fresh account'))
      return mvp_pb2.RegisterUsernameResponse(ok=login_response.ok)

    @transactional
    @checks_token
    @log_action
    def LogInUsername(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.LogInUsernameRequest) -> mvp_pb2.LogInUsernameResponse:
        if token is not None:
            logger.warn('logged-in user trying to log in again', new_username=request.username)
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='already authenticated; first, log out'))

        login_password_info = self._conn.execute(sqlalchemy.select(schema.passwords.c.salt, schema.passwords.c.scrypt).where(sqlalchemy.and_(schema.users.c.username == request.username, schema.users.c.login_password_id == schema.passwords.c.login_password_id))).first()
        if login_password_info is None:
            logger.debug('login attempt for nonexistent user', username=request.username)
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='no such user'))
        if not check_password(request.password, mvp_pb2.HashedPassword(salt=login_password_info['salt'], scrypt=login_password_info['scrypt'])):
            logger.info('login attempt has bad password', possible_malice=True)
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='bad password'))

        logger.debug('username logged in', username=request.username)
        token = self._token_mint.mint_token(owner=Username(request.username), ttl_seconds=60*60*24*365)
        settings_response = self.GetSettings(token, request=mvp_pb2.GetSettingsRequest())
        if settings_response.WhichOneof('get_settings_result') != 'ok':
          logging.error('unable to get settings of successfully-logged-in user', username=request.username, response=login_response)
          return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='somehow failed to get your settings'))

        return mvp_pb2.LogInUsernameResponse(ok=mvp_pb2.AuthSuccess(
          token=token,
          user_info=settings_response.ok,
        ))

    @transactional
    @checks_token
    @log_action
    def CreatePrediction(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.CreatePredictionRequest) -> mvp_pb2.CreatePredictionResponse:
      if token is None:
        logger.warn('not logged in')
        return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall='must log in to create predictions'))

      now = int(self._clock())

      problems = describe_CreatePredictionRequest_problems(request, now=now)
      if problems is not None:
        return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall=problems))

      prediction_id = int(time.time() * 100000000) % (2**32) # TODO(P0)
      logger.debug('creating prediction', prediction_id=prediction_id, request=request)
      self._conn.execute(sqlalchemy.insert(schema.predictions).values(
        prediction_id=prediction_id,
        prediction=request.prediction,
        certainty_low_p=request.certainty.low,
        certainty_high_p=request.certainty.high,
        maximum_stake_cents=request.maximum_stake_cents,
        created_at_unixtime=now,
        closes_at_unixtime=now + request.open_seconds,
        resolves_at_unixtime=request.resolves_at_unixtime,
        special_rules=request.special_rules,
        creator=token.owner,
      ))
      return mvp_pb2.CreatePredictionResponse(new_prediction_id=prediction_id)

    @transactional
    @checks_token
    @log_action
    def GetPrediction(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetPredictionRequest) -> mvp_pb2.GetPredictionResponse:
      view = view_prediction(self._conn, token_owner(token), request.prediction_id)
      if view is None:
        logger.info('trying to get nonexistent prediction', prediction_id=request.prediction_id)
        return mvp_pb2.GetPredictionResponse(error=mvp_pb2.GetPredictionResponse.Error(catchall='no such prediction'))
      return mvp_pb2.GetPredictionResponse(prediction=view)
      

    @transactional
    @checks_token
    @log_action
    def ListMyStakes(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ListMyStakesRequest) -> mvp_pb2.ListMyStakesResponse:
        if token is None:
            logger.info('logged-out user trying to list their predictions')
            return mvp_pb2.ListMyStakesResponse(ok=mvp_pb2.PredictionsById(predictions={}))

        wstate = self._storage.get()
        result = {
            prediction_id: view_prediction(wstate, token_owner(token), prediction)
            for prediction_id, prediction in wstate.predictions.items()
            if prediction.creator == token.owner or any(trade.bettor == token.owner for trade in prediction.trades)
        }

        return mvp_pb2.ListMyStakesResponse(ok=mvp_pb2.PredictionsById(predictions=result))

    @transactional
    @checks_token
    @log_action
    def ListPredictions(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ListPredictionsRequest) -> mvp_pb2.ListPredictionsResponse:
        if token is None:
            logger.info('logged-out user trying to list predictions')
            return mvp_pb2.ListPredictionsResponse(ok=mvp_pb2.PredictionsById(predictions={}))
        creator = Username(request.creator) if request.creator else token_owner(token)

        wstate = self._storage.get()
        if not trusts(wstate, creator, token_owner(token)):
            logger.info('trying to get list untrusting creator\'s predictions', creator=creator)
            return mvp_pb2.ListPredictionsResponse(error=mvp_pb2.ListPredictionsResponse.Error(catchall="creator doesn't trust you"))

        result = {
            prediction_id: view_prediction(wstate, token_owner(token), prediction)
            for prediction_id, prediction in wstate.predictions.items()
            if prediction.creator == creator
        }

        return mvp_pb2.ListPredictionsResponse(ok=mvp_pb2.PredictionsById(predictions=result))

    @transactional
    @checks_token
    @log_action
    def Stake(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.StakeRequest) -> mvp_pb2.StakeResponse:
      if token is None:
        logger.warn('not logged in')
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='must log in to bet'))
      assert request.bettor_stake_cents >= 0, 'protobuf should enforce this being a uint, but just in case...'

      row = self._conn.execute(sqlalchemy.select(schema.predictions).where(schema.predictions.c.prediction_id == request.prediction_id)).fetchone()
      if row is None:
        logger.warn('trying to bet on nonexistent prediction', prediction_id=request.prediction_id)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='no such prediction'))
      if row['creator'] == token.owner:
        logger.warn('trying to bet against self', prediction_id=request.prediction_id)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="can't bet against yourself"))
      if not trusts(self._conn, Username(row['creator']), token_owner(token)):
        logger.warn('trying to bet against untrusting creator', prediction_id=request.prediction_id, possible_malice=True)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="creator doesn't trust you"))
      if not trusts(self._conn, token_owner(token), Username(row['creator'])):
        logger.warn('trying to bet against untrusted creator', prediction_id=request.prediction_id)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="you don't trust the creator"))
      now = self._clock()
      if not (row['created_at_unixtime'] <= now <= row['closes_at_unixtime']):
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="prediction is no longer open for betting"))
      last_resolution = self._conn.execute(
        sqlalchemy.select(schema.resolutions.c.resolution)
        .where(schema.resolutions.c.prediction_id == request.prediction_id)
        .order_by(schema.resolutions.c.resolved_at_unixtime.desc())
        .limit(1)
      ).scalar()

      if (last_resolution is not None) and (mvp_pb2.Resolution.Value(last_resolution) != mvp_pb2.RESOLUTION_NONE_YET):
        logger.warn('trying to bet on a resolved prediction', prediction_id=request.prediction_id)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="prediction has already resolved"))

      if request.bettor_is_a_skeptic:
        lowP = row['certainty_low_p']
        creator_stake_cents = int(request.bettor_stake_cents * lowP/(1-lowP))
      else:
        highP = row['certainty_high_p']
        creator_stake_cents = int(request.bettor_stake_cents * (1-highP)/highP)
      existing_stake = self._conn.execute(
        sqlalchemy.select(sqlalchemy.sql.func.coalesce(sqlalchemy.sql.func.sum(schema.trades.c.creator_stake_cents), 0))
        .where(sqlalchemy.and_(
          schema.trades.c.prediction_id == request.prediction_id,
          schema.trades.c.bettor_is_a_skeptic if request.bettor_is_a_skeptic else sqlalchemy.not_(schema.trades.c.bettor_is_a_skeptic),
        ))
      ).scalar()
      logger.info('existing stake', existing_stake=existing_stake, trades=[dict(r) for r in self._conn.execute(sqlalchemy.select(schema.trades).where(schema.trades.c.prediction_id == request.prediction_id))])
      if existing_stake + creator_stake_cents > row['maximum_stake_cents']:
          logger.warn('trying to make a bet that would exceed creator tolerance', request=request)
          return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall=f'bet would exceed creator tolerance ({existing_stake} existing + {creator_stake_cents} new stake > {row["maximum_stake_cents"]} max)'))
      existing_bettor_exposure = self._conn.execute(
        sqlalchemy.select(sqlalchemy.sql.func.coalesce(sqlalchemy.sql.func.sum(schema.trades.c.bettor_stake_cents), 0))
        .where(sqlalchemy.and_(
          schema.trades.c.prediction_id == request.prediction_id,
          schema.trades.c.bettor_is_a_skeptic == request.bettor_is_a_skeptic,
          schema.trades.c.bettor == token.owner,
        ))
      ).scalar()
      if existing_bettor_exposure + request.bettor_stake_cents > MAX_LEGAL_STAKE_CENTS:
        logger.warn('trying to make a bet that would exceed per-market stake limit', request=request)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall=f'your existing stake of ~${existing_bettor_exposure//100} plus your new stake ~${request.bettor_stake_cents//100} cents would put you over the limit of ${MAX_LEGAL_STAKE_CENTS//100} staked in a single prediction'))
      self._conn.execute(sqlalchemy.insert(schema.trades).values(
        prediction_id=request.prediction_id,
        bettor=token.owner,
        bettor_is_a_skeptic=request.bettor_is_a_skeptic,
        bettor_stake_cents=request.bettor_stake_cents,
        creator_stake_cents=creator_stake_cents,
        transacted_at_unixtime=now,
      ))
      logger.info('trade executed', prediction_id=request.prediction_id, request=request)
      return mvp_pb2.StakeResponse(ok=view_prediction(self._conn, token_owner(token), request.prediction_id))

    @transactional
    @checks_token
    @log_action
    def Resolve(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ResolveRequest) -> mvp_pb2.ResolveResponse:
      if token is None:
        logger.warn('not logged in')
        return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='must log in to resolve a prediction'))
      if request.resolution not in {mvp_pb2.RESOLUTION_YES, mvp_pb2.RESOLUTION_NO, mvp_pb2.RESOLUTION_INVALID, mvp_pb2.RESOLUTION_NONE_YET}:
        logger.warn('user sent unrecognized resolution', resolution=request.resolution)
        return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='unrecognized resolution'))
      if len(request.notes) > 1024:
        logger.warn('unreasonably long notes', snipped_notes=request.notes[:256] + '  <snip>  ' + request.notes[-256:])
        return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='unreasonably long notes'))

      row = self._conn.execute(sqlalchemy.select(schema.predictions).where(schema.predictions.c.prediction_id == request.prediction_id)).fetchone()
      if row is None:
        logger.info('attempt to resolve nonexistent prediction', prediction_id=request.prediction_id)
        return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='no such prediction'))
      if token_owner(token) != row['creator']:
        logger.warn('non-creator trying to resolve prediction', prediction_id=request.prediction_id, creator=row['creator'], possible_malice=True)
        return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall="you are not the creator"))
      self._conn.execute(sqlalchemy.insert(schema.resolutions).values(
        prediction_id=request.prediction_id,
        resolution=mvp_pb2.Resolution.Name(request.resolution),
        resolved_at_unixtime=int(self._clock()),
        notes=request.notes,
      ))

      email_addrs = []
      stakeholders = {
        row['creator'],
        *(row['bettor']
          for row in self._conn.execute(
            sqlalchemy.select(schema.trades.c.bettor.distinct())
            .where(schema.trades.c.prediction_id == request.prediction_id)
          ).fetchall()
        )}
      for stakeholder in stakeholders:
        pass
        # TODO(P1)
        # info = something something
        # if info is None:
        #     logger.error('prediction references nonexistent user', prediction_id=request.prediction_id, user=stakeholder)
        #     continue
        # elif info.email_resolution_notifications and info.email.WhichOneof('email_flow_state_kind') == 'verified':
        #     email_addrs.append(info.email.verified)

      # logger.info('sending resolution emails', prediction_id=request.prediction_id, email_addrs=email_addrs)
      # asyncio.create_task(self._emailer.send_resolution_notifications(
      #     bccs=email_addrs,
      #     prediction_id=PredictionId(request.prediction_id),
      #     prediction=prediction,
      # ))
      return mvp_pb2.ResolveResponse(ok=view_prediction(self._conn, token_owner(token), request.prediction_id))

    @transactional
    @checks_token
    @log_action
    def SetTrusted(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SetTrustedRequest) -> mvp_pb2.SetTrustedResponse:
      if token is None:
        logger.warn('not logged in')
        return mvp_pb2.SetTrustedResponse(error=mvp_pb2.SetTrustedResponse.Error(catchall='must log in to trust folks'))

      if not user_exists(self._conn, Username(request.who)):
        logger.warn('attempting to set trust for nonexistent user')
        return mvp_pb2.SetTrustedResponse(error=mvp_pb2.SetTrustedResponse.Error(catchall='no such user'))

      if self._conn.execute(
            sqlalchemy.select(schema.relationships)
            .where(sqlalchemy.and_(
              schema.relationships.c.subject_username == token.owner,
              schema.relationships.c.object_username == request.who,
            ))).fetchone() is None:
        logger.info('creating relationship between users', who=request.who, trusted=request.trusted)
        self._conn.execute(
          sqlalchemy.insert(schema.relationships).values(
            subject_username=token.owner,
            object_username=request.who,
            trusted=request.trusted,
          )
        )
      else:
        logger.info('setting user trust in existing relationship', who=request.who, trusted=request.trusted)
        self._conn.execute(
          sqlalchemy.update(schema.relationships)
          .values(trusted=request.trusted)
          .where(sqlalchemy.and_(
            schema.relationships.c.subject_username == token.owner,
            schema.relationships.c.object_username == request.who,
          ))
        )

      return mvp_pb2.SetTrustedResponse(ok=self.GetSettings(token, mvp_pb2.GetSettingsRequest()).ok)

    @transactional
    @checks_token
    @log_action
    def GetUser(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetUserRequest) -> mvp_pb2.GetUserResponse:
        wstate = self._storage.get()
        if not user_exists(wstate, Username(request.who)):
            logger.info('attempting to view nonexistent user', who=request.who)
            return mvp_pb2.GetUserResponse(error=mvp_pb2.GetUserResponse.Error(catchall='no such user'))

        return mvp_pb2.GetUserResponse(ok=mvp_pb2.UserUserView(
            username=request.who,
            is_trusted=trusts(wstate, token_owner(token), Username(request.who)) if (token is not None) else False,
            trusts_you=trusts(wstate, Username(request.who), token_owner(token)) if (token is not None) else False,
        ))

    @transactional
    @checks_token
    @log_action
    def ChangePassword(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ChangePasswordRequest) -> mvp_pb2.ChangePasswordResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall='must log in to change your password'))
        password_problems = describe_password_problems(request.new_password)
        if password_problems is not None:
            logger.warn('attempting to set bad password')
            return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall=password_problems))

        with self._storage.mutate() as wstate:
            info = wstate.user_settings.get(token.owner)
            if info is None:
                raise ForgottenTokenError(token)
            if info.WhichOneof('login_type') != 'login_password':
                logger.warn('password-change request for non-password user', possible_malice=True)
                return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall="you don't use a password to log in"))

            if not check_password(request.old_password, info.login_password):
                logger.warn('password-change request has wrong password', possible_malice=True)
                return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall='wrong old password'))

            info.login_password.CopyFrom(new_hashed_password(request.new_password))

            logger.info('changing password', who=token.owner)
            return mvp_pb2.ChangePasswordResponse(ok=mvp_pb2.VOID)

    @transactional
    @checks_token
    @log_action
    def SetEmail(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SetEmailRequest) -> mvp_pb2.SetEmailResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.SetEmailResponse(error=mvp_pb2.SetEmailResponse.Error(catchall='must log in to set an email'))
        problems = describe_SetEmailRequest_problems(request)
        if problems is not None:
            logger.warn('attempting to set invalid email', problems=problems)
            return mvp_pb2.SetEmailResponse(error=mvp_pb2.SetEmailResponse.Error(catchall=problems))

        with self._storage.mutate() as wstate:
            requester_info = get_generic_user_info(wstate, token_owner(token))
            if requester_info is None:
                raise ForgottenTokenError(token)
            if request.email:
                # TODO: prevent an email address from getting "too many" emails if somebody abuses us
                code = secrets.token_urlsafe(nbytes=16)
                asyncio.create_task(self._emailer.send_email_verification(
                    to=request.email,
                    code=code,
                ))
                requester_info.email.MergeFrom(mvp_pb2.EmailFlowState(code_sent=mvp_pb2.EmailFlowState.CodeSent(email=request.email, code=new_hashed_password(code))))
                wstate.user_settings[token.owner].CopyFrom(requester_info) # TODO: hack
                logger.info('set email address', who=token.owner, address=request.email)
            else:
                requester_info.email.MergeFrom(mvp_pb2.EmailFlowState(unstarted=mvp_pb2.VOID))
                logger.info('dissociated email address', who=token.owner)
            return mvp_pb2.SetEmailResponse(ok=requester_info.email)

    @transactional
    @checks_token
    @log_action
    def VerifyEmail(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.VerifyEmailRequest) -> mvp_pb2.VerifyEmailResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.VerifyEmailResponse(error=mvp_pb2.VerifyEmailResponse.Error(catchall='must log in to change your password'))

        with self._storage.mutate() as wstate:
            requester_info = get_generic_user_info(wstate, token_owner(token))
            if requester_info is None:
                raise ForgottenTokenError(token)
            if not (requester_info.email and requester_info.email.WhichOneof('email_flow_state_kind') == 'code_sent'):
                logger.warn('attempting to verify email, but no email outstanding', possible_malice=True)
                return mvp_pb2.VerifyEmailResponse(error=mvp_pb2.VerifyEmailResponse.Error(catchall='you have no pending email-verification flow'))
            code_sent_state = requester_info.email.code_sent
            if not check_password(request.code, code_sent_state.code):
                logger.warn('bad email-verification code', address=code_sent_state.email, possible_malice=True)
                return mvp_pb2.VerifyEmailResponse(error=mvp_pb2.VerifyEmailResponse.Error(catchall='bad code'))
            requester_info.email.CopyFrom(mvp_pb2.EmailFlowState(verified=code_sent_state.email))
            logger.info('verified email address', who=token.owner, address=code_sent_state.email)
            return mvp_pb2.VerifyEmailResponse(ok=requester_info.email)

    @transactional
    @checks_token
    @log_action
    def GetSettings(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetSettingsRequest) -> mvp_pb2.GetSettingsResponse:
        if token is None:
          logger.info('not logged in')
          return mvp_pb2.GetSettingsResponse(error=mvp_pb2.GetSettingsResponse.Error(catchall='must log in to see your settings'))

        row = self._conn.execute(sqlalchemy.select(
          schema.users.c.email_reminders_to_resolve,
          schema.users.c.email_resolution_notifications,
        ).where(schema.users.c.username == token.owner)).first()
        if row is None:
          raise ForgottenTokenError(token)
        info = mvp_pb2.GenericUserInfo(
          email_reminders_to_resolve=row['email_reminders_to_resolve'],
          email_resolution_notifications=row['email_resolution_notifications'],
          # TODO(P0): email
          # TODO(P0): relationships
          # TODO(P0): invitations
        )
        return mvp_pb2.GetSettingsResponse(ok=info)

    @transactional
    @checks_token
    @log_action
    def UpdateSettings(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.UpdateSettingsRequest) -> mvp_pb2.UpdateSettingsResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.UpdateSettingsResponse(error=mvp_pb2.UpdateSettingsResponse.Error(catchall='must log in to update your settings'))

        with self._storage.mutate() as wstate:
            info = get_generic_user_info(wstate, token_owner(token))
            if info is None:
                raise ForgottenTokenError(token)
            if request.HasField('email_reminders_to_resolve'):
                info.email_reminders_to_resolve = request.email_reminders_to_resolve.value
            if request.HasField('email_resolution_notifications'):
                info.email_resolution_notifications = request.email_resolution_notifications.value
            logger.info('updated settings', request=request)
            return mvp_pb2.UpdateSettingsResponse(ok=info)

    @transactional
    @checks_token
    @log_action
    def CreateInvitation(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.CreateInvitationRequest) -> mvp_pb2.CreateInvitationResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.CreateInvitationResponse(error=mvp_pb2.CreateInvitationResponse.Error(catchall='must log in to create an invitation'))

        with self._storage.mutate() as wstate:
            info = get_generic_user_info(wstate, token_owner(token))
            if info is None:
                raise ForgottenTokenError(token)

            nonce = secrets.token_urlsafe(16)
            invitation = mvp_pb2.Invitation(
                created_unixtime=int(self._clock()),
                notes=request.notes,
                accepted_by=None,
            )
            info.invitations[nonce].CopyFrom(invitation)
            return mvp_pb2.CreateInvitationResponse(ok=mvp_pb2.CreateInvitationResponse.Result(
                id=mvp_pb2.InvitationId(inviter=token_owner(token), nonce=nonce),
                invitation=invitation,
                user_info=info,
            ))

    @transactional
    @checks_token
    @log_action
    def CheckInvitation(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.CheckInvitationRequest) -> mvp_pb2.CheckInvitationResponse:
        if not (request.HasField('invitation_id') and request.invitation_id.inviter):
            logger.warn('malformed CheckInvitationRequest')
            return mvp_pb2.CheckInvitationResponse(error=mvp_pb2.CheckInvitationResponse.Error(catchall='malformed invitation'))
        wstate = self._storage.get()

        inviter = Username(request.invitation_id.inviter)
        inviter_info = get_generic_user_info(wstate, inviter)
        if inviter_info is None:
            logger.warn('trying to get invitation from nonexistent user')
            return mvp_pb2.CheckInvitationResponse(is_open=False)

        invitation = inviter_info.invitations.get(request.invitation_id.nonce)
        if invitation is None:
            logger.warn('trying to get nonexistent invitation')
            return mvp_pb2.CheckInvitationResponse(is_open=False)

        return mvp_pb2.CheckInvitationResponse(is_open=not invitation.accepted_by)

    @transactional
    @checks_token
    @log_action
    def AcceptInvitation(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.AcceptInvitationRequest) -> mvp_pb2.AcceptInvitationResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.AcceptInvitationResponse(error=mvp_pb2.AcceptInvitationResponse.Error(catchall='must log in to create an invitation'))
        problems = describe_AcceptInvitationRequest_problems(request)
        if problems is not None:
            logger.warn('invalid AcceptInvitationRequest', problems=problems)
            return mvp_pb2.AcceptInvitationResponse(error=mvp_pb2.AcceptInvitationResponse.Error(catchall=problems))

        with self._storage.mutate() as wstate:
            if (not request.HasField('invitation_id')) or (not request.invitation_id.inviter):
                logger.warn('malformed attempt to accept invitation', possible_malice=True)
                return mvp_pb2.AcceptInvitationResponse(error=mvp_pb2.AcceptInvitationResponse.Error(catchall='malformed invitation'))

            accepter_info = get_generic_user_info(wstate, token_owner(token))
            if accepter_info is None:
                raise ForgottenTokenError(token)

            inviter = Username(request.invitation_id.inviter)
            inviter_info = get_generic_user_info(wstate, inviter)
            if inviter_info is None:
                return mvp_pb2.AcceptInvitationResponse(error=mvp_pb2.AcceptInvitationResponse.Error(catchall='invitation is non-existent or already used'))

            for orig_nonce, orig_invitation in inviter_info.invitations.items():
                # TODO: just index in, dummy
                if orig_nonce == request.invitation_id.nonce:
                    if orig_invitation.accepted_by:
                        logger.info('attempt to re-accept invitation')
                        return mvp_pb2.AcceptInvitationResponse(error=mvp_pb2.AcceptInvitationResponse.Error(catchall='invitation is non-existent or already used'))
                    orig_invitation.accepted_by = token.owner
                    orig_invitation.accepted_unixtime = int(self._clock())
                    accepter_info.relationships[inviter].trusted = True
                    inviter_info.relationships[token.owner].trusted = True
                    logger.info('accepted invitation', whose=inviter)
                    return mvp_pb2.AcceptInvitationResponse(ok=accepter_info)
            logger.warn('attempt to accept nonexistent invitation', possible_malice=True)
            return mvp_pb2.AcceptInvitationResponse(error=mvp_pb2.AcceptInvitationResponse.Error(catchall='invitation is non-existent or already used'))



def walk(obj: object) -> Iterator[object]:
  yield obj
  if isinstance(obj, Message):
    for _, child in obj.ListFields():
      yield from walk(child)
  elif isinstance(obj, Mapping):
    for child in obj.values():
      yield from walk(child)
  elif isinstance(obj, Sequence) and not isinstance(obj, str):
    for child in obj:
      yield from walk(child)

def find_invariant_violations(wstate: mvp_pb2.WorldState) -> Sequence[Mapping[str, Any]]:
    violations: MutableSequence[Mapping[str, Any]] = []
    for prediction_id, prediction in wstate.predictions.items():
        if sum(t.creator_stake_cents for t in prediction.trades if     t.bettor_is_a_skeptic) > prediction.maximum_stake_cents:
            violations.append({'type':'exposure exceeded', 'prediction_id':prediction_id})
        if sum(t.creator_stake_cents for t in prediction.trades if not t.bettor_is_a_skeptic) > prediction.maximum_stake_cents:
            violations.append({'type':'exposure exceeded', 'prediction_id':prediction_id})
    return violations


async def email_invariant_violations_forever(storage: 'FsStorage', emailer: Emailer, recipient_email: str):
    while True:
        now = datetime.datetime.now()
        next_hour = datetime.datetime.fromtimestamp(3600 * (1 + now.timestamp()//3600))
        await asyncio.sleep((next_hour - now).total_seconds())
        logger.info('checking invariants')
        violations = find_invariant_violations(storage.get())
        if violations:
            await emailer.send_invariant_violations(
                to=recipient_email,
                now=next_hour,
                violations=violations,
            )

async def email_daily_backups_forever(storage: 'FsStorage', emailer: Emailer, recipient_email: str):
    while True:
        now = datetime.datetime.now()
        next_day = datetime.datetime.fromtimestamp(86400 * (1 + now.timestamp()//86400))
        await asyncio.sleep((next_day - now).total_seconds())
        logger.info('emailing backups')
        await emailer.send_backup(
            to=recipient_email,
            now=next_day,
            wstate=storage.get(),
        )

def prediction_needs_email_reminder(now: datetime.datetime, prediction: mvp_pb2.WorldState.Prediction) -> bool:
    history = prediction.resolution_reminder_history
    return (
        prediction.resolves_at_unixtime < now.timestamp()
        and not history.skipped
        and not any(attempt.succeeded for attempt in history.attempts)
        and not (len(history.attempts) >= 3 and not any(attempt.succeeded for attempt in history.attempts[-3:]))
    )

def get_email_for_resolution_reminder(user_info: mvp_pb2.GenericUserInfo) -> Optional[str]:
    if (user_info.email_reminders_to_resolve
        and user_info.HasField('email')
        and user_info.email.WhichOneof('email_flow_state_kind') == 'verified'
        ):
        return user_info.email.verified
    return None

async def email_resolution_reminder_if_necessary(now: datetime.datetime, emailer: Emailer, storage: 'FsStorage', prediction_id: PredictionId) -> None:
    immut_wstate = storage.get()
    prediction = immut_wstate.predictions.get(prediction_id)
    if prediction is None:
        raise KeyError(f'no such prediction: {prediction_id}')

    if not prediction_needs_email_reminder(now=now, prediction=prediction):
        return

    creator_info = get_generic_user_info(immut_wstate, Username(prediction.creator))
    if creator_info is None:
        logger.error("prediction has nonexistent creator", prediction_id=prediction_id, creator=prediction.creator)
        return
    email_addr = get_email_for_resolution_reminder(creator_info)

    if email_addr is None:
        with storage.mutate() as mut_wstate:
            mut_wstate.predictions[prediction_id].resolution_reminder_history.skipped = True
    else:
        try:
            await emailer.send_resolution_reminder(
                to=email_addr,
                prediction_id=PredictionId(prediction_id),
                prediction=prediction,
            )
            succeeded = True
        except Exception as e:
            logger.error('failed to send resolution reminder email', to=email_addr, prediction_id=prediction_id)
            succeeded = False

        with storage.mutate() as mut_wstate:
            mut_wstate.predictions[prediction_id].resolution_reminder_history.attempts.append(
                mvp_pb2.EmailAttempt(unixtime=now.timestamp(), succeeded=succeeded)
            )

async def email_resolution_reminders_forever(storage: 'FsStorage', emailer: Emailer, interval: datetime.timedelta = datetime.timedelta(hours=1)):
    interval_secs = interval.total_seconds()
    while True:
        logger.info('waking up to email resolution reminders')
        cycle_start_time = int(time.time())
        wstate = storage.get()

        for prediction_id, prediction in wstate.predictions.items():
            await email_resolution_reminder_if_necessary(
                now=datetime.datetime.now(),
                emailer=emailer,
                storage=storage,
                prediction_id=PredictionId(prediction_id),
            )

        next_cycle_time = cycle_start_time + interval_secs
        time_to_next_cycle = next_cycle_time - time.time()
        if time_to_next_cycle < interval_secs / 2:
            logger.warn('sending resolution-reminders took dangerously long', interval_secs=interval_secs, time_remaining=time.time() - cycle_start_time)
        await asyncio.sleep(time_to_next_cycle)
