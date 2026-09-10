class CreateExecutionPersistence < ActiveRecord::Migration[8.1]
  UUID_TABLES = %w[workflow_attempts idempotency_records task_artifacts worktree_reservations].freeze

  def change
    add_index :tasks, %i[id repository_id], unique: true

    create_workflow_attempts
    create_idempotency_records
    create_task_artifacts
    create_worktree_reservations
    add_task_execution_references
    add_execution_triggers
  end

  private

  def create_workflow_attempts
    create_table :workflow_attempts, id: :string do |table|
      table.references :repository, type: :string, null: false, foreign_key: true
      table.string :task_id, null: false
      table.string :workflow_state_id, null: false
      table.string :owner_id, null: false
      table.string :idempotency_key, null: false
      table.string :state, null: false, default: "started"
      table.integer :fencing_token, null: false
      table.datetime :lease_expires_at
      table.datetime :heartbeat_at
      table.datetime :started_at, null: false
      table.datetime :completed_at
      table.text :input_context
      table.string :input_context_digest
      table.text :result_manifest
      table.timestamps

      table.check_constraint uuid_check("id"), name: "workflow_attempts_id_format"
      table.check_constraint identifier_check("owner_id"), name: "workflow_attempts_owner_id_format"
      table.check_constraint idempotency_key_check("idempotency_key"), name: "workflow_attempts_idempotency_key_format"
      table.check_constraint "fencing_token >= 1", name: "workflow_attempts_fencing_token_positive"
      table.check_constraint "state IN ('started', 'succeeded', 'failed', 'interrupted', 'needs_human')",
        name: "workflow_attempts_state_values"
      table.check_constraint digest_check("input_context_digest", nullable: true),
        name: "workflow_attempts_context_digest_format"
      table.check_constraint json_object_check("input_context", nullable: true),
        name: "workflow_attempts_input_context_json"
      table.check_constraint json_object_check("result_manifest", nullable: true),
        name: "workflow_attempts_result_manifest_json"
      table.check_constraint <<~SQL.squish, name: "workflow_attempts_context_pair"
        (input_context IS NULL AND input_context_digest IS NULL)
        OR (input_context IS NOT NULL AND input_context_digest IS NOT NULL)
      SQL
      table.check_constraint <<~SQL.squish, name: "workflow_attempts_timestamp_order"
        heartbeat_at IS NOT NULL AND heartbeat_at >= started_at
        AND (lease_expires_at IS NULL OR lease_expires_at > heartbeat_at)
        AND (completed_at IS NULL OR completed_at >= heartbeat_at)
      SQL
      table.check_constraint <<~SQL.squish, name: "workflow_attempts_lifecycle_shape"
        (state = 'started' AND lease_expires_at IS NOT NULL AND heartbeat_at IS NOT NULL
          AND completed_at IS NULL AND result_manifest IS NULL)
        OR (state = 'interrupted' AND lease_expires_at IS NULL AND heartbeat_at IS NOT NULL
          AND completed_at IS NOT NULL AND result_manifest IS NULL)
        OR (state IN ('succeeded', 'failed', 'needs_human') AND lease_expires_at IS NULL
          AND heartbeat_at IS NOT NULL AND completed_at IS NOT NULL
          AND input_context IS NOT NULL AND result_manifest IS NOT NULL)
      SQL
      table.check_constraint <<~SQL.squish, name: "workflow_attempts_result_manifest_binding"
        result_manifest IS NULL OR (
          json_extract(result_manifest, '$.attempt_id') IS id
          AND json_extract(result_manifest, '$.input_context_digest') IS input_context_digest
          AND json_extract(result_manifest, '$.outcome') IS state
        )
      SQL
    end

    add_index :workflow_attempts, %i[id repository_id], unique: true
    add_index :workflow_attempts, %i[id task_id repository_id], unique: true,
      name: "index_workflow_attempts_on_identity_and_ownership"
    add_index :workflow_attempts, %i[id task_id repository_id fencing_token], unique: true,
      name: "index_workflow_attempts_on_identity_and_fencing"
    add_index :workflow_attempts, %i[repository_id task_id fencing_token], unique: true,
      name: "index_workflow_attempts_on_task_and_fencing"
    add_index :workflow_attempts, %i[repository_id idempotency_key], unique: true
    add_index :workflow_attempts, %i[repository_id task_id], unique: true,
      where: "state = 'started'", name: "index_workflow_attempts_one_started_per_task"
    add_foreign_key :workflow_attempts, :tasks,
      column: %i[task_id repository_id], primary_key: %i[id repository_id]
    add_foreign_key :workflow_attempts, :workflow_states
  end

  def create_idempotency_records
    create_table :idempotency_records, id: :string do |table|
      table.references :repository, type: :string, foreign_key: true
      table.string :command, null: false
      table.string :idempotency_key, null: false
      table.string :request_fingerprint, null: false
      table.string :state, null: false, default: "in_progress"
      table.string :intent_resource_type
      table.string :intent_resource_id
      table.integer :response_status
      table.text :response_data
      table.datetime :completed_at
      table.timestamps

      table.check_constraint uuid_check("id"), name: "idempotency_records_id_format"
      table.check_constraint command_check("command"), name: "idempotency_records_command_format"
      table.check_constraint idempotency_key_check("idempotency_key"), name: "idempotency_records_key_format"
      table.check_constraint digest_check("request_fingerprint"), name: "idempotency_records_fingerprint_format"
      table.check_constraint "state IN ('in_progress', 'completed')", name: "idempotency_records_state_values"
      table.check_constraint "intent_resource_type IS NULL OR (#{identifier_check("intent_resource_type")})",
        name: "idempotency_records_intent_type_format"
      table.check_constraint "intent_resource_id IS NULL OR (#{uuid_check("intent_resource_id")})",
        name: "idempotency_records_intent_id_format"
      table.check_constraint json_object_check("response_data", nullable: true),
        name: "idempotency_records_response_data_json"
      table.check_constraint <<~SQL.squish, name: "idempotency_records_lifecycle_shape"
        (state = 'in_progress' AND intent_resource_type IS NOT NULL AND intent_resource_id IS NOT NULL
          AND response_status IS NULL AND response_data IS NULL AND completed_at IS NULL)
        OR (state = 'completed' AND intent_resource_type IS NULL AND intent_resource_id IS NULL
          AND response_status IS NOT NULL AND response_status BETWEEN 100 AND 599
          AND response_data IS NOT NULL AND completed_at IS NOT NULL)
      SQL
    end

    add_index :idempotency_records, %i[command idempotency_key], unique: true,
      where: "repository_id IS NULL", name: "index_idempotency_records_global_uniqueness"
    add_index :idempotency_records, %i[repository_id command idempotency_key], unique: true,
      where: "repository_id IS NOT NULL", name: "index_idempotency_records_repository_uniqueness"
  end

  def create_task_artifacts
    create_table :task_artifacts, id: :string do |table|
      table.references :repository, type: :string, null: false, foreign_key: true
      table.string :task_id, null: false
      table.string :workflow_attempt_id, null: false
      table.string :artifact_type, null: false
      table.string :state, null: false
      table.string :producer, null: false
      table.text :metadata, null: false
      table.datetime :created_at, null: false

      table.check_constraint uuid_check("id"), name: "task_artifacts_id_format"
      table.check_constraint identifier_check("producer"), name: "task_artifacts_producer_format"
      table.check_constraint json_object_check("metadata"), name: "task_artifacts_metadata_json"
      table.check_constraint <<~SQL.squish, name: "task_artifacts_type_state_pair"
        (artifact_type IN ('document', 'candidate') AND state = 'produced')
        OR (artifact_type = 'test' AND state IN ('passed', 'failed'))
        OR (artifact_type = 'review' AND state IN ('approved', 'changes_requested'))
        OR (artifact_type = 'publication' AND state = 'published')
      SQL
      table.check_constraint "json_extract(metadata, '$.kind') IS artifact_type",
        name: "task_artifacts_metadata_kind"
      table.check_constraint <<~SQL.squish, name: "task_artifacts_test_result_binding"
        artifact_type <> 'test' OR (
          json_type(metadata, '$.exit_code') IS 'integer'
          AND ((state = 'passed' AND json_extract(metadata, '$.exit_code') = 0)
            OR (state = 'failed' AND json_extract(metadata, '$.exit_code') >= 1))
        )
      SQL
      table.check_constraint "artifact_type <> 'review' OR json_extract(metadata, '$.verdict') IS state",
        name: "task_artifacts_review_verdict_binding"
      table.check_constraint <<~SQL.squish, name: "task_artifacts_publication_reachability"
        artifact_type <> 'publication' OR (
          json_type(metadata, '$.reachable') IS 'true'
          AND json_extract(metadata, '$.reachable') IS 1
        )
      SQL
    end

    add_index :task_artifacts, %i[repository_id task_id created_at id],
      name: "index_task_artifacts_for_listing"
    add_index :task_artifacts, %i[repository_id task_id artifact_type state],
      name: "index_task_artifacts_for_contracts"
    add_foreign_key :task_artifacts, :workflow_attempts,
      column: %i[workflow_attempt_id task_id repository_id],
      primary_key: %i[id task_id repository_id]
  end

  def create_worktree_reservations
    create_table :worktree_reservations, id: :string do |table|
      table.references :repository, type: :string, null: false, foreign_key: true
      table.string :task_id, null: false
      table.string :workflow_attempt_id, null: false
      table.string :branch, null: false
      table.string :path, null: false
      table.string :state, null: false, default: "reserved"
      table.integer :fencing_token, null: false
      table.string :git_common_dir_digest
      table.string :head_sha
      table.string :observed_state
      table.string :observation_digest
      table.datetime :confirmed_at
      table.datetime :released_at
      table.timestamps

      table.check_constraint uuid_check("id"), name: "worktree_reservations_id_format"
      table.check_constraint "path LIKE '/%'", name: "worktree_reservations_path_absolute"
      table.check_constraint "length(branch) > 0", name: "worktree_reservations_branch_present"
      table.check_constraint "fencing_token >= 1", name: "worktree_reservations_fencing_token_positive"
      table.check_constraint "state IN ('reserved', 'confirmed', 'release_pending', 'released')",
        name: "worktree_reservations_state_values"
      table.check_constraint <<~SQL.squish, name: "worktree_reservations_observed_state_values"
        observed_state IS NULL OR observed_state IN ('absent', 'clean', 'dirty', 'mismatched')
      SQL
      table.check_constraint digest_check("git_common_dir_digest", nullable: true),
        name: "worktree_reservations_common_dir_digest_format"
      table.check_constraint git_oid_check("head_sha", nullable: true), name: "worktree_reservations_head_sha_format"
      table.check_constraint digest_check("observation_digest", nullable: true),
        name: "worktree_reservations_observation_digest_format"
      table.check_constraint <<~SQL.squish, name: "worktree_reservations_confirmation_shape"
        (state = 'reserved' AND git_common_dir_digest IS NULL AND head_sha IS NULL AND confirmed_at IS NULL)
        OR (state IN ('confirmed', 'release_pending', 'released') AND git_common_dir_digest IS NOT NULL
          AND head_sha IS NOT NULL AND confirmed_at IS NOT NULL)
      SQL
      table.check_constraint <<~SQL.squish, name: "worktree_reservations_observation_pair"
        (observed_state IS NULL AND observation_digest IS NULL)
        OR (observed_state IS NOT NULL AND observation_digest IS NOT NULL)
      SQL
      table.check_constraint <<~SQL.squish, name: "worktree_reservations_release_shape"
        (state <> 'released' AND released_at IS NULL)
        OR (state = 'released' AND released_at IS NOT NULL AND observed_state = 'absent')
      SQL
    end

    add_index :worktree_reservations, %i[id repository_id], unique: true
    add_index :worktree_reservations, %i[id task_id repository_id], unique: true,
      name: "index_worktree_reservations_on_identity_and_ownership"
    add_index :worktree_reservations, %i[repository_id task_id], unique: true,
      where: "state <> 'released'", name: "index_worktree_reservations_one_active_per_task"
    add_index :worktree_reservations, %i[repository_id branch], unique: true,
      where: "state <> 'released'", name: "index_worktree_reservations_active_branch"
    add_index :worktree_reservations, :path, unique: true,
      where: "state <> 'released'", name: "index_worktree_reservations_active_path"
    add_foreign_key :worktree_reservations, :workflow_attempts,
      column: %i[workflow_attempt_id task_id repository_id fencing_token],
      primary_key: %i[id task_id repository_id fencing_token]
  end

  def add_task_execution_references
    add_column :tasks, :active_attempt_id, :string
    add_column :tasks, :worktree_reservation_id, :string
    add_index :tasks, :active_attempt_id, unique: true
    add_index :tasks, :worktree_reservation_id, unique: true
    add_foreign_key :tasks, :workflow_attempts,
      column: %i[active_attempt_id id repository_id],
      primary_key: %i[id task_id repository_id]
    add_foreign_key :tasks, :worktree_reservations,
      column: %i[worktree_reservation_id id repository_id],
      primary_key: %i[id task_id repository_id]
  end

  def add_execution_triggers
    UUID_TABLES.each { |table| add_primary_key_trigger(table) }
    restore_task_triggers

    execute <<~SQL
      CREATE TRIGGER workflow_attempts_current_task_state
      BEFORE INSERT ON workflow_attempts
      WHEN NOT EXISTS (
        SELECT 1 FROM tasks
        JOIN workflow_states ON workflow_states.id = tasks.workflow_state_id
        WHERE tasks.id = NEW.task_id
          AND tasks.repository_id = NEW.repository_id
          AND tasks.workflow_state_id = NEW.workflow_state_id
          AND workflow_states.terminal = 0
      )
      BEGIN
        SELECT RAISE(ABORT, 'attempt state must be the current task state');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_monotonic_fencing
      BEFORE INSERT ON workflow_attempts
      WHEN NEW.fencing_token <> COALESCE((
        SELECT MAX(fencing_token) + 1 FROM workflow_attempts
        WHERE task_id = NEW.task_id AND repository_id = NEW.repository_id
      ), 1)
      BEGIN
        SELECT RAISE(ABORT, 'attempt fencing token must be the next task token');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_immutable_identity
      BEFORE UPDATE OF repository_id, task_id, workflow_state_id, owner_id, idempotency_key,
        fencing_token, started_at ON workflow_attempts
      BEGIN
        SELECT RAISE(ABORT, 'attempt identity is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_frozen_context
      BEFORE UPDATE OF input_context, input_context_digest ON workflow_attempts
      WHEN OLD.input_context IS NOT NULL
        AND (NEW.input_context IS NOT OLD.input_context OR NEW.input_context_digest IS NOT OLD.input_context_digest)
      BEGIN
        SELECT RAISE(ABORT, 'attempt context is immutable after finalization');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_terminal_immutable
      BEFORE UPDATE ON workflow_attempts WHEN OLD.state <> 'started'
      BEGIN
        SELECT RAISE(ABORT, 'terminal attempt is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_terminal_requires_detached_task
      BEFORE UPDATE OF state ON workflow_attempts
      WHEN NEW.state <> 'started' AND EXISTS (
        SELECT 1 FROM tasks WHERE active_attempt_id = OLD.id
      )
      BEGIN
        SELECT RAISE(ABORT, 'task must release its active attempt before completion');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_no_delete
      BEFORE DELETE ON workflow_attempts
      BEGIN
        SELECT RAISE(ABORT, 'attempt cannot be deleted');
      END;
    SQL

    execute <<~SQL
      CREATE TRIGGER idempotency_records_immutable_request
      BEFORE UPDATE OF repository_id, command, idempotency_key, request_fingerprint ON idempotency_records
      BEGIN
        SELECT RAISE(ABORT, 'idempotency request identity is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER idempotency_records_completed_immutable
      BEFORE UPDATE ON idempotency_records WHEN OLD.state = 'completed'
      BEGIN
        SELECT RAISE(ABORT, 'completed idempotency record is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER idempotency_records_no_delete
      BEFORE DELETE ON idempotency_records
      BEGIN
        SELECT RAISE(ABORT, 'idempotency record cannot be deleted');
      END;
    SQL

    execute <<~SQL
      CREATE TRIGGER task_artifacts_immutable
      BEFORE UPDATE ON task_artifacts
      BEGIN
        SELECT RAISE(ABORT, 'task artifact is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER task_artifacts_no_delete
      BEFORE DELETE ON task_artifacts
      BEGIN
        SELECT RAISE(ABORT, 'task artifact cannot be deleted');
      END;
    SQL

    execute <<~SQL
      CREATE TRIGGER worktree_reservations_task_branch
      BEFORE INSERT ON worktree_reservations
      WHEN NEW.branch <> (
        SELECT 'kos/task-' || repositories.task_prefix || '-' || printf('%06d', tasks.sequence)
        FROM tasks JOIN repositories ON repositories.id = tasks.repository_id
        WHERE tasks.id = NEW.task_id AND tasks.repository_id = NEW.repository_id
      )
      BEGIN
        SELECT RAISE(ABORT, 'reservation branch must match the task number');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER worktree_reservations_immutable_allocation
      BEFORE UPDATE OF repository_id, task_id, branch, path, created_at ON worktree_reservations
      BEGIN
        SELECT RAISE(ABORT, 'worktree reservation allocation is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER worktree_reservations_active_owner_insert
      BEFORE INSERT ON worktree_reservations
      WHEN NOT EXISTS (
        SELECT 1 FROM workflow_attempts
        WHERE id = NEW.workflow_attempt_id AND task_id = NEW.task_id
          AND repository_id = NEW.repository_id AND fencing_token = NEW.fencing_token
          AND state = 'started'
      )
      BEGIN
        SELECT RAISE(ABORT, 'reservation owner must be an active attempt');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER worktree_reservations_active_owner_update
      BEFORE UPDATE OF workflow_attempt_id, fencing_token ON worktree_reservations
      WHEN NOT EXISTS (
        SELECT 1 FROM workflow_attempts
        WHERE id = NEW.workflow_attempt_id AND task_id = NEW.task_id
          AND repository_id = NEW.repository_id AND fencing_token = NEW.fencing_token
          AND state = 'started'
      )
      BEGIN
        SELECT RAISE(ABORT, 'reservation owner must be an active attempt');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER worktree_reservations_no_delete
      BEFORE DELETE ON worktree_reservations
      BEGIN
        SELECT RAISE(ABORT, 'worktree reservation cannot be deleted');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER worktree_reservations_release_requires_detached_task
      BEFORE UPDATE OF state ON worktree_reservations
      WHEN NEW.state = 'released' AND EXISTS (
        SELECT 1 FROM tasks WHERE worktree_reservation_id = OLD.id
      )
      BEGIN
        SELECT RAISE(ABORT, 'task must release its worktree reservation pointer first');
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

  def restore_task_triggers
    add_primary_key_trigger("tasks")
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
  end

  def add_primary_key_trigger(table)
    execute <<~SQL
      CREATE TRIGGER #{table}_primary_key_immutable
      BEFORE UPDATE OF id ON #{table}
      BEGIN
        SELECT RAISE(ABORT, 'primary key is immutable');
      END;
    SQL
  end

  def command_check(column)
    <<~SQL.squish
      length(#{column}) BETWEEN 1 AND 128
      AND substr(#{column}, 1, 1) GLOB '[a-z]'
      AND #{column} NOT GLOB '*[^a-z0-9_.-]*'
    SQL
  end

  def digest_check(column, nullable: false)
    expression = <<~SQL.squish
      substr(#{column}, 1, 7) = 'sha256:'
      AND length(#{column}) = 71
      AND substr(#{column}, 8) NOT GLOB '*[^0-9a-f]*'
    SQL
    nullable ? "#{column} IS NULL OR (#{expression})" : expression
  end

  def git_oid_check(column, nullable: false)
    expression = "length(#{column}) = 40 AND #{column} NOT GLOB '*[^0-9a-f]*'"
    nullable ? "#{column} IS NULL OR (#{expression})" : expression
  end

  def identifier_check(column)
    <<~SQL.squish
      length(#{column}) BETWEEN 1 AND 128
      AND substr(#{column}, 1, 1) GLOB '[a-z]'
      AND #{column} NOT GLOB '*[^a-z0-9_-]*'
    SQL
  end

  def idempotency_key_check(column)
    <<~SQL.squish
      length(#{column}) BETWEEN 8 AND 255
      AND #{column} NOT GLOB '*[^A-Za-z0-9._:-]*'
    SQL
  end

  def json_object_check(column, nullable: false)
    expression = "json_valid(#{column}) AND json_type(#{column}) = 'object'"
    nullable ? "#{column} IS NULL OR (#{expression})" : expression
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
end
