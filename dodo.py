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
    'file_dep': ['elm/elm.json', *src.glob('**/*.elm'), *[t for d in task_proto() for t in d['targets'] if d['name']=='elm']],
    'targets': [
      *[dist/f'{mod}.js' for mod in modules],
    ],
    'actions': [f'mkdir -p {dist}']
               + [f'cd elm && elm make src/{mod}.elm --output=dist/{mod}.js' for mod in modules]
               ,
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
    'name': 'pytest',
    'file_dep': [*Path('server').glob('**/*.py'), *Path('server').glob('**/*.pyi')],
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
    print("[to edit the server] Install Python dependencies: `pip install -r server/requirements.txt`", file=sys.stderr)
    if not has_executable('elm'):
      print("[to edit the UI] Install Elm: https://github.com/elm/compiler/blob/master/installers/linux/README.md", file=sys.stderr)
    if not has_executable('protoc'):
      print("[to edit the UI] Install protoc: https://github.com/elm/compiler/blob/master/installers/linux/README.md", file=sys.stderr)
    if not has_executable('protoc-gen-elm'):
      print("[to edit the UI] Install protoc-gen-elm: `npm install protoc-gen-elm` (and ensure it's on your path)", file=sys.stderr)
    if not has_executable('protoc-gen-mypy'):
      print("[to edit the UI] Install protoc-gen-mypy: `pip install mypy-protobuf`", file=sys.stderr)

  return {
    'actions': [(print_instructions,)],
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
      'rsync -havz --exclude=".*" --exclude="_*" --exclude="*~" --exclude=server.WorldState.pb ./ %(nfsuser)s_biatob@ssh.phx.nearlyfreespeech.net:/home/protected/',
      'echo "Sorry, I don\'t know how to kick your server! You gotta yourself." >&2',
    ],
  }


DOIT_CONFIG = {
  'default_tasks': list(
    {name[5:] for name, obj in locals().items() if name.startswith('task_') and callable(obj)}
    - {'nfsdeploy', 'devsetup'}
  ),
}
