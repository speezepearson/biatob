from pathlib import Path
import re
import subprocess

def task_proto():
  protos = list(Path('protobuf').glob('**/*.proto'))
  snake_to_camel = lambda s: re.sub(r'(?:^|_)([a-z])', lambda m: m.group(1).upper(), s)

  yield {
    'name': 'python',
    'file_dep': protos,
    'targets':
      ['server/protobuf/__init__.py']
      + [Path('server/protobuf/')/(p.with_suffix('').name+'_pb2.py')  for p in protos]
      ,
    'actions': [
      'mkdir -p server/protobuf',
      'touch server/protobuf/__init__.py',
      f'protoc --python_out=server {" ".join(str(p) for p in protos)}',
    ],
  }

  has_protoc_gen_for = lambda lang: not subprocess.call(['which', f'protoc-gen-{lang}'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

  if has_protoc_gen_for('elm'):
    yield {
      'name': 'elm',
      'file_dep': protos,
      'targets': [Path('elm/protobuf/Biatob/Proto')/snake_to_camel(p.with_suffix('.elm').name) for p in protos],
      'actions': [
        'mkdir -p elm/protobuf',
        f'protoc --elm_out=elm/protobuf {" ".join(str(p) for p in protos)}',
      ],
    }
  else:
    print('WARNING: protoc-gen-elm not found, not generating elm protos')

  if has_protoc_gen_for('mypy'):
    yield {
      'name': 'mypy',
      'file_dep': protos,
      'targets': [Path('server/protobuf/')/(p.with_suffix('').name+'_pb2.pyi') for p in protos],
      'actions': [
        'mkdir -p server/protobuf',
        'touch server/protobuf/__init__.py',
        f'protoc --mypy_out=server {" ".join(str(p) for p in protos)}',
      ],
    }
  else:
    print('WARNING: protoc-gen-mypy not found, not generating mypy protos')


def task_elm():
  src = Path('elm/src')
  dist = Path('elm/dist')
  modules = [p.with_suffix('').name for p in src.glob('*.elm') if '\nmain =' in p.read_text()]
  return {
    'file_dep': ['elm/elm.json', *src.glob('**/*.elm')],
    'targets': [
      *[dist/f'{mod}.js' for mod in modules],
      *[dist/f'{mod}.html' for mod in modules],
    ],
    'actions': [f'mkdir -p {dist}']
               + [f'cd elm && elm make src/{mod}.elm --output=dist/{mod}.js' for mod in modules]
               + [f'cd elm && elm make src/{mod}.elm && mv index.html dist/{mod}.html' for mod in modules]
               ,
  }

def task_test():
  yield {
    'name': 'python',
    'file_dep': list(Path('server').glob('**/*.py')),
    'actions': [
      'pip3 install -r server/requirements.txt',
      'mypy server',
      'cd server && pytest',
    ]
  }

def task_userstories():
  src = Path('mockup/user-stories.markdown')
  dst = src.with_suffix('.html')
  return {
    'file_dep': [src],
    'targets': [dst],
    'actions': [f'pandoc -s {src} -o {dst}'],
  }
