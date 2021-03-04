import argparse
import copy
from pathlib import Path
from typing import Callable, Iterator, Mapping, Sequence, Tuple

from google.protobuf.message import Message

from .protobuf.mvp_pb2 import WorldState, GenericUserInfo, Relationship
from .server import FsStorage, walk

def change_uint32_times_to_doubles(obj: object) -> None:
  if not isinstance(obj, Message):
    return
  for desc, value in obj.ListFields():
    if desc.type == desc.TYPE_UINT32 and desc.name.endswith('_depr'):
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

MIGRATIONS: Sequence[Callable[[object], None]] = [
  change_uint32_times_to_doubles,
  move_resolution_reminder_history_into_predictions,
  trusted_users_to_relationships,
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
