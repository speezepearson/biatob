from .sql_schema import *

def test_smoke():
  engine = create_sqlite_engine(':memory:')
  with engine.connect() as conn:
    conn.execute(sqlalchemy.select(users.c)).fetchall()
