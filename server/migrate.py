import argparse
import copy
from pathlib import Path
from typing import Callable, Iterator, Mapping, Sequence, Tuple

from google.protobuf.message import Message

from .protobuf.mvp_pb2 import WorldState, GenericUserInfo, Relationship, GenericUserInfo
from .server import FsStorage, walk

def change_uint32_times_to_doubles(obj: object) -> None:
  if not isinstance(obj, Message):
    return
  for desc, value in obj.ListFields():
    if desc.type == desc.TYPE_UINT32 and 'unixtime' in desc.name and desc.name.endswith('_depr'):
      new_fieldname = desc.name[:-5]
      setattr(obj, new_fieldname, value)

def move_resolution_reminder_history_into_predictions(obj: object) -> None:
  if not isinstance(obj, WorldState):
    return
  for prediction in obj.predictions.values():
    if prediction.resolves_at_unixtime < obj.email_reminders_sent_up_to_unixtime_depr and not prediction.HasField('resolution_reminder_history'):
      prediction.resolution_reminder_history.skipped = True

def trusted_users_to_relationships(obj: object) -> None:
  if not isinstance(obj, GenericUserInfo):
    return
  for uid in obj.trusted_users_depr:
    assert uid.WhichOneof('kind') == 'username'
    if uid.username not in obj.relationships:
      obj.relationships[uid.username].CopyFrom(Relationship(trusted=True))

def userids_to_usernames(obj: object) -> None:
  if not isinstance(obj, Message):
    return

  if isinstance(obj, WorldState):
    for username, info in obj.username_users_depr.items():
      obj.user_settings[username].CopyFrom(info.info)
      obj.user_settings[username].login_password.CopyFrom(info.password)
    obj.ClearField('username_users_depr')

  for desc, value in obj.ListFields():
    if desc.name == 'trusted_users_depr':
      continue # already migrated to Relationships based on username
    if desc.type == desc.TYPE_MESSAGE and desc.message_type.name=='UserId' and desc.name.endswith('_depr'):
      new_fieldname = desc.name[:-5]
      if desc.label == desc.LABEL_REPEATED:
        assert all(v.WhichOneof('kind') == 'username' for v in value)
        setattr(obj, new_fieldname, [v.username for v in value])
        obj.ClearField(desc.name)
      else:
        assert value.WhichOneof('kind') == 'username'
        setattr(obj, new_fieldname, value.username)
        obj.ClearField(desc.name)


MIGRATIONS: Sequence[Callable[[object], None]] = [
  change_uint32_times_to_doubles,
  move_resolution_reminder_history_into_predictions,
  trusted_users_to_relationships,
  userids_to_usernames,
]

parser = argparse.ArgumentParser()
parser.add_argument('state_path', type=Path)

def main(args):

  storage = FsStorage(args.state_path)

  with storage.mutate() as ws:

    for migrate in MIGRATIONS:
      for value in walk(ws):
        migrate(value)
      postmigration = copy.deepcopy(ws)
      for value in walk(ws):
        migrate(value)
      assert ws == postmigration, "migrations must be idempotent!"

if __name__ == '__main__':
  main(parser.parse_args())
