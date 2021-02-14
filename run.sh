#!/bin/bash
# This file assumes that:
# - you've rsynced biatob into /home/protected/ on a NearlyFreeSpeech server, probably using `doit nfsdeploy --nfsuser=MYNFSUSER`;
# - that's where this file is;
# - it's being run by a NearlyFreeSpeech daemon, with cwd /home/protected/
# - you've configured a proxy on your instance to redirect / to :8080/

set -e

echo '########################################'
date -Iseconds

if [ ! -d venv ]; then
  python3 -m venv ./venv
  ./venv/bin/pip install -r server/requirements.txt
fi
source ./venv/bin/activate

python -m server.server --host=0.0.0.0 --port=8080 --state-path=/home/protected/server.WorldState.pb