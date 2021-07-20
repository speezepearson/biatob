"""add column for who can view a prediction

Revision ID: 235b772150a8
Revises: 0f322d5fec41
Create Date: 2021-07-19 22:42:30.451922

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '235b772150a8'
down_revision = '0f322d5fec41'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('predictions', sa.Column('view_privacy', sa.String(length=96), server_default='PREDICTION_VIEW_PRIVACY_ANYBODY', nullable=False))


def downgrade():
    op.drop_column('predictions', 'view_privacy')
