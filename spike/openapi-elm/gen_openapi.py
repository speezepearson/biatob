import json
from pathlib import Path

from app import app

schema = app.openapi()
Path(__file__).parent.joinpath("openapi.json").write_text(json.dumps(schema, indent=2) + "\n")
print("wrote openapi.json")
