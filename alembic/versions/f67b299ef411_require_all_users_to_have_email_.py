"""require all users to have email addresses, and remove settings to disable emails

Revision ID: f67b299ef411
Revises: 235b772150a8
Create Date: 2021-07-30 11:05:33.508358

"""
from alembic import op
import sqlalchemy as sa
from server.protobuf import mvp_pb2


# revision identifiers, used by Alembic.
revision = 'f67b299ef411'
down_revision = '235b772150a8'
branch_labels = None
depends_on = None

old_users_table = sa.table('users', sa.Column('username', sa.String(64)), sa.Column('email_flow_state', sa.BLOB()))
new_users_table = sa.table('users', sa.Column('username', sa.String(64)), sa.Column('email_address', sa.String(128)))

def upgrade():
    with op.batch_alter_table('users') as batch_op:
        batch_op.add_column(sa.Column('email_address', sa.String(length=128), nullable=True))

    users_without_emails = []
    conn = op.get_bind()
    for row in conn.execute(sa.select(old_users_table.c)):
        efs = mvp_pb2.EmailFlowState.FromString(row['email_flow_state'])
        if efs.WhichOneof('email_flow_state_kind') == 'verified':
            batch_op.execute(sa.update(new_users_table).values(email_address=efs.verified).where(new_users_table.c.username == row['username']))
        else:
            users_without_emails.append(row['username'])
    if users_without_emails:
        raise RuntimeError(f"can't migrate users: {users_without_emails}")

    with op.batch_alter_table('users') as batch_op:
        batch_op.alter_column('email_address', nullable=False)
        batch_op.create_unique_constraint('unique_user_email', ['email_address'])

    with op.batch_alter_table('users') as batch_op:
        batch_op.drop_column('email_invitation_acceptance_notifications')
        batch_op.drop_column('allow_email_invitations')
        batch_op.drop_column('email_reminders_to_resolve')
        batch_op.drop_column('email_resolution_notifications')
        batch_op.drop_column('email_flow_state')


def downgrade():
    with op.batch_alter_table('users') as batch_op:
        batch_op.add_column(sa.Column('email_flow_state', sa.BLOB(), nullable=True))

    conn = op.get_bind()
    for row in conn.execute(sa.select(new_users_table.c)):
        op.execute(sa.update(old_users_table).values(email_flow_state=mvp_pb2.EmailFlowState(verified=row['email_address']).SerializeToString()).where(old_users_table.c.username == row['username']))

    with op.batch_alter_table('users') as batch_op:
        batch_op.alter_column('email_flow_state', nullable=False)

    with op.batch_alter_table('users') as batch_op:
        batch_op.add_column(sa.Column('email_resolution_notifications', sa.BOOLEAN(), server_default=sa.text('(TRUE)'), nullable=False))
        batch_op.add_column(sa.Column('email_reminders_to_resolve', sa.BOOLEAN(), server_default=sa.text('(TRUE)'), nullable=False))
        batch_op.add_column(sa.Column('allow_email_invitations', sa.BOOLEAN(), server_default=sa.text('(TRUE)'), nullable=False))
        batch_op.add_column(sa.Column('email_invitation_acceptance_notifications', sa.BOOLEAN(), server_default=sa.text('(TRUE)'), nullable=False))
        batch_op.drop_column('email_address')
