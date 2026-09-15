class CreatePublicationPreflights < ActiveRecord::Migration[8.1]
  MAX_OBSERVATION_CLOCK_SKEW_MINUTES = 5

  def up
    create_table :publication_preflights, id: :string do |table|
      table.references :repository, type: :string, null: false, foreign_key: true
      table.string :task_id, null: false
      table.string :prepared_attempt_id, null: false
      table.string :current_owner_attempt_id, null: false
      table.string :observation_owner_attempt_id
      table.string :publication_id
      table.string :candidate_sha, null: false
      table.string :remote, null: false
      table.string :base_ref, null: false
      table.string :state, null: false, default: "prepared"
      table.string :observed_remote_oid
      table.string :observation_digest
      table.text :error
      table.datetime :observed_at
      table.datetime :prepared_at, null: false
      table.datetime :reconciled_at
      table.datetime :consumed_at
      table.timestamps

      table.check_constraint uuid_check("id"), name: "publication_preflights_id_format"
      table.check_constraint git_oid_check("candidate_sha"), name: "publication_preflights_candidate_sha_format"
      table.check_constraint git_oid_check("observed_remote_oid", nullable: true),
        name: "publication_preflights_observed_oid_format"
      table.check_constraint digest_check("observation_digest", nullable: true),
        name: "publication_preflights_observation_digest_format"
      table.check_constraint "error IS NULL OR (json_valid(error) AND json_type(error) = 'object')",
        name: "publication_preflights_error_json"
      table.check_constraint "length(remote) > 0", name: "publication_preflights_remote_present"
      table.check_constraint "base_ref LIKE 'refs/heads/%' AND length(base_ref) > 11",
        name: "publication_preflights_base_ref_format"
      table.check_constraint "state IN ('prepared', 'unknown', 'reconciled', 'consumed')",
        name: "publication_preflights_state_values"
      table.check_constraint lifecycle_shape, name: "publication_preflights_lifecycle_shape"
      table.check_constraint timestamp_order, name: "publication_preflights_timestamp_order"
    end

    add_index :publication_preflights, %i[id repository_id], unique: true
    add_index :publication_preflights, %i[id task_id repository_id], unique: true,
      name: "index_publication_preflights_on_identity_and_scope"
    add_index :publication_preflights, %i[repository_id task_id], unique: true,
      where: "state IN ('prepared', 'unknown', 'reconciled')",
      name: "index_publication_preflights_one_active_per_task"
    add_index :publication_preflights, %i[current_owner_attempt_id state],
      name: "index_publication_preflights_on_owner_and_state"
    add_index :publication_preflights, :publication_id, unique: true, where: "publication_id IS NOT NULL"
    add_foreign_key :publication_preflights, :tasks,
      column: %i[task_id repository_id], primary_key: %i[id repository_id]
    add_foreign_key :publication_preflights, :workflow_attempts,
      column: %i[prepared_attempt_id task_id repository_id], primary_key: %i[id task_id repository_id]
    add_foreign_key :publication_preflights, :workflow_attempts,
      column: %i[current_owner_attempt_id task_id repository_id], primary_key: %i[id task_id repository_id]
    add_foreign_key :publication_preflights, :workflow_attempts,
      column: %i[observation_owner_attempt_id task_id repository_id], primary_key: %i[id task_id repository_id]
    add_foreign_key :publication_preflights, :publications,
      column: %i[publication_id task_id repository_id], primary_key: %i[id task_id repository_id]
    add_triggers
  end

  def down
    execute "DROP TRIGGER IF EXISTS workflow_attempts_active_publication_preflight_guard"
    execute "DROP TRIGGER IF EXISTS publication_preflights_no_delete"
    execute "DROP TRIGGER IF EXISTS publication_preflights_consumed_immutable"
    execute "DROP TRIGGER IF EXISTS publication_preflights_reconciled_observation_immutable"
    execute "DROP TRIGGER IF EXISTS publication_preflights_consumed_binding"
    execute "DROP TRIGGER IF EXISTS publication_preflights_observation_update"
    execute "DROP TRIGGER IF EXISTS publication_preflights_lifecycle"
    execute "DROP TRIGGER IF EXISTS publication_preflights_active_owner_update"
    execute "DROP TRIGGER IF EXISTS publication_preflights_active_owner_insert"
    execute "DROP TRIGGER IF EXISTS publication_preflights_immutable_intent"
    execute "DROP TRIGGER IF EXISTS publication_preflights_primary_key_immutable"
    drop_table :publication_preflights
  end

  private

  def lifecycle_shape
    <<~SQL.squish
      (state = 'prepared' AND observation_owner_attempt_id IS NULL AND observed_remote_oid IS NULL
        AND observation_digest IS NULL AND error IS NULL AND observed_at IS NULL
        AND publication_id IS NULL AND reconciled_at IS NULL AND consumed_at IS NULL)
      OR (state = 'unknown' AND observation_owner_attempt_id IS NULL AND observed_remote_oid IS NULL
        AND observation_digest IS NULL AND error IS NOT NULL AND observed_at IS NULL
        AND publication_id IS NULL AND reconciled_at IS NOT NULL AND consumed_at IS NULL)
      OR (state = 'reconciled' AND observation_owner_attempt_id IS NOT NULL AND observed_remote_oid IS NOT NULL
        AND observation_digest IS NOT NULL AND error IS NULL AND observed_at IS NOT NULL
        AND publication_id IS NULL AND reconciled_at IS NOT NULL AND consumed_at IS NULL)
      OR (state = 'consumed' AND observation_owner_attempt_id IS NOT NULL AND observed_remote_oid IS NOT NULL
        AND observation_digest IS NOT NULL AND error IS NULL AND observed_at IS NOT NULL
        AND publication_id IS NOT NULL AND reconciled_at IS NOT NULL AND consumed_at IS NOT NULL)
    SQL
  end

  def timestamp_order
    <<~SQL.squish
      (observed_at IS NULL OR julianday(observed_at) >= julianday(prepared_at))
      AND (reconciled_at IS NULL OR julianday(reconciled_at) >= julianday(prepared_at))
      AND (consumed_at IS NULL OR julianday(consumed_at) >= julianday(reconciled_at))
    SQL
  end

  def add_triggers
    add_identity_triggers
    add_ownership_triggers
    add_lifecycle_triggers
    add_consumption_triggers
  end

  def add_identity_triggers
    execute <<~SQL
      CREATE TRIGGER publication_preflights_primary_key_immutable
      BEFORE UPDATE OF id ON publication_preflights
      BEGIN
        SELECT RAISE(ABORT, 'primary key is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publication_preflights_immutable_intent
      BEFORE UPDATE OF repository_id, task_id, prepared_attempt_id, candidate_sha, remote, base_ref,
        prepared_at, created_at ON publication_preflights
      BEGIN
        SELECT RAISE(ABORT, 'publication preflight intent is immutable');
      END;
    SQL
  end

  def add_ownership_triggers
    execute <<~SQL
      CREATE TRIGGER publication_preflights_active_owner_insert
      BEFORE INSERT ON publication_preflights
      WHEN NOT EXISTS (
        SELECT 1 FROM workflow_attempts JOIN tasks
          ON tasks.id = workflow_attempts.task_id AND tasks.repository_id = workflow_attempts.repository_id
        WHERE workflow_attempts.id = NEW.current_owner_attempt_id
          AND workflow_attempts.id = NEW.prepared_attempt_id
          AND workflow_attempts.task_id = NEW.task_id AND workflow_attempts.repository_id = NEW.repository_id
          AND workflow_attempts.state = 'started' AND workflow_attempts.lease_expires_at > CURRENT_TIMESTAMP
          AND tasks.active_attempt_id = workflow_attempts.id
      )
      BEGIN
        SELECT RAISE(ABORT, 'publication preflight owner must be the preparing active attempt');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publication_preflights_active_owner_update
      BEFORE UPDATE OF current_owner_attempt_id ON publication_preflights
      WHEN OLD.state NOT IN ('prepared', 'unknown', 'reconciled') OR NOT EXISTS (
        SELECT 1 FROM workflow_attempts JOIN tasks
          ON tasks.id = workflow_attempts.task_id AND tasks.repository_id = workflow_attempts.repository_id
        WHERE workflow_attempts.id = NEW.current_owner_attempt_id
          AND workflow_attempts.task_id = NEW.task_id AND workflow_attempts.repository_id = NEW.repository_id
          AND workflow_attempts.state = 'started' AND workflow_attempts.lease_expires_at > CURRENT_TIMESTAMP
          AND tasks.active_attempt_id = workflow_attempts.id
      )
      BEGIN
        SELECT RAISE(ABORT, 'publication preflight owner must be an active replacement attempt');
      END;
    SQL
  end

  def add_lifecycle_triggers
    execute <<~SQL
      CREATE TRIGGER publication_preflights_lifecycle
      BEFORE UPDATE OF state ON publication_preflights
      WHEN NOT (
        (OLD.state = 'prepared' AND NEW.state IN ('prepared', 'unknown', 'reconciled'))
        OR (OLD.state = 'unknown' AND NEW.state IN ('unknown', 'reconciled'))
        OR (OLD.state = 'reconciled' AND NEW.state IN ('reconciled', 'consumed'))
        OR (OLD.state = 'consumed' AND NEW.state = 'consumed')
      )
      BEGIN
        SELECT RAISE(ABORT, 'invalid publication preflight lifecycle transition');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publication_preflights_observation_update
      BEFORE UPDATE OF observation_owner_attempt_id, observed_remote_oid, observation_digest, error,
        observed_at, reconciled_at ON publication_preflights
      WHEN OLD.state IN ('prepared', 'unknown') AND (
        NEW.current_owner_attempt_id IS NOT (
          SELECT active_attempt_id FROM tasks WHERE id = NEW.task_id AND repository_id = NEW.repository_id
        )
        OR (NEW.state = 'reconciled' AND NEW.observation_owner_attempt_id IS NOT NEW.current_owner_attempt_id)
        OR (NEW.observed_at IS NOT NULL AND (
          julianday(NEW.observed_at) IS NULL
          OR julianday(NEW.observed_at) < julianday(NEW.prepared_at)
          OR julianday(NEW.observed_at) >
            julianday(CURRENT_TIMESTAMP, '+#{MAX_OBSERVATION_CLOCK_SKEW_MINUTES} minutes')
        ))
      )
      BEGIN
        SELECT RAISE(ABORT, 'invalid publication preflight observation update');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publication_preflights_reconciled_observation_immutable
      BEFORE UPDATE OF observation_owner_attempt_id, observed_remote_oid, observation_digest, error,
        observed_at, reconciled_at ON publication_preflights
      WHEN OLD.state = 'reconciled' AND (
        NEW.observation_owner_attempt_id IS NOT OLD.observation_owner_attempt_id
        OR NEW.observed_remote_oid IS NOT OLD.observed_remote_oid
        OR NEW.observation_digest IS NOT OLD.observation_digest
        OR NEW.error IS NOT OLD.error
        OR NEW.observed_at IS NOT OLD.observed_at
        OR NEW.reconciled_at IS NOT OLD.reconciled_at
      )
      BEGIN
        SELECT RAISE(ABORT, 'reconciled publication preflight observation is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publication_preflights_consumed_immutable
      BEFORE UPDATE ON publication_preflights
      WHEN OLD.state = 'consumed'
      BEGIN
        SELECT RAISE(ABORT, 'consumed publication preflight is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publication_preflights_no_delete
      BEFORE DELETE ON publication_preflights
      BEGIN
        SELECT RAISE(ABORT, 'publication preflight cannot be deleted');
      END;
    SQL
  end

  def add_consumption_triggers
    execute <<~SQL
      CREATE TRIGGER publication_preflights_consumed_binding
      BEFORE UPDATE OF state, publication_id, consumed_at ON publication_preflights
      WHEN NEW.state = 'consumed' AND NOT EXISTS (
        SELECT 1 FROM publications
        WHERE id = NEW.publication_id AND task_id = NEW.task_id AND repository_id = NEW.repository_id
          AND prepared_attempt_id = NEW.current_owner_attempt_id
          AND current_owner_attempt_id = NEW.current_owner_attempt_id
          AND candidate_sha = NEW.candidate_sha AND remote = NEW.remote AND base_ref = NEW.base_ref
          AND expected_remote_oid = NEW.observed_remote_oid AND state = 'prepared'
      )
      BEGIN
        SELECT RAISE(ABORT, 'consumed publication preflight must bind its prepared publication');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_active_publication_preflight_guard
      BEFORE UPDATE OF state ON workflow_attempts
      WHEN NEW.state IN ('succeeded', 'failed', 'needs_human') AND EXISTS (
        SELECT 1 FROM publication_preflights
        WHERE current_owner_attempt_id = OLD.id AND state IN ('prepared', 'unknown', 'reconciled')
      )
      BEGIN
        SELECT RAISE(ABORT, 'attempt cannot finish with an active publication preflight');
      END;
    SQL
  end

  def uuid_check(column)
    <<~SQL.squish
      length(#{column}) = 36
      AND substr(#{column}, 9, 1) = '-'
      AND substr(#{column}, 14, 1) = '-'
      AND substr(#{column}, 19, 1) = '-'
      AND substr(#{column}, 24, 1) = '-'
      AND length(replace(#{column}, '-', '')) = 32
      AND replace(#{column}, '-', '') NOT GLOB '*[^0-9a-f]*'
    SQL
  end

  def git_oid_check(column, nullable: false)
    expression = "length(#{column}) = 40 AND #{column} NOT GLOB '*[^0-9a-f]*'"
    nullable ? "#{column} IS NULL OR (#{expression})" : expression
  end

  def digest_check(column, nullable: false)
    expression = <<~SQL.squish
      substr(#{column}, 1, 7) = 'sha256:' AND length(#{column}) = 71
      AND substr(#{column}, 8) NOT GLOB '*[^0-9a-f]*'
    SQL
    nullable ? "#{column} IS NULL OR (#{expression})" : expression
  end
end
