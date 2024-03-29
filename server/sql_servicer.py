#! /usr/bin/env python3

from __future__ import annotations

import asyncio
import contextlib
import datetime
import functools
import json
from pathlib import Path
import random
import secrets
import time
from typing import Any, Awaitable, Iterator, Mapping, Optional, MutableMapping, MutableSequence, NoReturn, Callable, NoReturn, Iterable, Sequence, MutableSequence
from typing_extensions import TypedDict
import logging
import os
from email.message import EmailMessage

import sqlalchemy
from sqlalchemy import sql

from .api_server import *
from .core import *
from .emailer import *
from .http_glue import *
from .web_server import *
from .protobuf import mvp_pb2
from . import sql_schema as schema

import structlog
logger = structlog.get_logger()



class SqlConn:
  def  __init__(self, conn: sqlalchemy.engine.base.Connection):
    self._conn = conn

  @contextlib.contextmanager
  def transaction(self) -> Iterator[None]:
    with self._conn.begin():
      yield

  def register_username(self, username: Username, password: str, password_id: str, email_address: str) -> None:
      if self.user_exists(username):
        raise UsernameAlreadyRegisteredError(username)
      hashed_password = new_hashed_password(password)
      self._conn.execute(sqlalchemy.insert(schema.passwords).values(
        password_id=password_id,
        salt=hashed_password.salt,
        scrypt=hashed_password.scrypt,
      ))
      self._conn.execute(sqlalchemy.insert(schema.users).values(
        username=username,
        email_address=email_address,
        login_password_id=password_id,
      ))

  def get_username_password_info(self, username: Username) -> Optional[mvp_pb2.HashedPassword]:
    row = self._conn.execute(
      sqlalchemy.select([schema.passwords.c.salt, schema.passwords.c.scrypt])
      .where(sqlalchemy.and_(
        schema.users.c.username == username,
        schema.users.c.login_password_id == schema.passwords.c.password_id,
      ))
    ).first()
    if row is None:
      return None
    return mvp_pb2.HashedPassword(salt=row['salt'], scrypt=row['scrypt'])

  def create_prediction(
    self,
    now: datetime.datetime,
    prediction_id: PredictionId,
    creator: Username,
    request: mvp_pb2.CreatePredictionRequest,
  ) -> None:
    now_unixtime = round(now.timestamp())
    self._conn.execute(sqlalchemy.insert(schema.predictions).values(
      prediction_id=prediction_id,
      prediction=request.prediction,
      certainty_low_p=request.certainty.low,
      certainty_high_p=request.certainty.high,
      maximum_stake_cents=request.maximum_stake_cents,
      created_at_unixtime=now_unixtime,
      closes_at_unixtime=now_unixtime + request.open_seconds,
      resolves_at_unixtime=request.resolves_at_unixtime,
      view_privacy=mvp_pb2.PredictionViewPrivacy.Name(request.view_privacy),
      special_rules=request.special_rules,
      creator=creator,
    ))

  def user_exists(self, user: Username) -> bool:
    return self._conn.execute(sqlalchemy.select(schema.users.c).where(schema.users.c.username == user)).first() is not None

  def email_is_registered(self, email_address: str) -> bool:
    return self._conn.execute(sqlalchemy.select(schema.users.c).where(schema.users.c.email_address == email_address)).first() is not None

  def trusts(self, a: Username, b: Username) -> bool:
    if a == b:
      return True

    result: Optional[bool] = self._conn.execute(
      sqlalchemy.select([schema.relationships.c.trusted])
      .where(sqlalchemy.and_(
        schema.relationships.c.subject_username == a,
        schema.relationships.c.object_username == b,
        schema.relationships.c.trusted,
      ))
    ).scalar()

    return bool(result)

  def view_prediction(self, viewer: Optional[Username], prediction_id: PredictionId) -> Optional[mvp_pb2.UserPredictionView]:
    row = self._conn.execute(sqlalchemy.select(schema.predictions.c).where(schema.predictions.c.prediction_id == prediction_id)).first()
    if row is None:
      return None

    creator_is_viewer = (viewer == row['creator'])

    creator_settings_row = self._conn.execute(
      sqlalchemy.select(schema.users.c)
      .where(schema.users.c.username == row['creator'])
    ).fetchone()
    assert creator_settings_row is not None  # else the "prediction.creator -> user.username" integrity constraint is broken

    resolution = self.get_resolution(prediction_id)

    trade_rows = self._conn.execute(
      sqlalchemy.select(schema.trades.c)
      .where(sqlalchemy.and_(
        schema.trades.c.prediction_id == prediction_id,
        True if creator_is_viewer else (schema.trades.c.bettor == viewer)
      ))
      .order_by(schema.trades.c.transacted_at_unixtime)
    ).fetchall()

    remaining_stake_cents_vs_believers = int(
      row['maximum_stake_cents'] - self.get_creator_exposure_cents(prediction_id, against_skeptics=False)
    )
    remaining_stake_cents_vs_skeptics = int(
      row['maximum_stake_cents'] - self.get_creator_exposure_cents(prediction_id, against_skeptics=True)
    )

    follow_row = self._conn.execute(
      sqlalchemy.select(schema.prediction_follows.c)
      .where(sqlalchemy.and_(
        schema.prediction_follows.c.prediction_id == prediction_id,
        schema.prediction_follows.c.follower == viewer,
      ))
    ).fetchone()

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
      creator=row['creator'],
      resolution=resolution,
      your_trades=[
        mvp_pb2.Trade(
          bettor=t['bettor'],
          bettor_is_a_skeptic=t['bettor_is_a_skeptic'],
          creator_stake_cents=t['creator_stake_cents'],
          bettor_stake_cents=t['bettor_stake_cents'],
          transacted_unixtime=t['transacted_at_unixtime'],
          updated_unixtime=t['updated_at_unixtime'],
          state=mvp_pb2.TradeState.Value(t['state']),
          notes=t['notes'],
        )
        for t in trade_rows
      ],
      your_following_status=(
        mvp_pb2.PREDICTION_FOLLOWING_MANDATORY_BECAUSE_STAKED if (creator_is_viewer or trade_rows) else
        mvp_pb2.PREDICTION_FOLLOWING_FOLLOWING if follow_row is not None else
        mvp_pb2.PREDICTION_FOLLOWING_NOT_FOLLOWING
      ),
    )

  def list_stakes(self, user: Username) -> Iterable[PredictionId]:
    return {
      *[PredictionId(row['prediction_id'])
        for row in self._conn.execute(
          sqlalchemy.select([schema.predictions.c.prediction_id])
          .where(schema.predictions.c.creator == user)
        ).fetchall()],
      *[PredictionId(row['prediction_id'])
        for row in self._conn.execute(
          sqlalchemy.select([schema.trades.c.prediction_id.distinct()])
          .where(sqlalchemy.and_(
            schema.trades.c.bettor == user,
            # schema.trades.c.state == mvp_pb2.TradeState.Name(mvp_pb2.TRADE_STATE_ACTIVE),
          ))
        ).fetchall()],
    }

  def list_predictions_created(self, creator: Username, privacies: Iterable[mvp_pb2.PredictionViewPrivacy.V]) -> Iterable[PredictionId]:
    privacy_names = {mvp_pb2.PredictionViewPrivacy.Name(p) for p in privacies}
    return {
      PredictionId(row['prediction_id'])
      for row in self._conn.execute(
        sqlalchemy.select([schema.predictions.c.prediction_id, schema.predictions.c.view_privacy])
        .where(sqlalchemy.and_(
          schema.predictions.c.creator == creator,
          schema.predictions.c.view_privacy.in_(privacy_names),
        ))
      ).fetchall()
    }

  PredictionInfo = TypedDict('PredictionInfo',
                 {'creator': Username,
                  'prediction': str,
                  'created_at_unixtime': int,
                  'closes_at_unixtime': int,
                  'certainty_low_p': float,
                  'certainty_high_p': float,
                  'maximum_stake_cents': int,
                 })
  def get_prediction_info(
    self,
    prediction_id: PredictionId,
  ) -> Optional[PredictionInfo]:
    row = self._conn.execute(
      sqlalchemy.select(schema.predictions.c)
      .where(schema.predictions.c.prediction_id == prediction_id)
    ).fetchone()
    if row is None:
      return None
    return {
      'creator': Username(row['creator']),
      'prediction': str(row['prediction']),
      'created_at_unixtime': int(row['created_at_unixtime']),
      'closes_at_unixtime': int(row['closes_at_unixtime']),
      'certainty_low_p': float(row['certainty_low_p']),
      'certainty_high_p': float(row['certainty_high_p']),
      'maximum_stake_cents': int(row['maximum_stake_cents']),
    }

  @staticmethod
  def _trade_row_to_pb(row) -> mvp_pb2.Trade:
    return mvp_pb2.Trade(
      bettor=str(row['bettor']),
      bettor_is_a_skeptic=bool(row['bettor_is_a_skeptic']),
      bettor_stake_cents=int(row['bettor_stake_cents']),
      creator_stake_cents=int(row['creator_stake_cents']),
      transacted_unixtime=float(row['transacted_at_unixtime']),
      updated_unixtime=float(row['updated_at_unixtime']),
      state=mvp_pb2.TradeState.Value(row['state']),
      notes=str(row['notes']),
    )

  def get_trades(
    self,
    prediction_id: PredictionId,
  ) -> Iterable[mvp_pb2.Trade]:
    rows = self._conn.execute(
      sqlalchemy.select(schema.trades.c)
      .where(schema.trades.c.prediction_id == prediction_id)
    ).fetchall()
    return [SqlConn._trade_row_to_pb(row) for row in rows]

  def get_resolution(
    self,
    prediction_id: PredictionId,
  ) -> Optional[mvp_pb2.ResolutionEvent]:
    rows = self._conn.execute(
      sqlalchemy.select(schema.resolutions.c)
      .where(schema.resolutions.c.prediction_id == prediction_id)
      .order_by(schema.resolutions.c.resolved_at_unixtime)
    ).fetchall()
    last_event = None
    for row in rows:
      last_event = mvp_pb2.ResolutionEvent(
        unixtime=float(row['resolved_at_unixtime']),
        resolution=mvp_pb2.Resolution.Value(row['resolution']),
        notes=str(row['notes']),
        prior_revision=last_event,
      )
    return last_event

  def get_creator_exposure_cents(
    self,
    prediction_id: PredictionId,
    against_skeptics: bool,
  ) -> int:
    return int(self._conn.execute(
      sqlalchemy.select([
        sqlalchemy.sql.func.sum(schema.trades.c.creator_stake_cents).label('exposure'),
      ])
      .select_from(schema.predictions.join(schema.trades))
      .where(sqlalchemy.and_(
        schema.predictions.c.prediction_id == prediction_id,
        schema.trades.c.bettor_is_a_skeptic if against_skeptics else sqlalchemy.not_(schema.trades.c.bettor_is_a_skeptic),
        schema.trades.c.state == mvp_pb2.TradeState.Name(mvp_pb2.TRADE_STATE_ACTIVE),
      ))
    ).scalar() or 0)

  def get_bettor_exposure_cents(
    self,
    prediction_id: PredictionId,
    bettor: Username,
    bettor_is_a_skeptic: bool
  ) -> int:
    return int(self._conn.execute(
      sqlalchemy.select([
        sqlalchemy.sql.func.sum(schema.trades.c.bettor_stake_cents).label('exposure'),
      ])
      .select_from(schema.predictions.join(schema.trades))
      .where(sqlalchemy.and_(
        schema.trades.c.bettor == bettor,
        schema.predictions.c.prediction_id == prediction_id,
        schema.trades.c.bettor_is_a_skeptic if bettor_is_a_skeptic else sqlalchemy.not_(schema.trades.c.bettor_is_a_skeptic),
        schema.trades.c.state == mvp_pb2.TradeState.Name(mvp_pb2.TRADE_STATE_ACTIVE),
      ))
    ).scalar() or 0)

  def stake(
    self,
    prediction_id: PredictionId,
    bettor: Username,
    bettor_is_a_skeptic: bool,
    bettor_stake_cents: int,
    creator_stake_cents: int,
    state: mvp_pb2.TradeState.V,
    now: datetime.datetime,
  ) -> None:
    self._conn.execute(sqlalchemy.insert(schema.trades).values(
      prediction_id=prediction_id,
      bettor=bettor,
      bettor_is_a_skeptic=bettor_is_a_skeptic,
      bettor_stake_cents=bettor_stake_cents,
      creator_stake_cents=creator_stake_cents,
      state=mvp_pb2.TradeState.Name(state),
      transacted_at_unixtime=now.timestamp(),
      updated_at_unixtime=now.timestamp(),
    ))

  def set_following(
    self,
    prediction_id: PredictionId,
    follower: Username,
    follow: bool,
  ) -> None:
    if follow:
      self._conn.execute(
        sqlalchemy.insert(schema.prediction_follows)
        .values(
          prediction_id=prediction_id,
          follower=follower,
        )
      )
    else:
      self._conn.execute(
        sqlalchemy.delete(schema.prediction_follows)
        .where(sqlalchemy.and_(
          schema.prediction_follows.c.prediction_id == prediction_id,
          schema.prediction_follows.c.follower == follower,
        ))
      )

  def resolve(
    self,
    request: mvp_pb2.ResolveRequest,
    now: datetime.datetime,
  ) -> None:
    self._conn.execute(sqlalchemy.insert(schema.resolutions).values(
      prediction_id=request.prediction_id,
      resolution=mvp_pb2.Resolution.Name(request.resolution),
      resolved_at_unixtime=round(now.timestamp()),
      notes=request.notes,
    ))

  def set_trusted(self, subject_username: Username, object_username: Username, trusted: bool, now: datetime.datetime) -> None:
    if self._conn.execute(
          sqlalchemy.select(schema.relationships.c)
          .where(sqlalchemy.and_(
            schema.relationships.c.subject_username == subject_username,
            schema.relationships.c.object_username == object_username,
          ))).fetchone() is None:
      logger.info('creating relationship between users', who=object_username, trusted=trusted)
      self._conn.execute(
        sqlalchemy.insert(schema.relationships).values(
          subject_username=subject_username,
          object_username=object_username,
          trusted=trusted,
        )
      )
    else:
      logger.info('setting user trust in existing relationship', who=object_username, trusted=trusted)
      self._conn.execute(
        sqlalchemy.update(schema.relationships)
        .values(trusted=trusted)
        .where(sqlalchemy.and_(
          schema.relationships.c.subject_username == subject_username,
          schema.relationships.c.object_username == object_username,
        ))
      )

    if self.trusts(subject_username, object_username) and self.trusts(object_username, subject_username):
      self._dequeue_trades(bettor=subject_username, creator=object_username, now=now)
      self._dequeue_trades(bettor=object_username, creator=subject_username, now=now)

  def _dequeue_trades(self, bettor: Username, creator: Username, now: datetime.datetime) -> None:
    queued_trades = self._conn.execute(
      sqlalchemy.select(schema.trades.c)
      .where(sqlalchemy.and_(
        schema.trades.c.bettor == bettor,
        schema.trades.c.state == mvp_pb2.TradeState.Name(mvp_pb2.TRADE_STATE_QUEUED),
        schema.trades.c.prediction_id == schema.predictions.c.prediction_id,
        schema.predictions.c.creator == creator,
      ))
      .order_by(schema.trades.c.transacted_at_unixtime.asc())
    ).fetchall()
    predinfos_ = {predid: self.get_prediction_info(predid) for predid in {qt['prediction_id'] for qt in queued_trades}}
    predinfos = {predid: predinfo for predid, predinfo in predinfos_.items() if predinfo}
    if predinfos != predinfos_:
      logger.error('queued trades reference nonexistent predictions', missing_predids={predid for predid, predinfo in predinfos_ if predinfo is None})

    for qt in queued_trades:
      predinfo = predinfos[qt['prediction_id']]

      existing_creator_exposure = self.get_creator_exposure_cents(PredictionId(qt['prediction_id']), against_skeptics=qt['bettor_is_a_skeptic'])

      creator_stake_cents = min(qt['creator_stake_cents'], predinfo['maximum_stake_cents']-existing_creator_exposure)
      bettor_stake_cents = round(qt['bettor_stake_cents'] * creator_stake_cents/qt['creator_stake_cents'])
      if creator_stake_cents < 10 and bettor_stake_cents < 10:
        logger.warn('dropping a queued bet instead of partially committing a trivial trade', queued_trade=qt, predinfo=predinfo, new_creator_stake=creator_stake_cents, new_bettor_stake=bettor_stake_cents)
        values = dict(
          state=mvp_pb2.TradeState.Name(mvp_pb2.TRADE_STATE_DEQUEUE_FAILED),
          notes=f'[trade ignored during dequeue due to trivial stakes]' + (('\n'+qt['notes']) if qt['notes'] else ''),
        )
      else:
        if creator_stake_cents < qt['creator_stake_cents']:
          logger.warn('queued trade will be only partially applied', queued_trade=qt, predinfo=predinfo, new_creator_stake=creator_stake_cents, new_bettor_stake=bettor_stake_cents)
        values = dict(
          bettor_stake_cents=bettor_stake_cents,
          creator_stake_cents=creator_stake_cents,
          state=mvp_pb2.TradeState.Name(mvp_pb2.TRADE_STATE_ACTIVE),
          notes=qt['notes'] or f'Initially queued; committed at {now:%Y-%m-%d %H:%M}',
        )
      self._conn.execute(
        sqlalchemy.update(schema.trades)
        .where(sqlalchemy.and_(
          schema.trades.c.prediction_id == qt['prediction_id'],
          schema.trades.c.bettor == qt['bettor'],
          schema.trades.c.bettor_is_a_skeptic == qt['bettor_is_a_skeptic'],
          schema.trades.c.transacted_at_unixtime == qt['transacted_at_unixtime'],
        ))
        .values(
          updated_at_unixtime=now.timestamp(),
          **values
        )
      )

  def change_password(self, user: Username, new_password: str) -> None:
    pwid = self._conn.execute(
      sqlalchemy.select([schema.users.c.login_password_id])
      .where(schema.users.c.username == user)
    ).scalar()
    if pwid is None:
      raise ValueError('no such user', user)
    new = new_hashed_password(new_password)
    self._conn.execute(
      sqlalchemy.update(schema.passwords)
      .values(salt=new.salt, scrypt=new.scrypt)
      .where(schema.passwords.c.password_id == pwid)
    )

  def get_email(self, user: Username) -> Optional[str]:
    return self._conn.execute(
      sqlalchemy.select([schema.users.c.email_address])
      .where(schema.users.c.username == user)
    ).scalar()

  def get_resolution_notification_addrs(self, prediction_id: PredictionId) -> Iterable[str]:
    q_bettors = (
      sqlalchemy.select([schema.users.c.email_address])
      .where(sqlalchemy.and_(
          schema.trades.c.prediction_id == prediction_id,
          schema.trades.c.bettor == schema.users.c.username,
      ))
    )
    q_followers = (
      sqlalchemy.select([schema.users.c.email_address])
      .where(sqlalchemy.and_(
          schema.prediction_follows.c.prediction_id == prediction_id,
          schema.prediction_follows.c.follower == schema.users.c.username,
      ))
    )
    return {row['email_address'] for row in self._conn.execute(q_bettors.union(q_followers))}

  def get_settings(self, user: AuthorizingUsername, include_relationships_with_users: Iterable[Username] = ()) -> Optional[mvp_pb2.GenericUserInfo]:
    row = self._conn.execute(
      sqlalchemy.select(schema.users.c)
      .where(schema.users.c.username == user)
    ).first()
    if row is None:
      return None
    outgoing_relationships = self._conn.execute(
      sqlalchemy.select(schema.relationships.c)
      .where(schema.relationships.c.subject_username == user)
    ).fetchall()
    include_relationships_with_users = set(include_relationships_with_users) | {row['object_username'] for row in outgoing_relationships}
    outgoing_relationships_by_name = {row['object_username']: row for row in outgoing_relationships}
    trusting_users = {row['subject_username'] for row in self._conn.execute(
      sqlalchemy.select(schema.relationships.c)
      .where(sqlalchemy.and_(
        schema.relationships.c.subject_username.in_(include_relationships_with_users),
        schema.relationships.c.object_username == user,
        schema.relationships.c.trusted,
      ))
    )}
    return mvp_pb2.GenericUserInfo(
      email_address=str(row['email_address']),
      relationships={
        who: mvp_pb2.Relationship(
          trusted_by_you=outgoing_relationships_by_name[who]['trusted'] if who in outgoing_relationships_by_name else False,
          trusts_you=who in trusting_users,
        )
        for who in include_relationships_with_users
      },
      invitations={
        row['recipient']: mvp_pb2.GenericUserInfo.Invitation()
        for row in self._conn.execute(
          sqlalchemy.select([schema.email_invitations.c.recipient])
          .where(schema.email_invitations.c.inviter == user)
        )
      },
    )

  def create_invitation(self, nonce: str, inviter: Username, recipient: Username) -> None:
    self._conn.execute(
      sqlalchemy.insert(schema.email_invitations)
      .values(
        nonce=nonce,
        inviter=inviter,
        recipient=recipient,
      )
    )

  def check_invitation(self, nonce: str) -> Optional[mvp_pb2.CheckInvitationResponse.Result]:
    row = self._conn.execute(
      sqlalchemy.select(schema.email_invitations.c)
      .where(schema.email_invitations.c.nonce == nonce)
    ).fetchone()
    if row is None:
      return None
    return mvp_pb2.CheckInvitationResponse.Result(
      inviter=row['inviter'],
      recipient=row['recipient'],
    )

  def accept_invitation(self, nonce: str, now: datetime.datetime) -> Optional[mvp_pb2.CheckInvitationResponse.Result]:
    check_resp = self.check_invitation(nonce)
    if check_resp is None:
      return None
    self.set_trusted(Username(check_resp.recipient), Username(check_resp.inviter), True, now=now)
    self._conn.execute(
      sqlalchemy.delete(schema.email_invitations)
      .where(schema.email_invitations.c.nonce == nonce)
    )
    return check_resp

  def delete_invitation(self, inviter: Username, recipient: Username) -> None:
    self._conn.execute(
      sqlalchemy.delete(schema.email_invitations)
      .where(sqlalchemy.and_(
        schema.email_invitations.c.inviter == inviter,
        schema.email_invitations.c.recipient == recipient,
      ))
    )

  def is_invitation_outstanding(self, inviter: Username, recipient: Username) -> bool:
    return self._conn.execute(
      sqlalchemy.select([1])
      .where(sqlalchemy.and_(
        schema.email_invitations.c.inviter == inviter,
        schema.email_invitations.c.recipient == recipient,
      ))
    ).fetchone() is not None

  ResolutionReminderInfo = TypedDict('ResolutionReminderInfo', {'prediction_id': PredictionId,
                                                                'prediction_text': str,
                                                                'email_address': str})
  def get_predictions_needing_resolution_reminders(self, now: datetime.datetime) -> Iterable[ResolutionReminderInfo]:
    latest_time_per_prediction_q = sqlalchemy.select([
      schema.resolutions.c.prediction_id,
      sqlalchemy.sql.func.max(schema.resolutions.c.resolved_at_unixtime).label('resolved_at_unixtime'),
    ]).group_by(
      schema.resolutions.c.prediction_id,
    )
    latest_time_per_prediction_q = latest_time_per_prediction_q.subquery()  # type: ignore # https://github.com/dropbox/sqlalchemy-stubs/pull/218

    resolved_prediction_ids_q = sqlalchemy.select([
      schema.resolutions.c.prediction_id,
    ]).select_from(schema.resolutions.join(
      latest_time_per_prediction_q,
      onclause=sqlalchemy.and_(
        latest_time_per_prediction_q.c.prediction_id == schema.resolutions.c.prediction_id,
        latest_time_per_prediction_q.c.resolved_at_unixtime == schema.resolutions.c.resolved_at_unixtime,
        schema.resolutions.c.resolution != 'RESOLUTION_NONE_YET'
      ),
    ))
    resolved_prediction_ids_q = resolved_prediction_ids_q.subquery()  # type: ignore # https://github.com/dropbox/sqlalchemy-stubs/pull/218

    rows = self._conn.execute(
      sqlalchemy.select([
        schema.predictions.c.prediction_id,
        schema.predictions.c.prediction,
        schema.users.c.email_address,
      ])
      .where(sqlalchemy.and_(
        schema.predictions.c.resolves_at_unixtime < now.timestamp(),
        sqlalchemy.not_(schema.predictions.c.resolution_reminder_sent),
        schema.predictions.c.creator == schema.users.c.username,
        sqlalchemy.not_(schema.predictions.c.prediction_id.in_(sqlalchemy.select(resolved_prediction_ids_q.c)))
      ))
    ).fetchall()

    for row in rows:
      yield {
        'prediction_id': PredictionId(str(row['prediction_id'])),
        'prediction_text': str(row['prediction']),
        'email_address': str(row['email_address']),
      }

  def mark_resolution_reminder_sent(self, prediction_id: PredictionId) -> None:
    self._conn.execute(
      sqlalchemy.update(schema.predictions)
      .values(resolution_reminder_sent=True)
      .where(schema.predictions.c.prediction_id == prediction_id)
    )


def transactional(f):
  @functools.wraps(f)
  def wrapped(self: 'SqlServicer', *args, **kwargs):
    with self._conn.transaction():
      return f(self, *args, **kwargs)
  return wrapped
def log_actor(f):
  @functools.wraps(f)
  def wrapped(self: 'SqlServicer', actor: Optional[AuthorizingUsername], *args, **kwargs):
    structlog.contextvars.bind_contextvars(actor=actor)
    try:
      return f(self, actor, *args, **kwargs)
    finally:
      structlog.contextvars.unbind_contextvars('actor')
  return wrapped
def ensure_actor_exists(f):
  @functools.wraps(f)
  def wrapped(self: 'SqlServicer', actor: Optional[AuthorizingUsername], *args, **kwargs):
    if (actor is not None) and not self._conn.user_exists(actor):
      raise ForgottenTokenError(actor)
    return f(self, actor, *args, **kwargs)
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
    def __init__(self, conn: SqlConn, token_mint: TokenMint, emailer: Emailer, random_seed: Optional[int] = None, clock: Callable[[], datetime.datetime] = datetime.datetime.now) -> None:
        self._conn = conn
        self._token_mint = token_mint
        self._emailer = emailer
        self._rng = random.Random(random_seed)
        self._clock = clock

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def Whoami(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.WhoamiRequest) -> mvp_pb2.WhoamiResponse:
        return mvp_pb2.WhoamiResponse(username=actor if (actor is not None) else '')

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def SignOut(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.SignOutRequest) -> mvp_pb2.SignOutResponse:
        if actor is not None:
            # self._token_mint.revoke_token(actor)
            pass # TODO(P3): figure out how token-revoking should work; is it enough for the browser to just forget the cookie?
        return mvp_pb2.SignOutResponse()

    @transactional
    @log_actor
    @log_action
    def SendVerificationEmail(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.SendVerificationEmailRequest) -> mvp_pb2.SendVerificationEmailResponse:
      logger.debug('API call', email_address=request.email_address)
      if actor is not None:
        logger.warn('logged-in user trying to send a verification email', email_address=request.email_address)
        return mvp_pb2.SendVerificationEmailResponse(error=mvp_pb2.SendVerificationEmailResponse.Error(catchall='already authenticated; first, log out'))

      if self._conn.email_is_registered(request.email_address):
        logger.info('email is already registered', email_address=request.email_address)
        return mvp_pb2.SendVerificationEmailResponse(error=mvp_pb2.SendVerificationEmailResponse.Error(catchall='email is already registered'))

      logger.info('sending verification email', email_address=request.email_address)
      asyncio.create_task(self._emailer.send_email_verification(
        to=request.email_address,
        proof_of_email=self._token_mint.sign_proof_of_email(email_address=request.email_address),
      ))

      return mvp_pb2.SendVerificationEmailResponse(ok=mvp_pb2.VOID)

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def RegisterUsername(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.RegisterUsernameRequest) -> mvp_pb2.RegisterUsernameResponse:
      logger.debug('API call', username=request.username)
      if actor is not None:
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

      if self._conn.user_exists(Username(request.username)):
        logger.info('username taken', username=request.username)
        return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall='username taken'))

      email_address = self._token_mint.check_proof_of_email(request.proof_of_email)
      if email_address is None:
        logger.warn('invalid HMAC for proof-of-email', request=request)
        return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall='invalid signature'))
      logger.info('registering username', username=request.username)
      password_id = ''.join(self._rng.choices('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234567879_', k=16))
      self._conn.register_username(
        username=Username(request.username),
        email_address=email_address,
        password=request.password,
        password_id=password_id,
      )

      login_response = self.LogInUsername(None, mvp_pb2.LogInUsernameRequest(username=request.username, password=request.password))
      if login_response.WhichOneof('log_in_username_result') != 'ok':
        logging.error('unable to log in as freshly-created user', username=request.username, response=login_response)
        return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall='somehow failed to log you into your fresh account'))
      return mvp_pb2.RegisterUsernameResponse(ok=login_response.ok)

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def LogInUsername(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.LogInUsernameRequest) -> mvp_pb2.LogInUsernameResponse:
        if actor is not None:
            logger.warn('logged-in user trying to log in again', new_username=request.username)
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='already authenticated; first, log out'))

        hashed_password = self._conn.get_username_password_info(Username(request.username))
        if hashed_password is None:
            logger.debug('login attempt for nonexistent user', username=request.username)
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='no such user; maybe you want to sign up?'))
        if not check_password(request.password, hashed_password):
            logger.info('login attempt has bad password', possible_malice=True)
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='bad password'))

        logger.debug('username logged in', username=request.username)
        token = self._token_mint.mint_token(owner=Username(request.username), ttl_seconds=60*60*24*365)
        return mvp_pb2.LogInUsernameResponse(ok=mvp_pb2.AuthSuccess(
          token=token,
          user_info=self._conn.get_settings(AuthorizingUsername(Username(request.username))),
        ))

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def CreatePrediction(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.CreatePredictionRequest) -> mvp_pb2.CreatePredictionResponse:
      logger.debug('API call', request=request)
      if actor is None:
        logger.warn('not logged in')
        return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall='must log in to create predictions'))

      now = self._clock()

      problems = describe_CreatePredictionRequest_problems(request, now=now.timestamp())
      if problems is not None:
        return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall=problems))

      prediction_id = PredictionId(str(self._rng.randrange(2**64)))
      logger.debug('creating prediction', prediction_id=prediction_id, request=request)
      self._conn.create_prediction(
        now=now,
        prediction_id=prediction_id,
        creator=actor,
        request=request,
      )
      return mvp_pb2.CreatePredictionResponse(new_prediction_id=prediction_id)

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def GetPrediction(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.GetPredictionRequest) -> mvp_pb2.GetPredictionResponse:
      view = self._conn.view_prediction(actor, PredictionId(request.prediction_id))
      if view is None:
        logger.info('trying to get nonexistent prediction', prediction_id=request.prediction_id)
        return mvp_pb2.GetPredictionResponse(error=mvp_pb2.GetPredictionResponse.Error(catchall='no such prediction'))
      return mvp_pb2.GetPredictionResponse(prediction=view)


    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def ListMyStakes(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.ListMyStakesRequest) -> mvp_pb2.ListMyStakesResponse:
      if actor is None:
        logger.info('logged-out user trying to list their predictions')
        return mvp_pb2.ListMyStakesResponse(ok=mvp_pb2.PredictionsById(predictions={}))

      prediction_ids = self._conn.list_stakes(actor)

      predictions_by_id: MutableMapping[str, mvp_pb2.UserPredictionView] = {}
      for prediction_id in prediction_ids:
        view = self._conn.view_prediction(actor, prediction_id)
        assert view is not None
        predictions_by_id[prediction_id] = view
      return mvp_pb2.ListMyStakesResponse(ok=mvp_pb2.PredictionsById(predictions=predictions_by_id))

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def ListPredictions(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.ListPredictionsRequest) -> mvp_pb2.ListPredictionsResponse:
      creator = Username(request.creator)

      prediction_ids = self._conn.list_predictions_created(
        creator=creator,
        privacies=mvp_pb2.PredictionViewPrivacy.values() if actor == request.creator else {mvp_pb2.PREDICTION_VIEW_PRIVACY_ANYBODY},
      )

      predictions_by_id: MutableMapping[str, mvp_pb2.UserPredictionView] = {}
      for prediction_id in prediction_ids:
        view = self._conn.view_prediction(actor, prediction_id)
        assert view is not None
        predictions_by_id[prediction_id] = view
      return mvp_pb2.ListPredictionsResponse(ok=mvp_pb2.PredictionsById(predictions=predictions_by_id))

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def Stake(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.StakeRequest) -> mvp_pb2.StakeResponse:
      logger.debug('API call', request=request)
      if actor is None:
        logger.warn('not logged in')
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='must log in to bet'))
      assert request.bettor_stake_cents >= 0, 'protobuf should enforce this being a uint, but just in case...'

      if request.bettor_stake_cents == 0:
        logger.warn('trying to stake 0 cents', prediction_id=request.prediction_id)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='betting 0 cents doesn\'t make sense'))

      predinfo = self._conn.get_prediction_info(PredictionId(request.prediction_id))
      if predinfo is None:
        logger.warn('trying to bet on nonexistent prediction', prediction_id=request.prediction_id)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='no such prediction'))
      if predinfo['creator'] == actor:
        logger.warn('trying to bet against self', prediction_id=request.prediction_id)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="can't bet against yourself"))
      if not self._conn.trusts(actor, Username(predinfo['creator'])):
        logger.warn('trying to bet against untrusted creator', prediction_id=request.prediction_id)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="you don't trust the creator"))
      now = self._clock()
      if not (predinfo['created_at_unixtime'] <= now.timestamp() <= predinfo['closes_at_unixtime']):
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="prediction is no longer open for betting"))

      resolution = self._conn.get_resolution(PredictionId(request.prediction_id))
      if resolution and resolution.resolution != mvp_pb2.RESOLUTION_NONE_YET:
        logger.warn('trying to bet on a resolved prediction', prediction_id=request.prediction_id)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="prediction has already resolved"))

      if request.bettor_is_a_skeptic:
        lowP = predinfo['certainty_low_p']
        creator_stake_cents = int(request.bettor_stake_cents * lowP/(1-lowP))
      else:
        highP = predinfo['certainty_high_p']
        creator_stake_cents = int(request.bettor_stake_cents * (1-highP)/highP)

      if creator_stake_cents == 0:
        logger.warn('trying to make a bet that results in the creator staking 0 cents', prediction_id=request.prediction_id, request=request)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='creator would bet 0 cents against you'))

      existing_creator_exposure = self._conn.get_creator_exposure_cents(PredictionId(request.prediction_id), against_skeptics=request.bettor_is_a_skeptic)
      if existing_creator_exposure + creator_stake_cents > predinfo['maximum_stake_cents']:
          logger.warn('trying to make a bet that would exceed creator tolerance', request=request)
          return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall=f'bet would exceed creator tolerance ({existing_creator_exposure} existing + {creator_stake_cents} new stake > {predinfo["maximum_stake_cents"]} max)'))

      existing_bettor_exposure = self._conn.get_bettor_exposure_cents(PredictionId(request.prediction_id), actor, bettor_is_a_skeptic=request.bettor_is_a_skeptic)
      if existing_bettor_exposure + request.bettor_stake_cents > MAX_LEGAL_STAKE_CENTS:
        logger.warn('trying to make a bet that would exceed per-market stake limit', request=request)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall=f'your existing stake of ~${existing_bettor_exposure//100} plus your new stake of ~${request.bettor_stake_cents//100} would put you over the limit of ${MAX_LEGAL_STAKE_CENTS//100} staked in a single prediction; sorry, I hate to be paternalistic, but this site is not yet ready for Big Bets.'))

      self._conn.stake(
        prediction_id=PredictionId(request.prediction_id),
        bettor=actor,
        bettor_is_a_skeptic=request.bettor_is_a_skeptic,
        bettor_stake_cents=request.bettor_stake_cents,
        creator_stake_cents=creator_stake_cents,
        state = (
          mvp_pb2.TRADE_STATE_ACTIVE if self._conn.trusts(Username(predinfo['creator']), actor) else
          mvp_pb2.TRADE_STATE_QUEUED
        ),
        now=now,
      )
      logger.info('trade executed', prediction_id=request.prediction_id, request=request)
      return mvp_pb2.StakeResponse(ok=self._conn.view_prediction(actor, PredictionId(request.prediction_id)))

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def Follow(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.FollowRequest) -> mvp_pb2.FollowResponse:
      logger.debug('API call', request=request)
      if actor is None:
        logger.warn('not logged in')
        return mvp_pb2.FollowResponse(error=mvp_pb2.FollowResponse.Error(catchall='must log in to follow'))

      predinfo = self._conn.get_prediction_info(PredictionId(request.prediction_id))
      if predinfo is None:
        logger.warn('trying to follow nonexistent prediction', prediction_id=request.prediction_id)
        return mvp_pb2.FollowResponse(error=mvp_pb2.FollowResponse.Error(catchall='no such prediction'))

      self._conn.set_following(
        prediction_id=PredictionId(request.prediction_id),
        follower=actor,
        follow=request.follow,
      )
      logger.info('trade executed', prediction_id=request.prediction_id, request=request)
      return mvp_pb2.FollowResponse(ok=self._conn.view_prediction(actor, PredictionId(request.prediction_id)))

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def Resolve(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.ResolveRequest) -> mvp_pb2.ResolveResponse:
      logger.debug('API call', request=request)
      if actor is None:
        logger.warn('not logged in')
        return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='must log in to resolve a prediction'))
      if request.resolution not in {mvp_pb2.RESOLUTION_YES, mvp_pb2.RESOLUTION_NO, mvp_pb2.RESOLUTION_INVALID, mvp_pb2.RESOLUTION_NONE_YET}:
        logger.warn('user sent unrecognized resolution', resolution=request.resolution)
        return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='unrecognized resolution'))
      if len(request.notes) > 1024:
        logger.warn('unreasonably long notes', snipped_notes=request.notes[:256] + '  <snip>  ' + request.notes[-256:])
        return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='unreasonably long notes'))

      predid = PredictionId(request.prediction_id)
      predinfo = self._conn.get_prediction_info(predid)
      if predinfo is None:
        logger.info('attempt to resolve nonexistent prediction', prediction_id=request.prediction_id)
        return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='no such prediction'))
      if actor != predinfo['creator']:
        logger.warn('non-creator trying to resolve prediction', prediction_id=request.prediction_id, creator=predinfo['creator'], possible_malice=True)
        return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall="you are not the creator"))
      self._conn.resolve(request, now=self._clock())

      email_addrs = set(self._conn.get_resolution_notification_addrs(predid))
      if email_addrs:
        logger.info('sending resolution emails', prediction_id=request.prediction_id, email_addrs=email_addrs)
        asyncio.create_task(self._emailer.send_resolution_notifications(
            bccs=email_addrs,
            prediction_id=predid,
            prediction_text=predinfo['prediction'],
            resolution=request.resolution,
        ))
      return mvp_pb2.ResolveResponse(ok=self._conn.view_prediction(actor, predid))

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def SetTrusted(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.SetTrustedRequest) -> mvp_pb2.SetTrustedResponse:
      logger.debug('API call', request=request)
      if actor is None:
        logger.warn('not logged in')
        return mvp_pb2.SetTrustedResponse(error=mvp_pb2.SetTrustedResponse.Error(catchall='must log in to trust folks'))

      if request.who == actor:
        logger.warn('attempting to set trust for self')
        return mvp_pb2.SetTrustedResponse(error=mvp_pb2.SetTrustedResponse.Error(catchall='cannot set trust for self'))

      if not self._conn.user_exists(Username(request.who)):
        logger.warn('attempting to set trust for nonexistent user')
        return mvp_pb2.SetTrustedResponse(error=mvp_pb2.SetTrustedResponse.Error(catchall='no such user'))

      self._conn.set_trusted(actor, Username(request.who), request.trusted, now=self._clock())
      if not request.trusted:
        self._conn.delete_invitation(inviter=actor, recipient=Username(request.who))

      return mvp_pb2.SetTrustedResponse(ok=self._conn.get_settings(actor))

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def GetUser(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.GetUserRequest) -> mvp_pb2.GetUserResponse:
      if not self._conn.user_exists(Username(request.who)):
        logger.info('attempting to view nonexistent user', who=request.who)
        return mvp_pb2.GetUserResponse(error=mvp_pb2.GetUserResponse.Error(catchall='no such user'))

      return mvp_pb2.GetUserResponse(ok=mvp_pb2.Relationship(
        trusted_by_you=self._conn.trusts(actor, Username(request.who)) if (actor is not None) else False,
        trusts_you=self._conn.trusts(Username(request.who), actor) if (actor is not None) else False,
      ))

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def ChangePassword(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.ChangePasswordRequest) -> mvp_pb2.ChangePasswordResponse:
      logger.debug('API call')
      if actor is None:
        logger.warn('not logged in')
        return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall='must log in to change your password'))
      password_problems = describe_password_problems(request.new_password)
      if password_problems is not None:
        logger.warn('attempting to set bad password')
        return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall=password_problems))

      old_hashed_password = self._conn.get_username_password_info(actor)
      if old_hashed_password is None:
        logger.warn('password-change request for non-password user', possible_malice=True)
        return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall="you don't use a password to log in"))

      if not check_password(request.old_password, old_hashed_password):
        logger.warn('password-change request has wrong password', possible_malice=True)
        return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall='wrong old password'))

      logger.info('changing password', who=actor)
      self._conn.change_password(actor, request.new_password)

      return mvp_pb2.ChangePasswordResponse(ok=mvp_pb2.VOID)

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def GetSettings(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.GetSettingsRequest) -> mvp_pb2.GetSettingsResponse:
      if actor is None:
        logger.info('not logged in')
        return mvp_pb2.GetSettingsResponse(error=mvp_pb2.GetSettingsResponse.Error(catchall='must log in to see your settings'))

      info = self._conn.get_settings(actor, include_relationships_with_users=[Username(u) for u in request.include_relationships_with_users])
      if info is None:
        raise ForgottenTokenError(actor)
      return mvp_pb2.GetSettingsResponse(ok=info)

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def SendInvitation(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.SendInvitationRequest) -> mvp_pb2.SendInvitationResponse:
      logger.debug('API call', request=request)
      if actor is None:
        logger.warn('not logged in')
        return mvp_pb2.SendInvitationResponse(error=mvp_pb2.SendInvitationResponse.Error(catchall='must log in to create an invitation'))

      inviter_email = self._conn.get_email(actor)
      assert inviter_email is not None  # the user _must_ exist: they authenticated successfully!

      recipient = Username(request.recipient)
      recipient_settings = self._conn.get_settings(AuthorizingUsername(recipient))
      if recipient_settings is None:
        logger.warn('trying to send email invitation to nonexistent user')
        return mvp_pb2.SendInvitationResponse(error=mvp_pb2.SendInvitationResponse.Error(catchall='recipient user does not exist'))

      if self._conn.is_invitation_outstanding(inviter=actor, recipient=recipient):
        logger.warn('trying to send duplicate email invitation', request=request)
        return mvp_pb2.SendInvitationResponse(error=mvp_pb2.SendInvitationResponse.Error(catchall="I've already asked this user if they trust you"))

      self._conn.set_trusted(actor, recipient, True, now=self._clock())

      nonce = secrets.token_urlsafe(16)

      self._conn.create_invitation(
        nonce=nonce,
        inviter=actor,
        recipient=recipient,
      )
      asyncio.create_task(self._emailer.send_invitation(
        inviter_username=actor,
        inviter_email=inviter_email,
        recipient_username=recipient,
        recipient_email=recipient_settings.email_address,
        nonce=nonce,
      ))
      return mvp_pb2.SendInvitationResponse(ok=self._conn.get_settings(actor, include_relationships_with_users=[recipient]))

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def CheckInvitation(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.CheckInvitationRequest) -> mvp_pb2.CheckInvitationResponse:
      result = self._conn.check_invitation(
        nonce=request.nonce,
      )
      if result is None:
        logger.warn('asking about nonexistent (or completed) invitation')
        return mvp_pb2.CheckInvitationResponse(error=mvp_pb2.CheckInvitationResponse.Error(catchall='no such invitation'))
      return mvp_pb2.CheckInvitationResponse(ok=result)

    @transactional
    @ensure_actor_exists
    @log_actor
    @log_action
    def AcceptInvitation(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.AcceptInvitationRequest) -> mvp_pb2.AcceptInvitationResponse:
      logger.debug('API call', request=request)  # okay to log the nonce because it's one-time-use
      result = self._conn.accept_invitation(
        nonce=request.nonce,
        now=self._clock(),
      )
      if result is None:
        logger.warn('trying to accept nonexistent (or completed) invitation')
        return mvp_pb2.AcceptInvitationResponse(error=mvp_pb2.AcceptInvitationResponse.Error(catchall='no such invitation'))
      inviter_email = self._conn.get_email(Username(result.inviter))
      assert inviter_email is not None  # inviter must have existed in order to issue the invitation
      asyncio.create_task(self._emailer.send_invitation_acceptance_notification(
        inviter_email=inviter_email,
        recipient_username=Username(result.recipient),
      ))
      return mvp_pb2.AcceptInvitationResponse(ok=mvp_pb2.GenericUserInfo() if (actor is None) else self._conn.get_settings(actor))



def find_invariant_violations(conn: sqlalchemy.engine.base.Connection) -> Sequence[Mapping[str, Any]]:
  violations: MutableSequence[Mapping[str, Any]] = []
  overstaked_rows = conn.execute(
    sqlalchemy.select([
      schema.trades.c.prediction_id,
      schema.trades.c.bettor_is_a_skeptic,
      schema.predictions.c.maximum_stake_cents,
      sqlalchemy.sql.func.sum(schema.trades.c.creator_stake_cents).label('exposure'),
    ])
    .select_from(
      schema.trades.join(
        schema.predictions,
        onclause=(schema.trades.c.prediction_id == schema.predictions.c.prediction_id),
      )
    )
    .where(
      schema.trades.c.state == mvp_pb2.TradeState.Name(mvp_pb2.TRADE_STATE_ACTIVE),
    )
    .group_by(
      schema.trades.c.prediction_id,
      schema.trades.c.bettor_is_a_skeptic,
    )
  )
  for row in overstaked_rows:
    if row['exposure'] > row['maximum_stake_cents']:
      violations.append({
        'type':'exposure exceeded',
        'prediction_id': row['prediction_id'],
        'maximum_stake_cents': row['maximum_stake_cents'],
        'actual_exposure': row['exposure'],
      })
  return violations


###################################################################################
## Below this line are email-related very-nice-to-haves (TODO(P1)) that are hard to port from the Protobuf world.

def _backup_text(conn: sqlalchemy.engine.Connection) -> str:
  return json.dumps(
    {
      table.name: [dict(row) for row in conn.execute(sqlalchemy.select(table.c))]
      for table in schema.metadata.tables.values()
    },
    indent=2,
    sort_keys=True,
    default=lambda x: {'__type__': str(type(x)), '__repr__': repr(x)},
  )

async def email_daily_backups(
  conn: sqlalchemy.engine.Connection,
  emailer: Emailer,
  recipient_email: str,
  now: datetime.datetime,
):
  logger.info('emailing backups')
  await emailer.send_backup(
    to=recipient_email,
    now=now,
    body=_backup_text(conn),
  )


async def forever(
  interval: datetime.timedelta,
  f: Callable[[datetime.datetime], Awaitable[Any]],
) -> NoReturn:
  interval_secs = interval.total_seconds()
  while True:
    cycle_start_time = time.time()

    await f(datetime.datetime.now())

    next_cycle_time = cycle_start_time + interval_secs
    time_to_next_cycle = next_cycle_time - time.time()
    if time_to_next_cycle < interval_secs / 2:
        logger.warn('sending resolution-reminders took dangerously long', interval_secs=interval_secs, time_remaining=time.time() - cycle_start_time)
    await asyncio.sleep(time_to_next_cycle)

async def email_resolution_reminders(
  conn: SqlConn,
  emailer: Emailer,
  now: datetime.datetime,
):
  logger.info('sending email resolution reminders')
  for info in conn.get_predictions_needing_resolution_reminders(now):
    await emailer.send_resolution_reminder(
        to=info['email_address'],
        prediction_id=info['prediction_id'],
        prediction_text=info['prediction_text'],
    )
    conn.mark_resolution_reminder_sent(info['prediction_id'])

async def email_invariant_violations(
  conn: sqlalchemy.engine.Connection,
  emailer: Emailer,
  recipient_email: str,
  now: datetime.datetime,
):
  logger.info('seeking invariant violations')
  violations = find_invariant_violations(conn)
  if violations:
    logger.warn('found violations', violations=violations)
    await emailer.send_invariant_violations(
      to=recipient_email,
      now=now,
      violations=violations,
    )
