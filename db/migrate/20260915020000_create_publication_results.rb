class CreatePublicationResults < ActiveRecord::Migration[8.1]
  def up
    add_index :task_artifacts, %i[id task_id repository_id], unique: true,
      name: "index_task_artifacts_on_identity_and_ownership"
    create_table :publication_results, id: :string do |table|
      table.references :repository, type: :string, null: false, foreign_key: true
      table.string :task_id, null: false
      table.string :publication_id, null: false
      table.string :producing_attempt_id, null: false
      table.string :input_context_digest, null: false
      table.string :candidate_sha, null: false
      table.string :remote, null: false
      table.string :base_ref, null: false
      table.string :observed_remote_tip, null: false
      table.string :observation_digest, null: false
      table.string :observed_at, null: false
      table.string :approved_review_artifact_id, null: false
      table.text :passed_test_artifact_ids, null: false
      table.text :result_manifest, null: false
      table.datetime :recorded_at, null: false
      table.timestamps

      table.check_constraint uuid_check("id"), name: "publication_results_id_format"
      table.check_constraint git_oid_check("candidate_sha"), name: "publication_results_candidate_sha_format"
      table.check_constraint git_oid_check("observed_remote_tip"), name: "publication_results_observed_tip_format"
      table.check_constraint digest_check("input_context_digest"), name: "publication_results_context_digest_format"
      table.check_constraint digest_check("observation_digest"), name: "publication_results_observation_digest_format"
      table.check_constraint "length(remote) > 0", name: "publication_results_remote_present"
      table.check_constraint "base_ref LIKE 'refs/heads/%' AND length(base_ref) > 11",
        name: "publication_results_base_ref_format"
      table.check_constraint "json_valid(result_manifest)", name: "publication_results_manifest_json"
      table.check_constraint "json_valid(passed_test_artifact_ids) AND json_array_length(passed_test_artifact_ids) > 0",
        name: "publication_results_passed_tests_shape"
      table.check_constraint <<~SQL.squish, name: "publication_results_manifest_shape"
        json_type(result_manifest, '$') IS 'object'
          AND json_extract(result_manifest, '$.schema_version') IS '1'
          AND json_extract(result_manifest, '$.outcome') IS 'succeeded'
          AND json_extract(result_manifest, '$.attempt_id') IS producing_attempt_id
          AND json_extract(result_manifest, '$.input_context_digest') IS input_context_digest
          AND json_type(result_manifest, '$.artifacts') IS 'array'
          AND json_array_length(result_manifest, '$.artifacts') IS 1
          AND json_type(result_manifest, '$.artifacts[0]') IS 'object'
          AND json_extract(result_manifest, '$.artifacts[0].schema_version') IS '1'
          AND json_extract(result_manifest, '$.artifacts[0].type') IS 'publication'
          AND json_extract(result_manifest, '$.artifacts[0].state') IS 'published'
          AND json_type(result_manifest, '$.artifacts[0].producer') IS 'text'
          AND length(json_extract(result_manifest, '$.artifacts[0].producer')) BETWEEN 1 AND 128
          AND substr(json_extract(result_manifest, '$.artifacts[0].producer'), 1, 1) GLOB '[a-z]'
          AND json_extract(result_manifest, '$.artifacts[0].producer') NOT GLOB '*[^a-z0-9_-]*'
          AND json_type(result_manifest, '$.artifacts[0].metadata') IS 'object'
          AND json_extract(result_manifest, '$.artifacts[0].metadata.kind') IS 'publication'
          AND json_extract(result_manifest, '$.artifacts[0].metadata.publication_id') IS publication_id
          AND json_extract(result_manifest, '$.artifacts[0].metadata.candidate_sha') IS candidate_sha
          AND json_extract(result_manifest, '$.artifacts[0].metadata.remote') IS remote
          AND json_extract(result_manifest, '$.artifacts[0].metadata.base_ref') IS base_ref
          AND json_extract(result_manifest, '$.artifacts[0].metadata.observed_remote_tip') IS observed_remote_tip
          AND json_extract(result_manifest, '$.artifacts[0].metadata.reachable') IS 1
          AND json_type(result_manifest, '$.artifacts[0].metadata.observed_at') IS 'text'
          AND json_extract(result_manifest, '$.artifacts[0].metadata.observed_at') IS observed_at
          AND (json_type(result_manifest, '$.summary') IS NULL
            OR (json_type(result_manifest, '$.summary') IS 'text'
              AND length(json_extract(result_manifest, '$.summary')) > 0))
      SQL
    end

    add_index :publication_results, :publication_id, unique: true
    add_index :publication_results, %i[id repository_id], unique: true
    add_index :publication_results, %i[id task_id repository_id], unique: true,
      name: "index_publication_results_on_identity_and_ownership"
    add_foreign_key :publication_results, :tasks,
      column: %i[task_id repository_id], primary_key: %i[id repository_id]
    add_foreign_key :publication_results, :publications,
      column: %i[publication_id task_id repository_id], primary_key: %i[id task_id repository_id]
    add_foreign_key :publication_results, :workflow_attempts,
      column: %i[producing_attempt_id task_id repository_id], primary_key: %i[id task_id repository_id]
    add_foreign_key :publication_results, :task_artifacts,
      column: %i[approved_review_artifact_id task_id repository_id], primary_key: %i[id task_id repository_id]
    add_triggers
  end

  def down
    execute "DROP TRIGGER IF EXISTS worktree_release_requires_publication_result"
    execute "DROP TRIGGER IF EXISTS publication_observation_after_result"
    execute "DROP TRIGGER IF EXISTS publication_results_valid_insert"
    execute "DROP TRIGGER IF EXISTS publication_results_no_delete"
    execute "DROP TRIGGER IF EXISTS publication_results_immutable"
    drop_table :publication_results
    remove_index :task_artifacts, name: "index_task_artifacts_on_identity_and_ownership"
  end

  private

  def add_triggers
    execute <<~SQL
      CREATE TRIGGER publication_results_immutable
      BEFORE UPDATE ON publication_results
      BEGIN
        SELECT RAISE(ABORT, 'publication result is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publication_results_no_delete
      BEFORE DELETE ON publication_results
      BEGIN
        SELECT RAISE(ABORT, 'publication result cannot be deleted');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publication_results_valid_insert
      BEFORE INSERT ON publication_results
      WHEN NOT EXISTS (
        SELECT 1 FROM publications p
        JOIN tasks t ON t.id = p.task_id AND t.repository_id = p.repository_id
        JOIN workflow_attempts a ON a.id = NEW.producing_attempt_id
          AND a.task_id = p.task_id AND a.repository_id = p.repository_id
        WHERE p.id = NEW.publication_id AND p.task_id = NEW.task_id
          AND p.repository_id = NEW.repository_id AND p.state = 'reconciled'
          AND p.candidate_reachable = 1 AND p.current_owner_attempt_id = a.id
          AND p.observation_owner_attempt_id = a.id AND p.candidate_sha = NEW.candidate_sha
          AND p.remote = NEW.remote AND p.base_ref = NEW.base_ref
          AND p.observed_remote_tip = NEW.observed_remote_tip
          AND p.observation_digest = NEW.observation_digest
          AND NEW.observed_at IS substr(replace(p.observed_at, ' ', 'T') || '.000000', 1, 26) || 'Z'
          AND t.active_publication_id = p.id AND t.active_attempt_id = a.id
          AND a.state = 'started' AND a.lease_expires_at > CURRENT_TIMESTAMP
          AND a.input_context_digest = NEW.input_context_digest AND a.input_context IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM json_each(NEW.result_manifest)
            WHERE key NOT IN ('schema_version', 'attempt_id', 'input_context_digest', 'outcome', 'artifacts', 'summary')
          )
          AND NOT EXISTS (
            SELECT 1 FROM json_each(NEW.result_manifest, '$.artifacts[0]')
            WHERE key NOT IN ('schema_version', 'type', 'state', 'producer', 'metadata')
          )
          AND NOT EXISTS (
            SELECT 1 FROM json_each(NEW.result_manifest, '$.artifacts[0].metadata')
            WHERE key NOT IN ('kind', 'publication_id', 'candidate_sha', 'remote', 'base_ref',
              'observed_remote_tip', 'reachable', 'observed_at')
          )
          AND (SELECT COUNT(*) FROM json_each(NEW.passed_test_artifact_ids)) =
            (SELECT COUNT(DISTINCT value) FROM json_each(NEW.passed_test_artifact_ids))
          AND EXISTS (
            SELECT 1 FROM task_artifacts candidate JOIN workflow_attempts candidate_attempt
              ON candidate_attempt.id = candidate.workflow_attempt_id
            WHERE candidate.task_id = t.id AND candidate.repository_id = t.repository_id
              AND candidate.artifact_type = 'candidate' AND candidate.state = 'produced'
              AND candidate_attempt.state = 'succeeded'
              AND json_extract(candidate.metadata, '$.candidate_sha') = NEW.candidate_sha
              AND NOT EXISTS (
                SELECT 1 FROM task_artifacts newer JOIN workflow_attempts newer_attempt
                  ON newer_attempt.id = newer.workflow_attempt_id
                WHERE newer.task_id = t.id AND newer.artifact_type = 'candidate'
                  AND newer_attempt.state = 'succeeded'
                  AND newer_attempt.fencing_token > candidate_attempt.fencing_token
              )
          )
          AND EXISTS (
            SELECT 1 FROM task_artifacts test JOIN workflow_attempts test_attempt
              ON test_attempt.id = test.workflow_attempt_id
            WHERE test.task_id = t.id AND test.repository_id = t.repository_id
              AND test.artifact_type = 'test' AND test.state = 'passed'
              AND test_attempt.state = 'succeeded'
              AND json_extract(test.metadata, '$.candidate_sha') = NEW.candidate_sha
              AND json_extract(test.metadata, '$.exit_code') = 0
              AND test.id IN (SELECT value FROM json_each(NEW.passed_test_artifact_ids))
          )
          AND NOT EXISTS (
            SELECT 1 FROM json_each(NEW.passed_test_artifact_ids) ids
            WHERE NOT EXISTS (
              SELECT 1 FROM task_artifacts test JOIN workflow_attempts test_attempt
                ON test_attempt.id = test.workflow_attempt_id
              WHERE test.id = ids.value AND test.task_id = t.id AND test.repository_id = t.repository_id
                AND test.artifact_type = 'test' AND test.state = 'passed' AND test_attempt.state = 'succeeded'
                AND json_extract(test.metadata, '$.candidate_sha') = NEW.candidate_sha
                AND json_extract(test.metadata, '$.exit_code') = 0
            )
          )
          AND EXISTS (
            SELECT 1 FROM task_artifacts review JOIN workflow_attempts review_attempt
              ON review_attempt.id = review.workflow_attempt_id
            JOIN workflow_transitions transition ON transition.id = review_attempt.completed_transition_id
            WHERE review.task_id = t.id AND review.repository_id = t.repository_id
              AND review.artifact_type = 'review' AND review.state = 'approved'
              AND review_attempt.state = 'succeeded' AND transition.to_state_id = t.workflow_state_id
              AND review.id = NEW.approved_review_artifact_id
              AND json_extract(review.metadata, '$.candidate_sha') = NEW.candidate_sha
              AND json_extract(review.metadata, '$.review_attempt_id') = review_attempt.id
          )
      )
      BEGIN
        SELECT RAISE(ABORT, 'publication result does not match active verified publication');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER publication_observation_after_result
      BEFORE UPDATE OF observation_owner_attempt_id, observed_remote_tip, candidate_reachable,
        observation_digest, observed_at, reconciled_at ON publications
      WHEN EXISTS (SELECT 1 FROM publication_results WHERE publication_id = OLD.id)
      BEGIN
        SELECT RAISE(ABORT, 'publication observation is immutable after its result');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER worktree_release_requires_publication_result
      BEFORE UPDATE OF state ON worktree_reservations
      WHEN OLD.state = 'confirmed' AND NEW.state = 'release_pending'
        AND EXISTS (
          SELECT 1 FROM tasks JOIN workflow_states ON workflow_states.id = tasks.workflow_state_id
          WHERE tasks.id = NEW.task_id AND workflow_states.identifier = 'publication'
        )
        AND NOT EXISTS (
          SELECT 1 FROM publication_results result JOIN tasks task
            ON task.id = result.task_id AND task.repository_id = result.repository_id
          WHERE task.id = NEW.task_id AND result.repository_id = NEW.repository_id
            AND result.publication_id = task.active_publication_id AND result.candidate_sha = NEW.head_sha
        )
      BEGIN
        SELECT RAISE(ABORT, 'publication result is required before worktree release');
      END;
    SQL
  end

  def uuid_check(column)
    "length(#{column}) = 36 AND substr(#{column}, 9, 1) = '-' AND substr(#{column}, 14, 1) = '-' " \
      "AND substr(#{column}, 19, 1) = '-' AND substr(#{column}, 24, 1) = '-' " \
      "AND length(replace(#{column}, '-', '')) = 32 AND replace(#{column}, '-', '') NOT GLOB '*[^0-9a-f]*'"
  end

  def git_oid_check(column)
    "length(#{column}) = 40 AND #{column} NOT GLOB '*[^0-9a-f]*'"
  end

  def digest_check(column)
    "substr(#{column}, 1, 7) = 'sha256:' AND length(#{column}) = 71 " \
      "AND substr(#{column}, 8) NOT GLOB '*[^0-9a-f]*'"
  end
end
