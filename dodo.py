from pathlib import Path
import re
import subprocess

def has_executable(executable: str) -> bool:
  return subprocess.call(['which', executable], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0

def task_proto():
  protos = list(Path('protobuf').glob('**/*.proto'))
  snake_to_camel = lambda s: re.sub(r'(?:^|_)([a-z])', lambda m: m.group(1).upper(), s)

  yield {
    'name': 'python',
    'file_dep': protos,
    'targets':
      ['server/protobuf/__init__.py']
      + [Path('server/protobuf/')/(p.with_suffix('').name+'_pb2.py') for p in protos]
      ,
    'actions': [
      'mkdir -p server/protobuf',
      'touch server/protobuf/__init__.py',
      f'protoc --python_out=server {" ".join(str(p) for p in protos)}',
    ],
  }

  has_protoc_gen_for = lambda lang: has_executable(f'protoc-gen-{lang}')

  if has_protoc_gen_for('elm'):
    elm_protodir = Path('elm/protobuf')
    yield {
      'name': 'elm',
      'file_dep': protos,
      'targets': [(elm_protodir/'Biatob/Proto')/snake_to_camel(p.with_suffix('.elm').name) for p in protos],
      'actions': [
        f'if test -d {elm_protodir}; then rm -r {elm_protodir}; fi',
        f'mkdir -p {elm_protodir}',
        f'protoc --elm_out={elm_protodir} {" ".join(str(p) for p in protos)}',
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
  modules = [p.with_suffix('').name for p in (src/'Elements').glob('**/*.elm')]
  return {
    'file_dep': [
      'elm/elm.json',
      *src.glob('**/*.elm'),
      *[t for d in task_proto() for t in d['targets'] if d['name']=='elm'],
    ],
    'targets': [
      *[dist/f'{mod}.js' for mod in modules],
    ],
    'actions': [
      f'if test -d {dist}; then rm -r {dist}; fi',
      f'mkdir -p {dist}',
      *[f'cd elm && elm make {src.relative_to("elm")}/Elements/{mod}.elm --output=dist/{mod}.js' for mod in modules]
    ],
  }

def task_test():
  yield {
    'name': 'mypy',
    'file_dep': [*Path('server').glob('**/*.py'), *Path('server').glob('**/*.pyi')],
    'actions': [
      # 'pip3 install -r server/requirements.txt',
      'mypy server',
    ]
  }
  yield {
    'name': 'elm',
    'file_dep': [
      'elm/elm.json',
      *Path('elm/src').glob('**/*.elm'),
      *[t for d in task_proto() for t in d['targets'] if d['name']=='elm'],
      *Path('elm/tests').glob('**/*.elm'),
    ],
    'actions': [
      'cd elm && elm-test',
    ]
  }
  yield {
    'name': 'pytest',
    'setup': ['elm'],
    'file_dep': [
      *Path('server').glob('**/*.py'),
      *Path('server').glob('**/*.pyi'),
      *[p for p in Path('server/templates').glob('**/*') if p.is_file()],
    ],
    'params': [
      {'name': 'test_filter',
       'short': 'k',
       'default': '',
       'help': f'only run tests with this substring'},
    ],
    'actions': [
      # 'pip3 install -r server/requirements.txt',
      'pytest --color=yes -k=%(test_filter)s',
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


def task_devsetup():
  import sys
  def print_instructions():
    print("[to edit the server] Install Python dependencies: `pip install -r server/requirements.txt -r server/requirements.txt`", file=sys.stderr)
    if not has_executable('elm'):
      print("[to edit the UI] Install Elm: https://github.com/elm/compiler/blob/master/installers/linux/README.md", file=sys.stderr)
    if not has_executable('elm-test'):
      print("[to edit the UI] Install `elm-test`: https://elmprogramming.com/easy-to-test.html", file=sys.stderr)
    if not has_executable('protoc'):
      print("[to edit the UI] Install protoc: https://github.com/elm/compiler/blob/master/installers/linux/README.md", file=sys.stderr)
    if not has_executable('protoc-gen-elm'):
      print("[to edit the UI] Install protoc-gen-elm: `npm install protoc-gen-elm` (and ensure it's on your path)", file=sys.stderr)
    if not has_executable('protoc-gen-mypy'):
      print("[to edit the UI] Install protoc-gen-mypy: `pip install mypy-protobuf`", file=sys.stderr)

  return {
    'actions': [(print_instructions,)],
  }

def pprint_state(state_path: str):
  if not state_path:
    raise ValueError('state_path must be given to pprint')
  from server.protobuf.mvp_pb2 import WorldState
  ws = WorldState()
  ws.ParseFromString(open(state_path, 'rb').read())
  print(ws)

def task_pprint():
  def ensure_state_path_given(state_path):
    if not state_path:
      raise RuntimeError('--state_path must be given')
  return {
    'setup': ['proto:python'],
    'params': [
      {'name': 'state_path',
       'short': 'p',
       'long': 'state_path',
       'default': '',
       'help': f'path to state file to pprint'},
    ],
    'actions': [pprint_state],
    'verbosity': 2,
  }

def task_nfsdeploy():
  def ensure_nfsuser_given(nfsuser):
    if not nfsuser:
      raise RuntimeError('--nfsuser must be given')
  return {
    'setup': ['elm', 'proto', 'test'],
    'params': [
      {'name': 'nfsuser',
       'long': 'nfsuser',
       'default': '',
       'help': f'NearlyFreeSpeech username'},
    ],
    'actions': [
      (ensure_nfsuser_given,),
      'rsync -havz --exclude=venv --exclude=".*" --exclude="_*" --exclude="*~" --exclude=server.WorldState.pb ./ %(nfsuser)s_biatob@ssh.phx.nearlyfreespeech.net:/home/protected/src/',
      'echo "Sorry, I don\'t know how to kick your server! You gotta yourself." >&2',
    ],
  }


DOIT_CONFIG = {
  'default_tasks': list(
    {name[5:] for name, obj in locals().items() if name.startswith('task_') and callable(obj)}
    - {'nfsdeploy', 'devsetup', 'pprint'}
  ),
}
