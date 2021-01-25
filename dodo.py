from pathlib import Path
import re

def task_proto():
  protos = list(Path('protobuf').glob('**/*.proto'))
  return {
    'file_dep': protos,
    'targets': [Path('elm/protobuf/Biatob/Proto')/re.sub(r'(?:^|_)([a-z])', lambda m: m.group(1).upper(), p.with_suffix('').name) for p in protos],
    'actions': ['mkdir -p elm/protobuf', 'protoc --elm_out=elm/protobuf ' + ' '.join(str(p) for p in protos)]
  }

def task_elm():
  src = Path('elm/src')
  dist = Path('elm/dist')
  modules = [p.with_suffix('').name for p in src.glob('*.elm') if '\nmain =' in p.read_text()]
  return {
    'file_dep': ['elm/elm.json', *src.glob('**/*.elm')],
    'targets': [dist/f'{mod}.js' for mod in modules],
    'actions': [f'mkdir -p {dist}'] +
               [f'cd elm && elm make src/{mod}.elm --output=dist/{mod}.js' for mod in modules],
  }
