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

  def register_username(self, username: Username, password: str, password_id: str) -> None:
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
        login_password_id=password_id,
        email_flow_state=mvp_pb2.EmailFlowState(unstarted=mvp_pb2.VOID).SerializeToString(),
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
      special_rules=request.special_rules,
      creator=creator,
    ))

  def user_exists(self, user: Username) -> bool:
    return self._conn.execute(sqlalchemy.select(schema.users.c).where(schema.users.c.username == user)).first() is not None

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
    allow_email_invitations = (
      creator_settings_row['allow_email_invitations'] and
      mvp_pb2.EmailFlowState.FromString(creator_settings_row['email_flow_state']).WhichOneof('email_flow_state_kind') == 'verified'
    )

    resolution_rows = self._conn.execute(
      sqlalchemy.select(schema.resolutions.c)
      .where(schema.resolutions.c.prediction_id == prediction_id)
      .order_by(schema.resolutions.c.resolved_at_unixtime)
    ).fetchall()

    trade_rows = self._conn.execute(
      sqlalchemy.select(schema.trades.c)
      .where(sqlalchemy.and_(
        schema.trades.c.prediction_id == prediction_id,
        True if creator_is_viewer else (schema.trades.c.bettor == viewer)
      ))
      .order_by(schema.trades.c.transacted_at_unixtime)
    ).fetchall()

    queued_trade_rows = self._conn.execute(
      sqlalchemy.select(schema.queued_trades.c)
      .where(sqlalchemy.and_(
        schema.queued_trades.c.prediction_id == prediction_id,
        True if creator_is_viewer else (schema.queued_trades.c.bettor == viewer)
      ))
      .order_by(schema.queued_trades.c.enqueued_at_unixtime)
    ).fetchall()

    remaining_stake_cents_vs_believers = row['maximum_stake_cents'] - self._conn.execute(
      sqlalchemy.select([sqlalchemy.sql.func.coalesce(sqlalchemy.sql.func.sum(schema.trades.c.creator_stake_cents), 0)])
      .where(sqlalchemy.and_(
        schema.trades.c.prediction_id == prediction_id,
        sqlalchemy.not_(schema.trades.c.bettor_is_a_skeptic)
      ))
    ).scalar()
    remaining_stake_cents_vs_skeptics = row['maximum_stake_cents'] - self._conn.execute(
      sqlalchemy.select([sqlalchemy.sql.func.coalesce(sqlalchemy.sql.func.sum(schema.trades.c.creator_stake_cents), 0)])
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
      creator=row['creator'],
      allow_email_invitations=allow_email_invitations,
      resolutions=[
        mvp_pb2.ResolutionEvent(
          unixtime=r['resolved_at_unixtime'],
          resolution=mvp_pb2.Resolution.Value(r['resolution']),
          notes=r['notes'],
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
      your_queued_trades=[
        mvp_pb2.QueuedTrade(
          bettor=t['bettor'],
          bettor_is_a_skeptic=t['bettor_is_a_skeptic'],
          creator_stake_cents=t['creator_stake_cents'],
          bettor_stake_cents=t['bettor_stake_cents'],
          enqueued_at_unixtime=t['enqueued_at_unixtime'],
        )
        for t in queued_trade_rows
      ],
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
          .where(schema.trades.c.bettor == user)
        ).fetchall()],
    }

  def list_predictions_created(self, creator: Username) -> Iterable[PredictionId]:
    return {
      PredictionId(row['prediction_id'])
      for row in self._conn.execute(
        sqlalchemy.select([schema.predictions.c.prediction_id])
        .where(schema.predictions.c.creator == creator)
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

  def get_trades(
    self,
    prediction_id: PredictionId,
  ) -> Iterable[mvp_pb2.Trade]:
    rows = self._conn.execute(
      sqlalchemy.select(schema.trades.c)
      .where(schema.trades.c.prediction_id == prediction_id)
    ).fetchall()
    return [
      mvp_pb2.Trade(
        bettor=row['bettor'],
        bettor_is_a_skeptic=row['bettor_is_a_skeptic'],
        bettor_stake_cents=row['bettor_stake_cents'],
        creator_stake_cents=row['creator_stake_cents'],
        transacted_unixtime=row['transacted_at_unixtime'],
      )
      for row in rows
    ]

  QueuedTradeInfo = TypedDict('QueuedTradeInfo', {'prediction_id': PredictionId,
                                                  'bettor': Username,
                                                  'bettor_is_a_skeptic': bool,
                                                  'bettor_stake_cents': int,
                                                  'creator_stake_cents': int,
                                                  'enqueued_at_unixtime': float})
  def get_queued_trades(self, bettor: Username, creator: Username) -> Iterable[QueuedTradeInfo]:
    return [
      {'prediction_id': PredictionId(str(row['prediction_id'])),
       'bettor': Username(str(row['bettor'])),
       'bettor_is_a_skeptic': bool(row['bettor_is_a_skeptic']),
       'bettor_stake_cents': int(row['bettor_stake_cents']),
       'creator_stake_cents': int(row['creator_stake_cents']),
       'enqueued_at_unixtime': float(row['enqueued_at_unixtime']),
       }
      for row in self._conn.execute(
        sqlalchemy.select(schema.queued_trades.c)
          .where(sqlalchemy.and_(
            schema.queued_trades.c.bettor == bettor,
            schema.queued_trades.c.prediction_id == schema.predictions.c.prediction_id,
            schema.predictions.c.creator == creator,
          ))
      )
    ]

  def commit_queued_trade(self, prediction_id: PredictionId, bettor: Username, enqueued_at_unixtime: float) -> None:
    row = self._conn.execute(
      sqlalchemy.select(schema.queued_trades.c)
      .where(sqlalchemy.and_(
        schema.queued_trades.c.prediction_id == prediction_id,
        schema.queued_trades.c.bettor == bettor,
        schema.queued_trades.c.enqueued_at_unixtime == enqueued_at_unixtime,
      ))
    ).fetchone()
    self._conn.execute(
      sqlalchemy.insert(schema.trades)
      .values(
        prediction_id=prediction_id,
        bettor=bettor,
        bettor_is_a_skeptic=row['bettor_is_a_skeptic'],
        bettor_stake_cents=row['bettor_stake_cents'],
        creator_stake_cents=row['creator_stake_cents'],
        transacted_at_unixtime=enqueued_at_unixtime,
      )
    )
    self.delete_queued_trade(prediction_id=prediction_id, bettor=bettor, enqueued_at_unixtime=enqueued_at_unixtime)

  def delete_queued_trade(self, prediction_id: PredictionId, bettor: Username, enqueued_at_unixtime: float) -> None:
    self._conn.execute(
      sqlalchemy.delete(schema.queued_trades)
      .where(sqlalchemy.and_(
        schema.queued_trades.c.prediction_id == prediction_id,
        schema.queued_trades.c.bettor == bettor,
        schema.queued_trades.c.enqueued_at_unixtime == enqueued_at_unixtime,
      ))
    )

  def get_resolutions(
    self,
    prediction_id: PredictionId,
  ) -> Iterable[mvp_pb2.ResolutionEvent]:
    rows = self._conn.execute(
      sqlalchemy.select(schema.resolutions.c)
      .where(schema.resolutions.c.prediction_id == prediction_id)
    ).fetchall()
    return [
      mvp_pb2.ResolutionEvent(
        unixtime=row['resolved_at_unixtime'],
        resolution=mvp_pb2.Resolution.Value(row['resolution']),
        notes=row['notes'],
      )
      for row in rows
    ]

  def get_creator_exposure_cents(
    self,
    prediction_id: PredictionId,
    against_skeptics: bool,
  ) -> int:
    return self._conn.execute(
      sqlalchemy.select([
        sqlalchemy.sql.func.sum(schema.trades.c.creator_stake_cents).label('exposure'),
      ])
      .select_from(schema.predictions.join(schema.trades))
      .where(sqlalchemy.and_(
        schema.predictions.c.prediction_id == prediction_id,
        schema.trades.c.bettor_is_a_skeptic if against_skeptics else sqlalchemy.not_(schema.trades.c.bettor_is_a_skeptic),
      ))
    ).scalar() or 0

  def get_bettor_exposure_cents(
    self,
    prediction_id: PredictionId,
    bettor: Username,
    bettor_is_a_skeptic: bool
  ) -> int:
    return self._conn.execute(
      sqlalchemy.select([
        sqlalchemy.sql.func.sum(schema.trades.c.bettor_stake_cents).label('exposure'),
      ])
      .select_from(schema.predictions.join(schema.trades))
      .where(sqlalchemy.and_(
        schema.trades.c.bettor == bettor,
        schema.predictions.c.prediction_id == prediction_id,
        schema.trades.c.bettor_is_a_skeptic if bettor_is_a_skeptic else sqlalchemy.not_(schema.trades.c.bettor_is_a_skeptic),
      ))
    ).scalar() or 0

  def stake(
    self,
    prediction_id: PredictionId,
    bettor: Username,
    bettor_is_a_skeptic: bool,
    bettor_stake_cents: int,
    creator_stake_cents: int,
    now: datetime.datetime,
  ) -> None:
    self._conn.execute(sqlalchemy.insert(schema.trades).values(
      prediction_id=prediction_id,
      bettor=bettor,
      bettor_is_a_skeptic=bettor_is_a_skeptic,
      bettor_stake_cents=bettor_stake_cents,
      creator_stake_cents=creator_stake_cents,
      transacted_at_unixtime=now.timestamp(),
    ))

  def queue_stake(
    self,
    prediction_id: PredictionId,
    bettor: Username,
    bettor_is_a_skeptic: bool,
    bettor_stake_cents: int,
    creator_stake_cents: int,
    now: datetime.datetime,
  ) -> None:
    self._conn.execute(sqlalchemy.insert(schema.queued_trades).values(
      prediction_id=prediction_id,
      bettor=bettor,
      bettor_is_a_skeptic=bettor_is_a_skeptic,
      bettor_stake_cents=bettor_stake_cents,
      creator_stake_cents=creator_stake_cents,
      enqueued_at_unixtime=now.timestamp(),
    ))

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

  def set_trusted(self, subject_username: Username, object_username: Username, trusted: bool) -> None:
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
      self._dequeue_trades_between(subject_username, object_username)

  def _dequeue_trades_between(self, user_1: Username, user_2: Username) -> None:
    queued_trades = [
      *self.get_queued_trades(bettor=user_1, creator=user_2),
      *self.get_queued_trades(bettor=user_2, creator=user_1),
    ]
    predinfos_ = {predid: self.get_prediction_info(predid) for predid in {qt['prediction_id'] for qt in queued_trades}}
    predinfos = {predid: predinfo for predid, predinfo in predinfos_.items() if predinfo}
    if predinfos != predinfos_:
      logger.error('queued trades reference nonexistent predictions', missing_predids={predid for predid, predinfo in predinfos_ if predinfo is None})

    for qt in queued_trades:
      predinfo = predinfos[qt['prediction_id']]

      existing_creator_exposure = self.get_creator_exposure_cents(PredictionId(qt['prediction_id']), against_skeptics=qt['bettor_is_a_skeptic'])
      existing_bettor_exposure = self.get_bettor_exposure_cents(PredictionId(qt['prediction_id']), qt['bettor'], bettor_is_a_skeptic=qt['bettor_is_a_skeptic'])
      if (existing_creator_exposure + qt['creator_stake_cents'] > predinfo['maximum_stake_cents']):
        logger.warn('failed to dequeue a bet that would exceed creator tolerance', queued_trade=qt, predinfo=predinfo)
        self.delete_queued_trade(
          prediction_id=PredictionId(qt['prediction_id']),
          bettor=qt['bettor'],
          enqueued_at_unixtime=qt['enqueued_at_unixtime'],
        )
      elif existing_bettor_exposure + qt['bettor_stake_cents'] > MAX_LEGAL_STAKE_CENTS:
        logger.warn('failed to dequeue a bet that would exceed per-market stake limit', queued_trade=qt, predinfo=predinfo)
        self.delete_queued_trade(
          prediction_id=PredictionId(qt['prediction_id']),
          bettor=qt['bettor'],
          enqueued_at_unixtime=qt['enqueued_at_unixtime'],
        )
      else:
        self.commit_queued_trade(
          prediction_id=PredictionId(qt['prediction_id']),
          bettor=qt['bettor'],
          enqueued_at_unixtime=qt['enqueued_at_unixtime']
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

  def set_email(self, user: Username, new_efs: mvp_pb2.EmailFlowState) -> None:
    self._conn.execute(
      sqlalchemy.update(schema.users)
      .values(email_flow_state=new_efs.SerializeToString())
      .where(schema.users.c.username == user)
    )

  def get_email(self, user: Username) -> Optional[mvp_pb2.EmailFlowState]:
    old_efs_binary = self._conn.execute(
      sqlalchemy.select([schema.users.c.email_flow_state])
      .where(schema.users.c.username == user)
    ).scalar()
    if old_efs_binary is None:
      return None
    return mvp_pb2.EmailFlowState.FromString(old_efs_binary)

  def get_resolution_notification_addrs(self, prediction_id: PredictionId) -> Iterable[str]:
    result = set()
    bettor_efs_rows = self._conn.execute(
      sqlalchemy.select([schema.users.c.email_flow_state])
      .where(sqlalchemy.and_(
        schema.trades.c.prediction_id == prediction_id,
        schema.trades.c.bettor == schema.users.c.username,
        schema.users.c.email_resolution_notifications,
      ))
    ).fetchall()
    for row in bettor_efs_rows:
      bettor_efs = mvp_pb2.EmailFlowState.FromString(row['email_flow_state'])
      if bettor_efs.WhichOneof('email_flow_state_kind') == 'verified':
        result.add(bettor_efs.verified)

    return result

  def get_settings(self, user: Username, include_relationships_with_users: Iterable[Username] = ()) -> Optional[mvp_pb2.GenericUserInfo]:
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
      email_reminders_to_resolve=row['email_reminders_to_resolve'],
      email_resolution_notifications=row['email_resolution_notifications'],
      allow_email_invitations=row['allow_email_invitations'],
      email_invitation_acceptance_notifications=row['email_invitation_acceptance_notifications'],
      email=mvp_pb2.EmailFlowState.FromString(row['email_flow_state']),
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

  def update_settings(self, user: Username, request: mvp_pb2.UpdateSettingsRequest) -> None:
    update_kwargs = {}
    if request.HasField('email_reminders_to_resolve'):
      update_kwargs['email_reminders_to_resolve'] = request.email_reminders_to_resolve.value
    if request.HasField('email_resolution_notifications'):
      update_kwargs['email_resolution_notifications'] = request.email_resolution_notifications.value
    if request.HasField('allow_email_invitations'):
      update_kwargs['allow_email_invitations'] = request.allow_email_invitations.value
    if request.HasField('email_invitation_acceptance_notifications'):
      update_kwargs['email_invitation_acceptance_notifications'] = request.email_invitation_acceptance_notifications.value

    if update_kwargs:
      self._conn.execute(
        sqlalchemy.update(schema.users)
        .values(**update_kwargs)
        .where(schema.users.c.username == user)
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

  def accept_invitation(self, nonce: str) -> Optional[mvp_pb2.CheckInvitationResponse.Result]:
    check_resp = self.check_invitation(nonce)
    if check_resp is None:
      return None
    self.set_trusted(Username(check_resp.recipient), Username(check_resp.inviter), True)
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
        schema.users.c.email_flow_state,
      ])
      .where(sqlalchemy.and_(
        schema.predictions.c.resolves_at_unixtime < now.timestamp(),
        sqlalchemy.not_(schema.predictions.c.resolution_reminder_sent),
        schema.predictions.c.creator == schema.users.c.username,
        schema.users.c.email_reminders_to_resolve,
        sqlalchemy.not_(schema.predictions.c.prediction_id.in_(sqlalchemy.select(resolved_prediction_ids_q.c)))
      ))
    ).fetchall()

    for row in rows:
      efs = mvp_pb2.EmailFlowState.FromString(row['email_flow_state'])
      if efs.WhichOneof('email_flow_state_kind') == 'verified':
        yield {
          'prediction_id': row['prediction_id'],
          'prediction_text': row['prediction'],
          'email_address': efs.verified,
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
def checks_token(f):
  @functools.wraps(f)
  def wrapped(self: 'SqlServicer', token: Optional[mvp_pb2.AuthToken], *args, **kwargs):
    token = self._token_mint.check_token(token)
    if (token is not None) and not self._conn.user_exists(token_owner(token)):
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
    def __init__(self, conn: SqlConn, token_mint: TokenMint, emailer: Emailer, random_seed: Optional[int] = None, clock: Callable[[], datetime.datetime] = datetime.datetime.now) -> None:
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

      if self._conn.user_exists(Username(request.username)):
        logger.info('username taken', username=request.username)
        return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall='username taken'))

      logger.info('registering username', username=request.username)
      password_id = ''.join(self._rng.choices('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234567879_', k=16))
      self._conn.register_username(Username(request.username), request.password, password_id=password_id)

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

        hashed_password = self._conn.get_username_password_info(Username(request.username))
        if hashed_password is None:
            logger.debug('login attempt for nonexistent user', username=request.username)
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='no such user'))
        if not check_password(request.password, hashed_password):
            logger.info('login attempt has bad password', possible_malice=True)
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='bad password'))

        logger.debug('username logged in', username=request.username)
        token = self._token_mint.mint_token(owner=Username(request.username), ttl_seconds=60*60*24*365)
        return mvp_pb2.LogInUsernameResponse(ok=mvp_pb2.AuthSuccess(
          token=token,
          user_info=self._conn.get_settings(token_owner(token)),
        ))

    @transactional
    @checks_token
    @log_action
    def CreatePrediction(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.CreatePredictionRequest) -> mvp_pb2.CreatePredictionResponse:
      if token is None:
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
        creator=token_owner(token),
        request=request,
      )
      return mvp_pb2.CreatePredictionResponse(new_prediction_id=prediction_id)

    @transactional
    @checks_token
    @log_action
    def GetPrediction(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetPredictionRequest) -> mvp_pb2.GetPredictionResponse:
      view = self._conn.view_prediction(token_owner(token), PredictionId(request.prediction_id))
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

      prediction_ids = self._conn.list_stakes(token_owner(token))

      predictions_by_id: MutableMapping[str, mvp_pb2.UserPredictionView] = {}
      for prediction_id in prediction_ids:
        view = self._conn.view_prediction(token_owner(token), prediction_id)
        assert view is not None
        predictions_by_id[prediction_id] = view
      return mvp_pb2.ListMyStakesResponse(ok=mvp_pb2.PredictionsById(predictions=predictions_by_id))

    @transactional
    @checks_token
    @log_action
    def ListPredictions(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ListPredictionsRequest) -> mvp_pb2.ListPredictionsResponse:
      if token is None:
        logger.info('logged-out user trying to list predictions')
        return mvp_pb2.ListPredictionsResponse(ok=mvp_pb2.PredictionsById(predictions={}))
      creator = Username(request.creator) if request.creator else token_owner(token)
      if not self._conn.trusts(creator, token_owner(token)):
        logger.info('trying to get list untrusting creator\'s predictions', creator=creator)
        return mvp_pb2.ListPredictionsResponse(error=mvp_pb2.ListPredictionsResponse.Error(catchall="creator doesn't trust you"))

      prediction_ids = self._conn.list_predictions_created(creator)

      predictions_by_id: MutableMapping[str, mvp_pb2.UserPredictionView] = {}
      for prediction_id in prediction_ids:
        view = self._conn.view_prediction(token_owner(token), prediction_id)
        assert view is not None
        predictions_by_id[prediction_id] = view
      return mvp_pb2.ListPredictionsResponse(ok=mvp_pb2.PredictionsById(predictions=predictions_by_id))

    @transactional
    @checks_token
    @log_action
    def Stake(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.StakeRequest) -> mvp_pb2.StakeResponse:
      if token is None:
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
      if predinfo['creator'] == token.owner:
        logger.warn('trying to bet against self', prediction_id=request.prediction_id)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="can't bet against yourself"))
      if not self._conn.trusts(Username(predinfo['creator']), token_owner(token)):
        logger.warn('trying to bet against untrusting creator', prediction_id=request.prediction_id, possible_malice=True)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="creator doesn't trust you"))
      if not self._conn.trusts(token_owner(token), Username(predinfo['creator'])):
        logger.warn('trying to bet against untrusted creator', prediction_id=request.prediction_id)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="you don't trust the creator"))
      now = self._clock()
      if not (predinfo['created_at_unixtime'] <= now.timestamp() <= predinfo['closes_at_unixtime']):
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="prediction is no longer open for betting"))

      resolutions = self._conn.get_resolutions(PredictionId(request.prediction_id))
      if resolutions and max(resolutions, key=lambda r: r.unixtime).resolution != mvp_pb2.RESOLUTION_NONE_YET:
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

      existing_bettor_exposure = self._conn.get_bettor_exposure_cents(PredictionId(request.prediction_id), token_owner(token), bettor_is_a_skeptic=request.bettor_is_a_skeptic)
      if existing_bettor_exposure + request.bettor_stake_cents > MAX_LEGAL_STAKE_CENTS:
        logger.warn('trying to make a bet that would exceed per-market stake limit', request=request)
        return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall=f'your existing stake of ~${existing_bettor_exposure//100} plus your new stake of ~${request.bettor_stake_cents//100} would put you over the limit of ${MAX_LEGAL_STAKE_CENTS//100} staked in a single prediction; sorry, I hate to be paternalistic, but this site is not yet ready for Big Bets.'))

      self._conn.stake(
        prediction_id=PredictionId(request.prediction_id),
        bettor=token_owner(token),
        bettor_is_a_skeptic=request.bettor_is_a_skeptic,
        bettor_stake_cents=request.bettor_stake_cents,
        creator_stake_cents=creator_stake_cents,
        now=now,
      )
      logger.info('trade executed', prediction_id=request.prediction_id, request=request)
      return mvp_pb2.StakeResponse(ok=self._conn.view_prediction(token_owner(token), PredictionId(request.prediction_id)))

    @transactional
    @checks_token
    @log_action
    def QueueStake(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.QueueStakeRequest) -> mvp_pb2.QueueStakeResponse:
      if token is None:
        logger.warn('not logged in')
        return mvp_pb2.QueueStakeResponse(error=mvp_pb2.QueueStakeResponse.Error(catchall='must log in to bet'))
      assert request.bettor_stake_cents >= 0, 'protobuf should enforce this being a uint, but just in case...'

      if request.bettor_stake_cents == 0:
        logger.warn('trying to stake 0 cents', prediction_id=request.prediction_id)
        return mvp_pb2.QueueStakeResponse(error=mvp_pb2.QueueStakeResponse.Error(catchall='betting 0 cents doesn\'t make sense'))

      predinfo = self._conn.get_prediction_info(PredictionId(request.prediction_id))
      if predinfo is None:
        logger.warn('trying to bet on nonexistent prediction', prediction_id=request.prediction_id)
        return mvp_pb2.QueueStakeResponse(error=mvp_pb2.QueueStakeResponse.Error(catchall='no such prediction'))
      if predinfo['creator'] == token.owner:
        logger.warn('trying to bet against self', prediction_id=request.prediction_id)
        return mvp_pb2.QueueStakeResponse(error=mvp_pb2.QueueStakeResponse.Error(catchall="can't bet against yourself"))
      if not self._conn.trusts(token_owner(token), Username(predinfo['creator'])):
        logger.warn('trying to bet against untrusted creator', prediction_id=request.prediction_id)
        return mvp_pb2.QueueStakeResponse(error=mvp_pb2.QueueStakeResponse.Error(catchall="you don't trust the creator"))
      now = self._clock()
      if not (predinfo['created_at_unixtime'] <= now.timestamp() <= predinfo['closes_at_unixtime']):
        return mvp_pb2.QueueStakeResponse(error=mvp_pb2.QueueStakeResponse.Error(catchall="prediction is no longer open for betting"))

      if self._conn.trusts(token_owner(token), Username(predinfo['creator'])) and self._conn.trusts(Username(predinfo['creator']), token_owner(token)):
        return mvp_pb2.QueueStakeResponse(error=mvp_pb2.QueueStakeResponse.Error(catchall="you already trust the creator, so you should be using the Stake endpoint, not QueueStake"))

      resolutions = self._conn.get_resolutions(PredictionId(request.prediction_id))
      if resolutions and max(resolutions, key=lambda r: r.unixtime).resolution != mvp_pb2.RESOLUTION_NONE_YET:
        logger.warn('trying to bet on a resolved prediction', prediction_id=request.prediction_id)
        return mvp_pb2.QueueStakeResponse(error=mvp_pb2.QueueStakeResponse.Error(catchall="prediction has already resolved"))

      if request.bettor_is_a_skeptic:
        lowP = predinfo['certainty_low_p']
        creator_stake_cents = int(request.bettor_stake_cents * lowP/(1-lowP))
      else:
        highP = predinfo['certainty_high_p']
        creator_stake_cents = int(request.bettor_stake_cents * (1-highP)/highP)

      if creator_stake_cents == 0:
        logger.warn('trying to make a bet that results in the creator staking 0 cents', prediction_id=request.prediction_id, request=request)
        return mvp_pb2.QueueStakeResponse(error=mvp_pb2.QueueStakeResponse.Error(catchall='creator would bet 0 cents against you'))

      existing_creator_exposure = self._conn.get_creator_exposure_cents(PredictionId(request.prediction_id), against_skeptics=request.bettor_is_a_skeptic)
      if existing_creator_exposure + creator_stake_cents > predinfo['maximum_stake_cents']:
          logger.warn('trying to make a bet that would exceed creator tolerance', request=request)
          return mvp_pb2.QueueStakeResponse(error=mvp_pb2.QueueStakeResponse.Error(catchall=f'bet would exceed creator tolerance ({existing_creator_exposure} existing + {creator_stake_cents} new stake > {predinfo["maximum_stake_cents"]} max)'))

      existing_bettor_exposure = self._conn.get_bettor_exposure_cents(PredictionId(request.prediction_id), token_owner(token), bettor_is_a_skeptic=request.bettor_is_a_skeptic)
      if existing_bettor_exposure + request.bettor_stake_cents > MAX_LEGAL_STAKE_CENTS:
        logger.warn('trying to make a bet that would exceed per-market stake limit', request=request)
        return mvp_pb2.QueueStakeResponse(error=mvp_pb2.QueueStakeResponse.Error(catchall=f'your existing stake of ~${existing_bettor_exposure//100} plus your new stake of ~${request.bettor_stake_cents//100} would put you over the limit of ${MAX_LEGAL_STAKE_CENTS//100} staked in a single prediction; sorry, I hate to be paternalistic, but this site is not yet ready for Big Bets.'))

      self._conn.queue_stake(
        prediction_id=PredictionId(request.prediction_id),
        bettor=token_owner(token),
        bettor_is_a_skeptic=request.bettor_is_a_skeptic,
        bettor_stake_cents=request.bettor_stake_cents,
        creator_stake_cents=creator_stake_cents,
        now=now,
      )
      logger.info('trade executed', prediction_id=request.prediction_id, request=request)
      return mvp_pb2.QueueStakeResponse(ok=self._conn.view_prediction(token_owner(token), PredictionId(request.prediction_id)))

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

      predid = PredictionId(request.prediction_id)
      predinfo = self._conn.get_prediction_info(predid)
      if predinfo is None:
        logger.info('attempt to resolve nonexistent prediction', prediction_id=request.prediction_id)
        return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='no such prediction'))
      if token_owner(token) != predinfo['creator']:
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
      return mvp_pb2.ResolveResponse(ok=self._conn.view_prediction(token_owner(token), predid))

    @transactional
    @checks_token
    @log_action
    def SetTrusted(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SetTrustedRequest) -> mvp_pb2.SetTrustedResponse:
      if token is None:
        logger.warn('not logged in')
        return mvp_pb2.SetTrustedResponse(error=mvp_pb2.SetTrustedResponse.Error(catchall='must log in to trust folks'))

      if request.who == token.owner:
        logger.warn('attempting to set trust for self')
        return mvp_pb2.SetTrustedResponse(error=mvp_pb2.SetTrustedResponse.Error(catchall='cannot set trust for self'))

      if not self._conn.user_exists(Username(request.who)):
        logger.warn('attempting to set trust for nonexistent user')
        return mvp_pb2.SetTrustedResponse(error=mvp_pb2.SetTrustedResponse.Error(catchall='no such user'))

      self._conn.set_trusted(token_owner(token), Username(request.who), request.trusted)
      if not request.trusted:
        self._conn.delete_invitation(inviter=token_owner(token), recipient=Username(request.who))

      return mvp_pb2.SetTrustedResponse(ok=self._conn.get_settings(token_owner(token)))

    @transactional
    @checks_token
    @log_action
    def GetUser(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetUserRequest) -> mvp_pb2.GetUserResponse:
      if not self._conn.user_exists(Username(request.who)):
        logger.info('attempting to view nonexistent user', who=request.who)
        return mvp_pb2.GetUserResponse(error=mvp_pb2.GetUserResponse.Error(catchall='no such user'))

      return mvp_pb2.GetUserResponse(ok=mvp_pb2.Relationship(
        trusted_by_you=self._conn.trusts(token_owner(token), Username(request.who)) if (token is not None) else False,
        trusts_you=self._conn.trusts(Username(request.who), token_owner(token)) if (token is not None) else False,
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

      old_hashed_password = self._conn.get_username_password_info(token_owner(token))
      if old_hashed_password is None:
        logger.warn('password-change request for non-password user', possible_malice=True)
        return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall="you don't use a password to log in"))

      if not check_password(request.old_password, old_hashed_password):
        logger.warn('password-change request has wrong password', possible_malice=True)
        return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall='wrong old password'))

      logger.info('changing password', who=token.owner)
      self._conn.change_password(token_owner(token), request.new_password)

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

      if request.email:
        # TODO: prevent an email address from getting "too many" emails if somebody abuses us
        code = secrets.token_urlsafe(nbytes=16)
        asyncio.create_task(self._emailer.send_email_verification(
            to=request.email,
            code=code,
        ))
        new_efs = mvp_pb2.EmailFlowState(code_sent=mvp_pb2.EmailFlowState.CodeSent(email=request.email, code=new_hashed_password(code)))
      else:
        new_efs = mvp_pb2.EmailFlowState(unstarted=mvp_pb2.VOID)

      logger.info('setting email address', who=token.owner, address=request.email)
      self._conn.set_email(token_owner(token), new_efs)
      return mvp_pb2.SetEmailResponse(ok=new_efs)

    @transactional
    @checks_token
    @log_action
    def VerifyEmail(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.VerifyEmailRequest) -> mvp_pb2.VerifyEmailResponse:
      if token is None:
        logger.warn('not logged in')
        return mvp_pb2.VerifyEmailResponse(error=mvp_pb2.VerifyEmailResponse.Error(catchall='must log in to verify your email address'))

      old_efs = self._conn.get_email(token_owner(token))
      if old_efs is None:
        raise ForgottenTokenError(token)

      if old_efs.WhichOneof('email_flow_state_kind') != 'code_sent':
        logger.warn('attempting to verify email, but no email outstanding', possible_malice=True)
        return mvp_pb2.VerifyEmailResponse(error=mvp_pb2.VerifyEmailResponse.Error(catchall='you have no pending email-verification flow'))
      code_sent_state = old_efs.code_sent
      if not check_password(request.code, code_sent_state.code):
        logger.warn('bad email-verification code', address=code_sent_state.email, possible_malice=True)
        return mvp_pb2.VerifyEmailResponse(error=mvp_pb2.VerifyEmailResponse.Error(catchall='bad code'))

      new_efs = mvp_pb2.EmailFlowState(verified=code_sent_state.email)
      self._conn.set_email(token_owner(token), new_efs)
      logger.info('verified email address', who=token.owner, address=code_sent_state.email)
      return mvp_pb2.VerifyEmailResponse(ok=new_efs)

    @transactional
    @checks_token
    @log_action
    def GetSettings(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetSettingsRequest) -> mvp_pb2.GetSettingsResponse:
      if token is None:
        logger.info('not logged in')
        return mvp_pb2.GetSettingsResponse(error=mvp_pb2.GetSettingsResponse.Error(catchall='must log in to see your settings'))

      info = self._conn.get_settings(token_owner(token), include_relationships_with_users=[Username(u) for u in request.include_relationships_with_users])
      if info is None:
        raise ForgottenTokenError(token)
      return mvp_pb2.GetSettingsResponse(ok=info)

    @transactional
    @checks_token
    @log_action
    def UpdateSettings(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.UpdateSettingsRequest) -> mvp_pb2.UpdateSettingsResponse:
      if token is None:
        logger.warn('not logged in')
        return mvp_pb2.UpdateSettingsResponse(error=mvp_pb2.UpdateSettingsResponse.Error(catchall='must log in to update your settings'))

      self._conn.update_settings(token_owner(token), request)
      logger.info('updated settings', request=request)
      return mvp_pb2.UpdateSettingsResponse(ok=self._conn.get_settings(token_owner(token)))

    @transactional
    @checks_token
    @log_action
    def SendInvitation(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SendInvitationRequest) -> mvp_pb2.SendInvitationResponse:
      if token is None:
        logger.warn('not logged in')
        return mvp_pb2.SendInvitationResponse(error=mvp_pb2.SendInvitationResponse.Error(catchall='must log in to create an invitation'))

      inviter_email = self._conn.get_email(token_owner(token))
      assert inviter_email is not None  # the user _must_ exist: we have a token for them!
      if inviter_email.WhichOneof('email_flow_state_kind') != 'verified':
        logger.warn('trying to send email invitation to user without email set')
        return mvp_pb2.SendInvitationResponse(error=mvp_pb2.SendInvitationResponse.Error(catchall='you need to add an email address before you can send invitations'))

      recipient = Username(request.recipient)
      recipient_settings = self._conn.get_settings(recipient)
      if recipient_settings is None:
        logger.warn('trying to send email invitation to nonexistent user')
        return mvp_pb2.SendInvitationResponse(error=mvp_pb2.SendInvitationResponse.Error(catchall='recipient user does not exist'))
      if not recipient_settings.allow_email_invitations:
        logger.warn('trying to send email invitation to user without allow_email_invitations set')
        return mvp_pb2.SendInvitationResponse(error=mvp_pb2.SendInvitationResponse.Error(catchall='recipient user does not accept email invitations'))
      if recipient_settings.email.WhichOneof('email_flow_state_kind') != 'verified':
        logger.warn('trying to send email invitation to user without email set')
        return mvp_pb2.SendInvitationResponse(error=mvp_pb2.SendInvitationResponse.Error(catchall='recipient user does not accept email invitations'))

      if self._conn.is_invitation_outstanding(inviter=token_owner(token), recipient=recipient):
        logger.warn('trying to send duplicate email invitation', request=request)
        return mvp_pb2.SendInvitationResponse(error=mvp_pb2.SendInvitationResponse.Error(catchall="I've already asked this user if they trust you"))

      self._conn.set_trusted(token_owner(token), recipient, True)

      nonce = secrets.token_urlsafe(16)

      self._conn.create_invitation(
        nonce=nonce,
        inviter=token_owner(token),
        recipient=recipient,
      )
      asyncio.create_task(self._emailer.send_invitation(
        inviter_username=token_owner(token),
        inviter_email=inviter_email.verified,
        recipient_username=recipient,
        recipient_email=recipient_settings.email.verified,
        nonce=nonce,
      ))
      return mvp_pb2.SendInvitationResponse(ok=self._conn.get_settings(token_owner(token), include_relationships_with_users=[recipient]))

    @transactional
    @checks_token
    @log_action
    def CheckInvitation(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.CheckInvitationRequest) -> mvp_pb2.CheckInvitationResponse:
      result = self._conn.check_invitation(
        nonce=request.nonce,
      )
      if result is None:
        logger.warn('asking about nonexistent (or completed) invitation')
        return mvp_pb2.CheckInvitationResponse(error=mvp_pb2.CheckInvitationResponse.Error(catchall='no such invitation'))
      return mvp_pb2.CheckInvitationResponse(ok=result)

    @transactional
    @checks_token
    @log_action
    def AcceptInvitation(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.AcceptInvitationRequest) -> mvp_pb2.AcceptInvitationResponse:
      result = self._conn.accept_invitation(
        nonce=request.nonce,
      )
      if result is None:
        logger.warn('trying to accept nonexistent (or completed) invitation')
        return mvp_pb2.AcceptInvitationResponse(error=mvp_pb2.AcceptInvitationResponse.Error(catchall='no such invitation'))
      inviter_settings = self._conn.get_settings(Username(result.inviter))
      if inviter_settings and inviter_settings.email_invitation_acceptance_notifications and inviter_settings.email.WhichOneof('email_flow_state_kind') == 'verified':
        asyncio.create_task(self._emailer.send_invitation_acceptance_notification(
          inviter_email=inviter_settings.email.verified,
          recipient_username=Username(result.recipient),
        ))
      return mvp_pb2.AcceptInvitationResponse(ok=mvp_pb2.GenericUserInfo() if token is None else self._conn.get_settings(token_owner(token)))



def find_invariant_violations(conn: sqlalchemy.engine.base.Connection) -> Sequence[Mapping[str, Any]]:
  violations: MutableSequence[Mapping[str, Any]] = []
  overstaked_rows = conn.execute(
    sqlalchemy.select([
      schema.trades.c.prediction_id,
      schema.trades.c.bettor_is_a_skeptic,
      schema.predictions.c.maximum_stake_cents,
      sqlalchemy.sql.func.sum(schema.trades.c.creator_stake_cents).label('exposure'),
    ])
    .select_from(schema.trades.join(
      schema.predictions,
      onclause=(schema.trades.c.prediction_id == schema.predictions.c.prediction_id),
    ))
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
