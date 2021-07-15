from .sql_schema import *

def test_smoke():
  engine = create_engine(mvp_pb2.DatabaseInfo(sqlite=':memory:'))
  with engine.connect() as conn:
    conn.execute(sqlalchemy.select(users.c)).fetchall()
