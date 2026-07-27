#! /bin/bash
# Reproduces the spike end-to-end. Needs python3 and npx (network access for
# pip/npm). Nothing here is wired into the real build; this dir is throwaway.
set -euo pipefail
cd "$(dirname "$0")"

WORK="${WORK:-$(mktemp -d)}"
echo "scratch dir: $WORK"

# 1. Pydantic models -> OpenAPI schema
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install -q pydantic fastapi httpx
"$WORK/venv/bin/python" gen_openapi.py

# 2. Real FastAPI responses -> sample_*.json (what Elm must decode)
"$WORK/venv/bin/python" - <<'PY'
from fastapi.testclient import TestClient
from app import app
import json, warnings; warnings.filterwarnings("ignore")
c = TestClient(app)
for name, pw in [("sample_ok", "hunter2"), ("sample_err", "wrong")]:
    r = c.post("/api/LogInUsername", json={"username": "spike", "password": pw}).json()
    open(f"{name}.json", "w").write(json.dumps(r, indent=2) + "\n")
PY

# 3. OpenAPI schema -> Elm
mkdir -p "$WORK/gen" && cd "$WORK/gen"
npm init -y >/dev/null 2>&1
npm install --no-fund --no-audit elm@0.19.1-6 elm-test@0.19.1-revision12 elm-open-api >/dev/null 2>&1
npm approve-scripts --allow-scripts-pending >/dev/null 2>&1 || true
npm rebuild elm >/dev/null 2>&1
cd - >/dev/null
cp openapi.json "$WORK/gen/"
(cd "$WORK/gen" && ./node_modules/.bin/elm-open-api openapi.json --output-dir generated --module-name Api)
rm -rf elm-check/src/Api elm-check/src/OpenApi
cp -r "$WORK/gen/generated/." elm-check/src/

# 4. Compile the generated Elm and decode the real JSON from step 2
cd elm-check
PATH="$WORK/gen/node_modules/.bin:$PATH" ELM_HOME="$WORK/elm-home" \
  elm-test --compiler "$WORK/gen/node_modules/.bin/elm"
