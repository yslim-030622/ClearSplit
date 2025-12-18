-- Reference-only snapshot. Source of truth is Alembic migrations in backend/alembic/versions.
-- ClearSplit PostgreSQL schema for MVP1
-- Money stored as BIGINT cents; all timestamps are UTC (timestamptz).

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS citext;

-- Enums
CREATE TYPE membership_role AS ENUM ('owner', 'member', 'viewer');
CREATE TYPE settlement_status AS ENUM ('suggested', 'paid', 'voided');

CREATE TABLE users (
    id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    email         citext NOT NULL UNIQUE,
    password_hash text   NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE groups (
    id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name       text   NOT NULL,
    currency   char(3) NOT NULL DEFAULT 'USD',
    version    integer NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE memberships (
    id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id   uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role       membership_role NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (group_id, user_id),
    UNIQUE (group_id, id)
);

CREATE TABLE expenses (
    id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id      uuid NOT NULL,
    title         text   NOT NULL,
    amount_cents  bigint NOT NULL CHECK (amount_cents > 0),
    currency      char(3) NOT NULL DEFAULT 'USD',
    paid_by       uuid NOT NULL,
    expense_date  date NOT NULL,
    memo          text,
    version       integer NOT NULL DEFAULT 1,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id, group_id),
    CONSTRAINT fk_expenses_group FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
    CONSTRAINT fk_expenses_paid_by FOREIGN KEY (group_id, paid_by)
        REFERENCES memberships(group_id, id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE expense_splits (
    id             uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    expense_id     uuid NOT NULL,
    group_id       uuid NOT NULL,
    membership_id  uuid NOT NULL,
    share_cents    bigint NOT NULL CHECK (share_cents >= 0),
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_splits_expense FOREIGN KEY (expense_id, group_id)
        REFERENCES expenses(id, group_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_splits_membership FOREIGN KEY (group_id, membership_id)
        REFERENCES memberships(group_id, id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE settlement_batches (
    id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id           uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    status             settlement_status NOT NULL DEFAULT 'suggested',
    total_settlements  integer NOT NULL DEFAULT 0,
    version            integer NOT NULL DEFAULT 1,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    voided_reason      text,
    UNIQUE (id, group_id)
);

CREATE TABLE settlements (
    id               uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    batch_id         uuid NOT NULL,
    group_id         uuid NOT NULL,
    from_membership  uuid NOT NULL,
    to_membership    uuid NOT NULL,
    amount_cents     bigint NOT NULL CHECK (amount_cents > 0),
    status           settlement_status NOT NULL DEFAULT 'suggested',
    created_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT settlements_from_to_chk CHECK (from_membership <> to_membership),
    CONSTRAINT fk_settlements_batch FOREIGN KEY (batch_id, group_id)
        REFERENCES settlement_batches(id, group_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_settlements_from FOREIGN KEY (group_id, from_membership)
        REFERENCES memberships(group_id, id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_settlements_to FOREIGN KEY (group_id, to_membership)
        REFERENCES memberships(group_id, id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE activity_log (
    id               uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id         uuid REFERENCES groups(id) ON DELETE CASCADE,
    actor_membership uuid REFERENCES memberships(id) ON DELETE SET NULL,
    event_type       text NOT NULL,
    subject_id       uuid,
    metadata         jsonb,
    created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE idempotency_keys (
    id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    endpoint      text NOT NULL,
    user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    request_hash  text NOT NULL,
    response_body jsonb,
    status_code   integer,
    created_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (endpoint, user_id, request_hash)
);

-- Trigger helpers
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at_users
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_updated_at_groups
BEFORE UPDATE ON groups
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_updated_at_expenses
BEFORE UPDATE ON expenses
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_updated_at_settlement_batches
BEFORE UPDATE ON settlement_batches
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Enforce sum(share_cents) = expenses.amount_cents at transaction end.
CREATE OR REPLACE FUNCTION enforce_expense_split_sum()
RETURNS TRIGGER AS $$
DECLARE
    total bigint;
    expected bigint;
BEGIN
    SELECT SUM(share_cents) INTO total FROM expense_splits WHERE expense_id = NEW.expense_id;
    SELECT amount_cents INTO expected FROM expenses WHERE id = NEW.expense_id;
    IF total IS DISTINCT FROM expected THEN
        RAISE EXCEPTION 'Expense % split sum % does not equal amount %', NEW.expense_id, total, expected;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER expense_split_sum_check
AFTER INSERT OR UPDATE OR DELETE ON expense_splits
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION enforce_expense_split_sum();

-- Indexes
CREATE INDEX idx_memberships_group_user ON memberships(group_id, user_id);
CREATE INDEX idx_memberships_user ON memberships(user_id);
CREATE INDEX idx_expenses_group_created ON expenses(group_id, created_at DESC);
CREATE INDEX idx_expenses_group_date ON expenses(group_id, expense_date DESC);
CREATE INDEX idx_expenses_paid_by ON expenses(paid_by);
CREATE INDEX idx_expense_splits_expense ON expense_splits(expense_id);
CREATE INDEX idx_expense_splits_group_expense ON expense_splits(group_id, expense_id);
CREATE INDEX idx_settlement_batches_group_created ON settlement_batches(group_id, created_at DESC);
CREATE INDEX idx_settlements_batch ON settlements(batch_id);
CREATE INDEX idx_settlements_from ON settlements(from_membership);
CREATE INDEX idx_settlements_to ON settlements(to_membership);
CREATE INDEX idx_activity_group_created ON activity_log(group_id, created_at DESC);

-- Seed data (example)
INSERT INTO users (id, email, password_hash) VALUES
    ('00000000-0000-0000-0000-000000000001', 'alice@example.com', 'hash1'),
    ('00000000-0000-0000-0000-000000000002', 'bob@example.com', 'hash2'),
    ('00000000-0000-0000-0000-000000000003', 'carol@example.com', 'hash3');

INSERT INTO groups (id, name) VALUES
    ('10000000-0000-0000-0000-000000000001', 'Trip');

INSERT INTO memberships (id, group_id, user_id, role) VALUES
    ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'owner'),
    ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'member'),
    ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'member');

INSERT INTO expenses (id, group_id, title, amount_cents, currency, paid_by, expense_date) VALUES
    ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Dinner', 12000, 'USD', '20000000-0000-0000-0000-000000000001', '2024-01-01'),
    ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'Hotel', 30000, 'USD', '20000000-0000-0000-0000-000000000002', '2024-01-02');

INSERT INTO expense_splits (id, expense_id, group_id, membership_id, share_cents) VALUES
    (uuid_generate_v4(), '30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 4000),
    (uuid_generate_v4(), '30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 4000),
    (uuid_generate_v4(), '30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000003', 4000),
    (uuid_generate_v4(), '30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 10000),
    (uuid_generate_v4(), '30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 10000),
    (uuid_generate_v4(), '30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000003', 10000);

INSERT INTO settlement_batches (id, group_id, status, total_settlements) VALUES
    ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'suggested', 1);

INSERT INTO settlements (id, batch_id, group_id, from_membership, to_membership, amount_cents, status) VALUES
    (uuid_generate_v4(), '40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 9000, 'suggested');
