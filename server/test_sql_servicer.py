import sqlalchemy

from .sql_servicer import find_invariant_violations
from . import sql_schema as schema

def test_find_invariant_violations():
  engine = sqlalchemy.create_engine('sqlite+pysqlite:///:memory:')
  schema.metadata.create_all(engine)
  with engine.connect() as conn:
    assert find_invariant_violations(conn) == []

    conn.execute(sqlalchemy.insert(schema.predictions).values(
      prediction_id=1,
      prediction='a',
      certainty_low_p=0.4,
      certainty_high_p=0.6,
      maximum_stake_cents=100,
      created_at_unixtime=1,
      closes_at_unixtime=3,
      resolves_at_unixtime=4,
      special_rules='',
      creator='creator',
    ))
    assert find_invariant_violations(conn) == []

    conn.execute(sqlalchemy.insert(schema.trades).values(prediction_id=1, bettor='bettor', transacted_at_unixtime=2, bettor_stake_cents=120, creator_stake_cents=200, bettor_is_a_skeptic=False))
    assert find_invariant_violations(conn) == [{'type': 'exposure exceeded', 'prediction_id': 1, 'actual_exposure': 200, 'maximum_stake_cents': 100}]