import argparse
import copy
from pathlib import Path
from typing import Callable, Iterator, Mapping, Sequence, Tuple

from google.protobuf.message import Message

from .protobuf.mvp_pb2 import WorldState
from .server import FsStorage

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

def change_uint32_times_to_doubles(obj: object) -> None:
  if not isinstance(obj, Message):
    return
  for desc, value in obj.ListFields():
    if desc.type == desc.TYPE_UINT32 and desc.name.endswith('_depr'):
      new_fieldname = desc.name[:-5]
      setattr(obj, new_fieldname, value)

MIGRATIONS: Sequence[Callable[[object], None]] = [
  change_uint32_times_to_doubles
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