class CreatePublications < ActiveRecord::Migration[8.1]
  MAX_OBSERVATION_CLOCK_SKEW_MINUTES = 5

  def up
    create_table :publications, id: :string do |table|
      table.references :repository, type: :string, null: false, foreign_key: true
      table.string :task_id, null: false
      table.string :prepared_attempt_id, null: false
      table.string :current_owner_attempt_id, null: false
      table.string :observation_owner_attempt_id
      table.string :candidate_sha, null: false
      table.string :remote, null: false
      table.string :base_ref, null: false
      table.string :expected_remote_oid, null: false
      table.string :state, null: false, default: "prepared"
      table.string :observed_remote_tip
      table.boolean :candidate_reachable
      table.string :observation_digest
      table.datetime :observed_at
      table.datetime :prepared_at, null: false
      table.datetime :reconciled_at
      table.datetime :completed_at
      table.timestamps

      table.check_constraint uuid_check("id"), name: "publications_id_format"
      table.check_constraint git_oid_check("candidate_sha"), name: "publications_candidate_sha_format"
      table.check_constraint git_oid_check("expected_remote_oid"), name: "publications_expected_oid_format"
      table.check_constraint git_oid_check("observed_remote_tip", nullable: true),
        name: "publications_observed_tip_format"
      table.check_constraint digest_check("observation_digest", nullable: true),
        name: "publications_observation_digest_format"
      table.check_constraint "candidate_reachable IS NULL OR candidate_reachable IN (0, 1)",
        name: "publications_candidate_reachable_boolean"
      table.check_constraint "length(remote) > 0", name: "publications_remote_present"
      table.check_constraint "base_ref LIKE 'refs/heads/%' AND length(base_ref) > 11",
        name: "publications_base_ref_format"
      table.check_constraint "state IN ('prepared', 'reconciled', 'superseded', 'completed')",
        name: "publications_state_values"
      table.check_constraint <<~SQL.squish, name: "publications_observation_shape"
        (state = 'prepared' AND observation_owner_attempt_id IS NULL
          AND observed_remote_tip IS NULL AND candidate_reachable IS NULL
          AND observation_digest IS NULL AND observed_at IS NULL AND reconciled_at IS NULL
          AND completed_at IS NULL)
        OR (state IN ('reconciled', 'superseded') AND observation_owner_attempt_id IS NOT NULL
          AND observed_remote_tip IS NOT NULL
          AND candidate_reachable IS NOT NULL AND observation_digest IS NOT NULL
          AND observed_at IS NOT NULL AND reconciled_at IS NOT NULL AND completed_at IS NULL)
        OR (state = 'completed' AND observation_owner_attempt_id IS NOT NULL
          AND observed_remote_tip IS NOT NULL AND candidate_reachable = 1
          AND observation_digest IS NOT NULL AND observed_at IS NOT NULL
          AND reconciled_at IS NOT NULL AND completed_at IS NOT NULL)
      SQL
      table.check_constraint "state <> 'superseded' OR candidate_reachable = 0",
        name: "publications_superseded_unreachable"
    end

    add_index :publications, %i[id repository_id], unique: true
    add_index :publications, %i[id task_id repository_id], unique: true,
      name: "index_publications_on_identity_and_ownership"
    add_index :publications, %i[repository_id task_id], unique: true,
      where: "state IN ('prepared', 'reconciled')", name: "index_publications_one_unresolved_per_task"
    add_index :publications, %i[current_owner_attempt_id state],
      name: "index_publications_on_owner_and_state"
    add_foreign_key :publications, :tasks,
      column: %i[task_id repository_id], primary_key: %i[id repository_id]
    add_foreign_key :publications, :workflow_attempts,
      column: %i[prepared_attempt_id task_id repository_id], primary_key: %i[id task_id repository_id]
    add_foreign_key :publications, :workflow_attempts,
      column: %i[current_owner_attempt_id task_id repository_id], primary_key: %i[id task_id repository_id]
    add_foreign_key :publications, :workflow_attempts,
      column: %i[observation_owner_attempt_id task_id repository_id], primary_key: %i[id task_id repository_id]

    add_column :tasks, :active_publication_id, :string
    add_index :tasks, :active_publication_id, unique: true
    add_foreign_key :tasks, :publications,
      column: %i[active_publication_id id repository_id], primary_key: %i[id task_id repository_id]
    restore_task_triggers
    add_triggers
  end

  def down
    execute "DROP TRIGGER IF EXISTS workflow_attempts_unresolved_publication_guard"
    execute "DROP TRIGGER IF EXISTS tasks_active_publication_must_be_unresolved"
    execute "DROP TRIGGER IF EXISTS publications_terminal_requires_detached_task"
    execute "DROP TRIGGER IF EXISTS publications_observation_update"
    execute "DROP TRIGGER IF EXISTS publications_no_delete"
    execute "DROP TRIGGER IF EXISTS publications_terminal_immutable"
    execute "DROP TRIGGER IF EXISTS publications_lifecycle"
    execute "DROP TRIGGER IF EXISTS publications_active_owner_update"
    execute "DROP TRIGGER IF EXISTS publications_active_owner_insert"
    execute "DROP TRIGGER IF EXISTS publications_immutable_intent"
    execute "DROP TRIGGER IF EXISTS publications_primary_key_immutable"
    remove_foreign_key :tasks, column: %i[active_publication_id id repository_id]
    remove_index :tasks, :active_publication_id
    remove_column :tasks, :active_publication_id
    drop_table :publications
    restore_task_triggers
  end

  private

  def restore_task_triggers
    execute <<~SQL
      CREATE TRIGGER tasks_primary_key_immutable
      BEFORE UPDATE OF id ON tasks
      BEGIN
        SELECT RAISE(ABORT, 'primary key is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER tasks_workflow_version_must_be_published
      BEFORE INSERT ON tasks
      WHEN NOT EXISTS (
        SELECT 1 FROM workflow_versions
        WHERE id = NEW.workflow_version_id AND published_at IS NOT NULL
      )
      BEGIN
        SELECT RAISE(ABORT, 'task workflow version must be published');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER tasks_immutable_identity
      BEFORE UPDATE OF repository_id, sequence, task_type_id, workflow_version_id ON tasks
      BEGIN
        SELECT RAISE(ABORT, 'task identity and workflow version are immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER tasks_active_attempt_must_be_started
      BEFORE UPDATE OF active_attempt_id ON tasks
      WHEN NEW.active_attempt_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM workflow_attempts
        WHERE id = NEW.active_attempt_id AND task_id = NEW.id
          AND repository_id = NEW.repository_id AND workflow_state_id = NEW.workflow_state_id
          AND state = 'started'
      )
      BEGIN
        SELECT RAISE(ABORT, 'active attempt must be started for this task');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER tasks_workflow_state_requires_matching_attempt
      BEFORE UPDATE OF workflow_state_id ON tasks
      WHEN NEW.active_attempt_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM workflow_attempts
        WHERE id = NEW.active_attempt_id AND task_id = NEW.id
          AND repository_id = NEW.repository_id AND workflow_state_id = NEW.workflow_state_id
          AND state = 'started'
      )
      BEGIN
        SELECT RAISE(ABORT, 'active attempt must match the task workflow state');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER tasks_worktree_reservation_must_be_active
      BEFORE UPDATE OF worktree_reservation_id ON tasks
      WHEN NEW.worktree_reservation_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM worktree_reservations
        WHERE id = NEW.worktree_reservation_id AND task_id = NEW.id
          AND repository_id = NEW.repository_id AND state <> 'released'
      )
      BEGIN
        SELECT RAISE(ABORT, 'task worktree reservation must be active');
      END;
    SQL
  end

  def add_triggers
    execute <<~SQL
      CREATE TRIGGER publications_primary_key_immutable
      BEFORE UPDATE OF id ON publications
      BEGIN
        SELECT RAISE(ABORT, 'primary key is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publications_immutable_intent
      BEFORE UPDATE OF repository_id, task_id, prepared_attempt_id, candidate_sha, remote, base_ref,
        expected_remote_oid, prepared_at, created_at ON publications
      BEGIN
        SELECT RAISE(ABORT, 'publication intent is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publications_active_owner_insert
      BEFORE INSERT ON publications
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
        SELECT RAISE(ABORT, 'publication owner must be the preparing active attempt');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publications_active_owner_update
      BEFORE UPDATE OF current_owner_attempt_id ON publications
      WHEN OLD.state NOT IN ('prepared', 'reconciled') OR NOT EXISTS (
        SELECT 1 FROM workflow_attempts JOIN tasks
          ON tasks.id = workflow_attempts.task_id AND tasks.repository_id = workflow_attempts.repository_id
        WHERE workflow_attempts.id = NEW.current_owner_attempt_id AND workflow_attempts.task_id = NEW.task_id
          AND workflow_attempts.repository_id = NEW.repository_id AND workflow_attempts.state = 'started'
          AND workflow_attempts.lease_expires_at > CURRENT_TIMESTAMP
          AND tasks.active_attempt_id = workflow_attempts.id
      )
      BEGIN
        SELECT RAISE(ABORT, 'publication owner must be an active replacement attempt');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publications_lifecycle
      BEFORE UPDATE OF state ON publications
      WHEN NOT (
        (OLD.state = 'prepared' AND NEW.state IN ('prepared', 'reconciled', 'superseded'))
        OR (OLD.state = 'reconciled' AND NEW.state IN ('reconciled', 'superseded', 'completed'))
        OR (OLD.state IN ('superseded', 'completed') AND NEW.state = OLD.state)
      )
      BEGIN
        SELECT RAISE(ABORT, 'invalid publication lifecycle transition');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publications_observation_update
      BEFORE UPDATE OF observation_owner_attempt_id, observed_remote_tip, candidate_reachable,
        observation_digest, observed_at, reconciled_at ON publications
      WHEN NEW.observed_at IS NOT NULL AND (
        julianday(NEW.observed_at) IS NULL
        OR julianday(NEW.observed_at) < julianday(NEW.prepared_at)
        OR julianday(NEW.observed_at) >
          julianday(CURRENT_TIMESTAMP, '+#{MAX_OBSERVATION_CLOCK_SKEW_MINUTES} minutes')
        OR (OLD.observed_at IS NOT NULL
          AND julianday(NEW.observed_at) <= julianday(OLD.observed_at))
        OR NEW.observation_owner_attempt_id IS NOT NEW.current_owner_attempt_id
      )
      BEGIN
        SELECT RAISE(ABORT, 'invalid publication observation update');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publications_terminal_immutable
      BEFORE UPDATE ON publications
      WHEN OLD.state IN ('superseded', 'completed')
      BEGIN
        SELECT RAISE(ABORT, 'terminal publication is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publications_no_delete
      BEFORE DELETE ON publications
      BEGIN
        SELECT RAISE(ABORT, 'publication cannot be deleted');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publications_terminal_requires_detached_task
      BEFORE UPDATE OF state ON publications
      WHEN NEW.state IN ('superseded', 'completed') AND EXISTS (
        SELECT 1 FROM tasks WHERE active_publication_id = OLD.id
      )
      BEGIN
        SELECT RAISE(ABORT, 'task must release its active publication before termination');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER tasks_active_publication_must_be_unresolved
      BEFORE UPDATE OF active_publication_id ON tasks
      WHEN NEW.active_publication_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM publications WHERE id = NEW.active_publication_id AND task_id = NEW.id
          AND repository_id = NEW.repository_id AND state IN ('prepared', 'reconciled')
      )
      BEGIN
        SELECT RAISE(ABORT, 'task active publication must be unresolved');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_unresolved_publication_guard
      BEFORE UPDATE OF state ON workflow_attempts
      WHEN NEW.state IN ('succeeded', 'failed', 'needs_human') AND EXISTS (
        SELECT 1 FROM publications
        WHERE current_owner_attempt_id = OLD.id AND state IN ('prepared', 'reconciled')
      )
      BEGIN
        SELECT RAISE(ABORT, 'attempt cannot finish with an unresolved publication');
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
