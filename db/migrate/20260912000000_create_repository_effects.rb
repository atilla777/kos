class CreateRepositoryEffects < ActiveRecord::Migration[8.1]
  def up
    create_table :repository_effects, id: :string do |table|
      table.references :repository, type: :string, null: false, foreign_key: true
      table.string :task_id, null: false
      table.string :prepared_attempt_id, null: false
      table.string :current_owner_attempt_id, null: false
      table.string :request_digest, null: false
      table.text :request, null: false
      table.string :state, null: false, default: "prepared"
      table.text :result
      table.datetime :prepared_at, null: false
      table.datetime :reconciled_at
      table.timestamps

      table.check_constraint uuid_check("id"), name: "repository_effects_id_format"
      table.check_constraint digest_check("request_digest"), name: "repository_effects_request_digest_format"
      table.check_constraint json_object_check("request"), name: "repository_effects_request_json"
      table.check_constraint json_object_check("result", nullable: true), name: "repository_effects_result_json"
      table.check_constraint "state IN ('prepared', 'succeeded', 'failed', 'unknown')",
        name: "repository_effects_state_values"
      table.check_constraint <<~SQL.squish, name: "repository_effects_request_shape"
        json_extract(request, '$.schema_version') IS '1'
        AND json_extract(request, '$.attempt_id') IS prepared_attempt_id
        AND json_type(request, '$.input_context_digest') = 'text'
        AND substr(json_extract(request, '$.input_context_digest'), 1, 7) = 'sha256:'
        AND length(json_extract(request, '$.input_context_digest')) = 71
        AND json_extract(request, '$.effect.operation') IN ('commit', 'fetch', 'rebase')
        AND COALESCE(CASE json_extract(request, '$.effect.operation')
          WHEN 'commit' THEN
            json_type(request, '$.effect.reservation_id') = 'text'
            AND json_type(request, '$.effect.expected_head_sha') = 'text'
            AND json_type(request, '$.effect.expected_diff_digest') = 'text'
            AND json_type(request, '$.effect.expected_index_digest') = 'text'
            AND json_type(request, '$.effect.paths') = 'array'
            AND json_array_length(request, '$.effect.paths') > 0
            AND json_type(request, '$.effect.message') = 'text'
            AND length(json_extract(request, '$.effect.message')) > 0
            AND json_type(request, '$.effect.task_number') = 'text'
          WHEN 'fetch' THEN
            json_type(request, '$.effect.remote') = 'text'
            AND length(json_extract(request, '$.effect.remote')) > 0
            AND json_type(request, '$.effect.ref') = 'text'
            AND json_extract(request, '$.effect.ref') LIKE 'refs/%'
          WHEN 'rebase' THEN
            json_type(request, '$.effect.reservation_id') = 'text'
            AND json_type(request, '$.effect.expected_head_sha') = 'text'
            AND json_type(request, '$.effect.onto_sha') = 'text'
          ELSE 0
        END, 0) = 1
      SQL
      table.check_constraint <<~SQL.squish, name: "repository_effects_lifecycle_shape"
        (state = 'prepared' AND result IS NULL AND reconciled_at IS NULL)
        OR (state IN ('succeeded', 'failed', 'unknown') AND result IS NOT NULL AND reconciled_at IS NOT NULL
          AND json_extract(result, '$.result.outcome') IS state)
      SQL
      table.check_constraint <<~SQL.squish, name: "repository_effects_result_binding"
        result IS NULL OR (
          json_extract(result, '$.schema_version') IS '1'
          AND json_extract(result, '$.effect_intent_id') IS id
          AND json_extract(result, '$.request_attempt_id') IS prepared_attempt_id
          AND json_extract(result, '$.owner_attempt_id') IS current_owner_attempt_id
          AND json_extract(result, '$.input_context_digest') IS json_extract(request, '$.input_context_digest')
          AND json_extract(result, '$.effect_request_digest') IS request_digest
          AND json_extract(result, '$.result.operation') IS json_extract(request, '$.effect.operation')
          AND COALESCE(CASE json_extract(result, '$.result.outcome')
            WHEN 'succeeded' THEN CASE json_extract(result, '$.result.operation')
              WHEN 'commit' THEN json_type(result, '$.result.commit_sha') = 'text'
                AND json_type(result, '$.result.evidence_digest') = 'text'
              WHEN 'fetch' THEN json_type(result, '$.result.remote') = 'text'
                AND json_type(result, '$.result.ref') = 'text'
                AND json_type(result, '$.result.observed_oid') = 'text'
                AND json_type(result, '$.result.evidence_digest') = 'text'
              WHEN 'rebase' THEN json_type(result, '$.result.head_sha') = 'text'
                AND json_type(result, '$.result.evidence_digest') = 'text'
              ELSE 0
            END
            WHEN 'failed' THEN json_type(result, '$.result.error.category') = 'text'
              AND json_type(result, '$.result.error.code') = 'text'
              AND json_type(result, '$.result.error.message') = 'text'
              AND json_type(result, '$.result.error.retryable') IN ('true', 'false')
            WHEN 'unknown' THEN json_type(result, '$.result.error.category') = 'text'
              AND json_type(result, '$.result.error.code') = 'text'
              AND json_type(result, '$.result.error.message') = 'text'
              AND json_type(result, '$.result.error.retryable') IN ('true', 'false')
            ELSE 0
          END, 0) = 1
        )
      SQL
    end

    add_index :repository_effects, %i[id repository_id], unique: true
    add_index :repository_effects, %i[id task_id repository_id], unique: true,
      name: "index_repository_effects_on_identity_and_ownership"
    add_index :repository_effects, %i[repository_id task_id state],
      name: "index_repository_effects_on_task_and_state"
    add_index :repository_effects, %i[current_owner_attempt_id state],
      name: "index_repository_effects_on_owner_and_state"
    add_foreign_key :repository_effects, :tasks,
      column: %i[task_id repository_id], primary_key: %i[id repository_id]
    add_foreign_key :repository_effects, :workflow_attempts,
      column: %i[prepared_attempt_id task_id repository_id], primary_key: %i[id task_id repository_id]
    add_foreign_key :repository_effects, :workflow_attempts,
      column: %i[current_owner_attempt_id task_id repository_id], primary_key: %i[id task_id repository_id]

    add_triggers
  end

  def down
    execute "DROP TRIGGER IF EXISTS workflow_attempts_unresolved_effect_guard"
    execute "DROP TRIGGER IF EXISTS repository_effects_no_delete"
    execute "DROP TRIGGER IF EXISTS repository_effects_terminal_immutable"
    execute "DROP TRIGGER IF EXISTS repository_effects_lifecycle"
    execute "DROP TRIGGER IF EXISTS repository_effects_active_owner_update"
    execute "DROP TRIGGER IF EXISTS repository_effects_active_owner_insert"
    execute "DROP TRIGGER IF EXISTS repository_effects_immutable_intent"
    execute "DROP TRIGGER IF EXISTS repository_effects_primary_key_immutable"
    drop_table :repository_effects
  end

  private

  def add_triggers
    execute <<~SQL
      CREATE TRIGGER repository_effects_primary_key_immutable
      BEFORE UPDATE OF id ON repository_effects
      BEGIN
        SELECT RAISE(ABORT, 'primary key is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER repository_effects_immutable_intent
      BEFORE UPDATE OF repository_id, task_id, prepared_attempt_id, request_digest, request, prepared_at, created_at
        ON repository_effects
      BEGIN
        SELECT RAISE(ABORT, 'repository effect intent is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER repository_effects_active_owner_insert
      BEFORE INSERT ON repository_effects
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
        SELECT RAISE(ABORT, 'repository effect owner must be the preparing active attempt');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER repository_effects_active_owner_update
      BEFORE UPDATE OF current_owner_attempt_id ON repository_effects
      WHEN OLD.state NOT IN ('prepared', 'unknown') OR NOT EXISTS (
        SELECT 1 FROM workflow_attempts JOIN tasks
          ON tasks.id = workflow_attempts.task_id AND tasks.repository_id = workflow_attempts.repository_id
        WHERE workflow_attempts.id = NEW.current_owner_attempt_id AND workflow_attempts.task_id = NEW.task_id
          AND workflow_attempts.repository_id = NEW.repository_id AND workflow_attempts.state = 'started'
          AND workflow_attempts.lease_expires_at > CURRENT_TIMESTAMP
          AND tasks.active_attempt_id = workflow_attempts.id
      )
      BEGIN
        SELECT RAISE(ABORT, 'repository effect owner must be an active replacement attempt');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER repository_effects_lifecycle
      BEFORE UPDATE OF state ON repository_effects
      WHEN NOT (
        (OLD.state = 'prepared' AND NEW.state IN ('prepared', 'succeeded', 'failed', 'unknown'))
        OR (OLD.state = 'unknown' AND NEW.state IN ('succeeded', 'failed', 'unknown'))
        OR (OLD.state IN ('succeeded', 'failed') AND NEW.state = OLD.state)
      )
      BEGIN
        SELECT RAISE(ABORT, 'invalid repository effect lifecycle transition');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER repository_effects_terminal_immutable
      BEFORE UPDATE ON repository_effects
      WHEN OLD.state IN ('succeeded', 'failed')
      BEGIN
        SELECT RAISE(ABORT, 'terminal repository effect is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER repository_effects_no_delete
      BEFORE DELETE ON repository_effects
      BEGIN
        SELECT RAISE(ABORT, 'repository effect cannot be deleted');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_unresolved_effect_guard
      BEFORE UPDATE OF state ON workflow_attempts
      WHEN NEW.state IN ('succeeded', 'failed', 'needs_human') AND EXISTS (
        SELECT 1 FROM repository_effects
        WHERE current_owner_attempt_id = OLD.id AND state IN ('prepared', 'unknown')
      )
      BEGIN
        SELECT RAISE(ABORT, 'attempt cannot finish with an unresolved repository effect');
      END;
    SQL
  end

  def digest_check(column)
    <<~SQL.squish
      substr(#{column}, 1, 7) = 'sha256:'
      AND length(#{column}) = 71
      AND substr(#{column}, 8) NOT GLOB '*[^0-9a-f]*'
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
