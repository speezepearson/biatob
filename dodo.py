from pathlib import Path
import subprocess

def has_executable(executable: str) -> bool:
  return subprocess.call(['which', executable], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0

def task_genapi():
  """Regenerate the committed Elm API bindings (elm/generated/Api/*) from the
  OpenAPI schema that FastAPI derives from the api_types Pydantic models.

  This is the successor to the old protoc-gen-elm step. It needs `npx
  elm-open-api`, so it is not a default task -- run it explicitly (`doit
  genapi`) after changing api_types.py, then commit the regenerated files.
  """
  return {
    'actions': [
      'python -m server.openapi_spec > elm/generated/openapi.json',
      'cd elm && npx --yes elm-open-api generated/openapi.json --output-dir generated --module-name Api',
    ],
    'verbosity': 2,
  }


def task_elm():
  src = Path('elm/src')
  generated = Path('elm/generated')
  dist = Path('elm/dist')
  modules = [p.with_suffix('').name for p in (src/'Elements').glob('**/*.elm')]
  return {
    'file_dep': [
      'elm/elm.json',
      *src.glob('**/*.elm'),
      *generated.glob('**/*.elm'),
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
      *Path('elm/generated').glob('**/*.elm'),
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
    print("[to regenerate the Elm API bindings after changing server/api_types.py] "
          "`npx elm-open-api` is used by `doit genapi`; it runs via npx, no global install needed.", file=sys.stderr)

  return {
    'actions': [(print_instructions,)],
  }

def task_nfsdeploy():
  def ensure_nfsuser_given(nfsuser):
    if not nfsuser:
      raise RuntimeError('--nfsuser must be given')
  return {
    'setup': ['elm', 'test'],
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
    - {'nfsdeploy', 'devsetup', 'genapi'}
  ),
}
