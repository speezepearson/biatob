"""init

Revision ID: 0f322d5fec41
Revises: 
Create Date: 2021-07-14 15:53:51.137246

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '0f322d5fec41'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():

    pwid_t = sa.String(64)
    username_t = sa.String(64)
    predid_t = sa.String(64)

    op.create_table(
        'passwords',
        sa.Column('password_id', pwid_t, primary_key=True, nullable=False),
        sa.Column('salt', sa.VARBINARY(255), nullable=False),
        sa.Column('scrypt', sa.VARBINARY(255), nullable=False),
    )

    op.create_table(
        'users',
        sa.Column('username', username_t, primary_key=True, nullable=False),
        sa.Column('email_reminders_to_resolve', sa.BOOLEAN(), nullable=False, server_default=sa.text('TRUE')),
        sa.Column('email_resolution_notifications', sa.BOOLEAN(), nullable=False, server_default=sa.text('TRUE')),
        sa.Column('allow_email_invitations', sa.BOOLEAN(), nullable=False, server_default=sa.text('TRUE')),
        sa.Column('email_invitation_acceptance_notifications', sa.BOOLEAN(), nullable=False, server_default=sa.text('TRUE')),
        sa.Column('login_password_id', pwid_t, sa.ForeignKey('passwords.password_id'), nullable=False),  # will be nullable someday, if we add OAuth or something
        sa.Column('email_flow_state', sa.BLOB(), nullable=False),
    )

    op.create_table(
        'relationships',
        sa.Column('subject_username', username_t, sa.ForeignKey('users.username'), primary_key=True, nullable=False),
        sa.Column('object_username', username_t, sa.ForeignKey('users.username'), primary_key=True, nullable=False),
        sa.Column('trusted', sa.BOOLEAN(), nullable=False, server_default=sa.text('FALSE')),
    )
    op.create_index('relationships_by_subject_username', 'relationships', ['subject_username'])
    op.create_index('relationships_by_object_username', 'relationships', ['object_username'])

    op.create_table(
        'predictions',
        sa.Column('prediction_id', predid_t, primary_key=True, nullable=False),
        sa.Column('prediction', sa.String(1024), sa.CheckConstraint('LENGTH(prediction) > 0'), nullable=False),
        sa.Column('certainty_low_p', sa.REAL(), sa.CheckConstraint('0 < certainty_low_p AND certainty_low_p < 1'), nullable=False),
        sa.Column('certainty_high_p', sa.REAL(), sa.CheckConstraint('certainty_low_p <= certainty_high_p AND certainty_high_p <= 1'), nullable=False),
        sa.Column('maximum_stake_cents', sa.Integer(), sa.CheckConstraint('maximum_stake_cents > 0'), nullable=False),
        sa.Column('created_at_unixtime', sa.REAL(), nullable=False),
        sa.Column('closes_at_unixtime', sa.REAL(), sa.CheckConstraint('closes_at_unixtime > created_at_unixtime'), nullable=False),
        sa.Column('resolves_at_unixtime', sa.REAL(), sa.CheckConstraint('resolves_at_unixtime > created_at_unixtime'), nullable=False),
        sa.Column('special_rules', sa.TEXT(), nullable=False),
        sa.Column('creator', username_t, sa.ForeignKey('users.username'), nullable=False),
        sa.Column('resolution_reminder_sent', sa.BOOLEAN(), nullable=False, server_default=sa.text('FALSE')),
    )

    op.create_table(
        'trades',
        sa.Column('prediction_id', predid_t, sa.ForeignKey('predictions.prediction_id'), primary_key=True, nullable=False),
        sa.Column('bettor', username_t, sa.ForeignKey('users.username'), primary_key=True, nullable=False),
        sa.Column('transacted_at_unixtime', sa.REAL(), primary_key=True, nullable=False),
        sa.Column('bettor_is_a_skeptic', sa.BOOLEAN(), nullable=False),
        sa.Column('bettor_stake_cents', sa.Integer(), sa.CheckConstraint('bettor_stake_cents > 0'), nullable=False),
        sa.Column('creator_stake_cents', sa.Integer(), sa.CheckConstraint('creator_stake_cents > 0'), nullable=False),
        sa.Column('state', sa.String(64), sa.CheckConstraint("state in ('TRADE_STATE_ACTIVE', 'TRADE_STATE_DEQUEUE_FAILED', 'TRADE_STATE_DISAVOWED', 'TRADE_STATE_QUEUED')"), nullable=False),
        sa.Column('updated_at_unixtime', sa.REAL(), nullable=False),
        sa.Column('notes', sa.TEXT(), nullable=False, server_default=sa.text("''")),
    )
    op.create_index('trades_by_prediction_id', 'trades', ['prediction_id'])
    op.create_index('trades_by_bettor', 'trades', ['bettor'])

    op.create_table(
        'resolutions',
        sa.Column('prediction_id', predid_t, sa.ForeignKey('predictions.prediction_id'), primary_key=True, nullable=False),
        sa.Column('resolved_at_unixtime', sa.REAL(), primary_key=True, nullable=False),
        sa.Column('resolution', sa.String(64), sa.CheckConstraint("resolution IN ('RESOLUTION_INVALID', 'RESOLUTION_NO', 'RESOLUTION_NONE_YET', 'RESOLUTION_YES')"), nullable=False),
        sa.Column('notes', sa.TEXT(), nullable=False, server_default=sa.text("''")),
    )
    op.create_index('resolutions_by_prediction_id', 'resolutions', ['prediction_id'])

    op.create_table(
        'email_invitations',
        sa.Column('inviter', username_t, sa.ForeignKey('users.username'), primary_key=True, nullable=False),
        sa.Column('recipient', username_t, sa.ForeignKey('users.username'), primary_key=True, nullable=False),
        sa.Column('nonce', sa.String(64), unique=True, nullable=False),
    )
    op.create_index('email_invitations_by_nonce', 'email_invitations', ['nonce'])
    op.create_index('email_invitations_by_inviter', 'email_invitations', ['inviter'])
    op.create_index('email_invitations_by_recipient', 'email_invitations', ['recipient'])



def downgrade():
    op.drop_table('email_invitations')
    op.drop_table('resolutions')
    op.drop_table('trades')
    op.drop_table('predictions')
    op.drop_table('relationships')
    op.drop_table('users')
    op.drop_table('passwords')
