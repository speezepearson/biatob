from pathlib import Path
import re

def task_proto():
  protos = list(Path('protobuf').glob('**/*.proto'))
  camelcase_names = [
    re.sub(r'(?:^|_)([a-z])',
           lambda m: m.group(1).upper(),
           p.with_suffix('').name)
    for p in protos
  ]
  return {
    'file_dep': protos,
    'targets': [Path('elm/protobuf/Biatob/Proto')/(n+'.elm') for n in camelcase_names],
    'actions': ['mkdir -p elm/protobuf', 'protoc --elm_out=elm/protobuf --python_out=server/protobuf --mypy_out=mypy_proto_wat ' + ' '.join(str(p) for p in protos)]
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

def task_userstories():
  src = Path('mockup/user-stories.markdown')
  dst = src.with_suffix('.html')
  return {
    'file_dep': [src],
    'targets': [dst],
    'actions': [f'pandoc -s {src} -o {dst}'],
  }
