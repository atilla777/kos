CREATE TABLE "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE "repositories" ("id" varchar NOT NULL PRIMARY KEY, "git_common_dir" varchar NOT NULL, "task_prefix" varchar NOT NULL, "trusted_remote" varchar NOT NULL, "trusted_remote_url" varchar NOT NULL, "base_ref" varchar NOT NULL, "next_task_sequence" integer DEFAULT 1 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT repositories_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT repositories_git_common_dir_absolute CHECK (git_common_dir LIKE '/%'), CONSTRAINT repositories_task_prefix_format CHECK (length(task_prefix) BETWEEN 2 AND 10 AND substr(task_prefix, 1, 1) GLOB '[A-Z]' AND task_prefix NOT GLOB '*[^A-Z0-9]*'), CONSTRAINT repositories_base_ref_format CHECK (base_ref LIKE 'refs/heads/%'), CONSTRAINT repositories_next_task_sequence_range CHECK (next_task_sequence BETWEEN 1 AND 1000000));
CREATE UNIQUE INDEX "index_repositories_on_git_common_dir" ON "repositories" ("git_common_dir");
CREATE UNIQUE INDEX "index_repositories_on_task_prefix" ON "repositories" ("task_prefix");
CREATE TABLE "workflow_states" ("id" varchar NOT NULL PRIMARY KEY, "workflow_version_id" varchar NOT NULL, "identifier" varchar NOT NULL, "initial" boolean DEFAULT FALSE NOT NULL, "terminal" boolean DEFAULT FALSE NOT NULL, "execution_mode" varchar, "instruction" text, "worktree_policy" varchar, "repository_changes_policy" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_1f82715b36"
FOREIGN KEY ("workflow_version_id")
  REFERENCES "workflow_versions" ("id")
, CONSTRAINT workflow_states_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT workflow_states_identifier_format CHECK (length(identifier) BETWEEN 1 AND 128 AND substr(identifier, 1, 1) GLOB '[a-z]' AND identifier NOT GLOB '*[^a-z0-9_-]*'), CONSTRAINT workflow_states_boolean_values CHECK (initial IN (0, 1) AND terminal IN (0, 1)), CONSTRAINT workflow_states_execution_shape CHECK ((terminal = 1 AND initial = 0 AND execution_mode IS NULL AND instruction IS NULL AND worktree_policy IS NULL AND repository_changes_policy IS NULL) OR (terminal = 0 AND execution_mode IN ('main_session', 'subagent') AND length(instruction) > 0 AND worktree_policy IN ('required', 'none') AND repository_changes_policy IN ('allowed', 'forbidden'))));
CREATE INDEX "index_workflow_states_on_workflow_version_id" ON "workflow_states" ("workflow_version_id");
CREATE UNIQUE INDEX "index_workflow_states_on_workflow_version_id_and_identifier" ON "workflow_states" ("workflow_version_id", "identifier");
CREATE UNIQUE INDEX "index_workflow_states_on_id_and_workflow_version_id" ON "workflow_states" ("id", "workflow_version_id");
CREATE UNIQUE INDEX "index_workflow_states_one_initial" ON "workflow_states" ("workflow_version_id") WHERE initial = 1;
CREATE UNIQUE INDEX "index_workflow_states_one_terminal" ON "workflow_states" ("workflow_version_id") WHERE terminal = 1;
CREATE TABLE "artifact_templates" ("id" varchar NOT NULL PRIMARY KEY, "workflow_state_id" varchar NOT NULL, "identifier" varchar NOT NULL, "media_type" varchar NOT NULL, "content" text NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_6392249d8a"
FOREIGN KEY ("workflow_state_id")
  REFERENCES "workflow_states" ("id")
, CONSTRAINT artifact_templates_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT artifact_templates_identifier_format CHECK (length(identifier) BETWEEN 1 AND 128 AND substr(identifier, 1, 1) GLOB '[a-z]' AND identifier NOT GLOB '*[^a-z0-9_-]*'), CONSTRAINT artifact_templates_media_type CHECK (media_type = 'text/markdown; charset=utf-8'), CONSTRAINT artifact_templates_content_present CHECK (length(content) > 0));
CREATE INDEX "index_artifact_templates_on_workflow_state_id" ON "artifact_templates" ("workflow_state_id");
CREATE UNIQUE INDEX "index_artifact_templates_on_workflow_state_id_and_identifier" ON "artifact_templates" ("workflow_state_id", "identifier");
CREATE TABLE "workflow_state_effects" ("id" varchar NOT NULL PRIMARY KEY, "workflow_state_id" varchar NOT NULL, "effect" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_cc1dbc9916"
FOREIGN KEY ("workflow_state_id")
  REFERENCES "workflow_states" ("id")
, CONSTRAINT workflow_state_effects_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT workflow_state_effects_effect_values CHECK (effect IN ('worktree_remove', 'commit', 'fetch', 'rebase', 'push')));
CREATE INDEX "index_workflow_state_effects_on_workflow_state_id" ON "workflow_state_effects" ("workflow_state_id");
CREATE UNIQUE INDEX "index_workflow_state_effects_on_workflow_state_id_and_effect" ON "workflow_state_effects" ("workflow_state_id", "effect");
CREATE TABLE "artifact_requirements" ("id" varchar NOT NULL PRIMARY KEY, "workflow_state_id" varchar NOT NULL, "artifact_type" varchar NOT NULL, "cardinality" varchar NOT NULL, "subject" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_f3153db9bc"
FOREIGN KEY ("workflow_state_id")
  REFERENCES "workflow_states" ("id")
, CONSTRAINT artifact_requirements_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT artifact_requirements_type_values CHECK (artifact_type IN ('document', 'candidate', 'test', 'review', 'publication')), CONSTRAINT artifact_requirements_cardinality_values CHECK (cardinality IN ('one', 'many')), CONSTRAINT artifact_requirements_subject_values CHECK (subject IN ('task', 'candidate')));
CREATE INDEX "index_artifact_requirements_on_workflow_state_id" ON "artifact_requirements" ("workflow_state_id");
CREATE UNIQUE INDEX "idx_on_workflow_state_id_artifact_type_d3f4ece954" ON "artifact_requirements" ("workflow_state_id", "artifact_type");
CREATE TABLE "artifact_requirement_states" ("id" varchar NOT NULL PRIMARY KEY, "artifact_requirement_id" varchar NOT NULL, "state" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_273fd0aa79"
FOREIGN KEY ("artifact_requirement_id")
  REFERENCES "artifact_requirements" ("id")
, CONSTRAINT artifact_requirement_states_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT artifact_requirement_states_state_values CHECK (state IN ('produced', 'passed', 'failed', 'approved', 'changes_requested', 'published')));
CREATE UNIQUE INDEX "index_artifact_requirement_states_uniqueness" ON "artifact_requirement_states" ("artifact_requirement_id", "state");
CREATE TABLE "workflow_transition_conditions" ("id" varchar NOT NULL PRIMARY KEY, "workflow_transition_id" varchar NOT NULL, "position" integer NOT NULL, "condition_type" varchar NOT NULL, "artifact_type" varchar, "artifact_state" varchar, "decision" varchar, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_8ca3c1ed0f"
FOREIGN KEY ("workflow_transition_id")
  REFERENCES "workflow_transitions" ("id")
, CONSTRAINT workflow_transition_conditions_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT workflow_transition_conditions_position_nonnegative CHECK (position >= 0), CONSTRAINT workflow_transition_conditions_artifact_values CHECK (artifact_type IS NULL OR artifact_type IN ('document', 'candidate', 'test', 'review', 'publication')), CONSTRAINT workflow_transition_conditions_artifact_state_values CHECK (artifact_state IS NULL OR artifact_state IN ('produced', 'passed', 'failed', 'approved', 'changes_requested', 'published')), CONSTRAINT workflow_transition_conditions_decision_format CHECK (decision IS NULL OR (length(decision) BETWEEN 1 AND 128 AND substr(decision, 1, 1) GLOB '[a-z]' AND decision NOT GLOB '*[^a-z0-9_-]*')), CONSTRAINT workflow_transition_conditions_value_format CHECK (value IS NULL OR (length(value) BETWEEN 1 AND 128 AND substr(value, 1, 1) GLOB '[a-z]' AND value NOT GLOB '*[^a-z0-9_-]*')), CONSTRAINT workflow_transition_conditions_shape CHECK ((condition_type = 'always' AND artifact_type IS NULL AND artifact_state IS NULL AND decision IS NULL AND value IS NULL) OR (condition_type IN ('artifact-present', 'not-applicable') AND artifact_type IS NOT NULL AND artifact_state IS NULL AND decision IS NULL AND value IS NULL) OR (condition_type = 'artifact-state' AND artifact_type IS NOT NULL AND artifact_state IS NOT NULL AND decision IS NULL AND value IS NULL) OR (condition_type = 'decision' AND artifact_type IS NULL AND artifact_state IS NULL AND decision IS NOT NULL AND value IS NOT NULL)));
CREATE UNIQUE INDEX "index_workflow_transition_conditions_position" ON "workflow_transition_conditions" ("workflow_transition_id", "position");
CREATE TABLE "workflow_drafts" ("id" varchar NOT NULL PRIMARY KEY, "task_type_id" varchar NOT NULL, "workflow_id" varchar NOT NULL, "definition" text NOT NULL, "lock_version" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_19d0fc73f6"
FOREIGN KEY ("task_type_id", "workflow_id")
  REFERENCES "task_types" ("id", "workflow_id")
, CONSTRAINT workflow_drafts_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT workflow_drafts_definition_json CHECK (json_valid(definition)), CONSTRAINT workflow_drafts_lock_version_nonnegative CHECK (lock_version >= 0));
CREATE UNIQUE INDEX "index_workflow_drafts_on_workflow_id" ON "workflow_drafts" ("workflow_id");
CREATE UNIQUE INDEX "index_workflow_drafts_on_task_type_id_and_workflow_id" ON "workflow_drafts" ("task_type_id", "workflow_id");
CREATE TABLE "workflow_versions" ("id" varchar NOT NULL PRIMARY KEY, "task_type_id" varchar NOT NULL, "workflow_id" varchar NOT NULL, "version" varchar NOT NULL, "content_digest" varchar NOT NULL, "published_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_e5334bba6f"
FOREIGN KEY ("task_type_id", "workflow_id")
  REFERENCES "task_types" ("id", "workflow_id")
, CONSTRAINT workflow_versions_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT workflow_versions_digest_format CHECK (substr(content_digest, 1, 7) = 'sha256:' AND length(content_digest) = 71 AND substr(content_digest, 8) NOT GLOB '*[^0-9a-f]*'));
CREATE UNIQUE INDEX "index_workflow_versions_on_workflow_id_and_version" ON "workflow_versions" ("workflow_id", "version");
CREATE UNIQUE INDEX "index_workflow_versions_on_id_and_task_type_id" ON "workflow_versions" ("id", "task_type_id");
CREATE TABLE "task_types" ("id" varchar NOT NULL PRIMARY KEY, "name" varchar NOT NULL, "workflow_id" varchar NOT NULL, "current_workflow_version_id" varchar, "lock_version" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_6ed5caed03"
FOREIGN KEY ("current_workflow_version_id")
  REFERENCES "workflow_versions" ("id")
, CONSTRAINT task_types_id_format CHECK (length(id) BETWEEN 1 AND 128 AND substr(id, 1, 1) GLOB '[a-z]' AND id NOT GLOB '*[^a-z0-9_-]*'), CONSTRAINT task_types_name_format CHECK (length(name) BETWEEN 1 AND 128 AND substr(name, 1, 1) GLOB '[a-z]' AND name NOT GLOB '*[^a-z0-9_-]*'), CONSTRAINT task_types_workflow_id_format CHECK (length(workflow_id) BETWEEN 1 AND 128 AND substr(workflow_id, 1, 1) GLOB '[a-z]' AND workflow_id NOT GLOB '*[^a-z0-9_-]*'), CONSTRAINT task_types_lock_version_nonnegative CHECK (lock_version >= 0));
CREATE UNIQUE INDEX "index_task_types_on_name" ON "task_types" ("name");
CREATE UNIQUE INDEX "index_task_types_on_workflow_id" ON "task_types" ("workflow_id");
CREATE UNIQUE INDEX "index_task_types_on_id_and_workflow_id" ON "task_types" ("id", "workflow_id");
CREATE TABLE "workflow_transitions" ("id" varchar NOT NULL PRIMARY KEY, "workflow_version_id" varchar NOT NULL, "from_state_id" varchar NOT NULL, "to_state_id" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_bf49e0b50d"
FOREIGN KEY ("from_state_id", "workflow_version_id")
  REFERENCES "workflow_states" ("id", "workflow_version_id")
, CONSTRAINT "fk_rails_bfc26274cc"
FOREIGN KEY ("workflow_version_id")
  REFERENCES "workflow_versions" ("id")
, CONSTRAINT "fk_rails_9293f3d93c"
FOREIGN KEY ("to_state_id", "workflow_version_id")
  REFERENCES "workflow_states" ("id", "workflow_version_id")
, CONSTRAINT workflow_transitions_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT workflow_transitions_distinct_states CHECK (from_state_id <> to_state_id));
CREATE INDEX "index_workflow_transitions_on_workflow_version_id" ON "workflow_transitions" ("workflow_version_id");
CREATE UNIQUE INDEX "index_workflow_transitions_uniqueness" ON "workflow_transitions" ("workflow_version_id", "from_state_id", "to_state_id");
CREATE TRIGGER task_types_primary_key_immutable
BEFORE UPDATE OF id ON task_types
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER workflow_states_primary_key_immutable
BEFORE UPDATE OF id ON workflow_states
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER artifact_templates_primary_key_immutable
BEFORE UPDATE OF id ON artifact_templates
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER workflow_state_effects_primary_key_immutable
BEFORE UPDATE OF id ON workflow_state_effects
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER artifact_requirements_primary_key_immutable
BEFORE UPDATE OF id ON artifact_requirements
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER artifact_requirement_states_primary_key_immutable
BEFORE UPDATE OF id ON artifact_requirement_states
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER workflow_transitions_primary_key_immutable
BEFORE UPDATE OF id ON workflow_transitions
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER workflow_transition_conditions_primary_key_immutable
BEFORE UPDATE OF id ON workflow_transition_conditions
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER repositories_primary_key_immutable
BEFORE UPDATE OF id ON repositories
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER workflow_drafts_primary_key_immutable
BEFORE UPDATE OF id ON workflow_drafts
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER workflow_versions_primary_key_immutable
BEFORE UPDATE OF id ON workflow_versions
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER repositories_immutable_registration
BEFORE UPDATE OF git_common_dir, task_prefix, trusted_remote, trusted_remote_url, base_ref ON repositories
BEGIN
  SELECT RAISE(ABORT, 'repository registration is immutable');
END;
CREATE TRIGGER repositories_no_delete
BEFORE DELETE ON repositories
BEGIN
  SELECT RAISE(ABORT, 'repository registration cannot be deleted');
END;
CREATE TRIGGER workflow_versions_immutable
BEFORE UPDATE ON workflow_versions WHEN OLD.published_at IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow version is immutable');
END;
CREATE TRIGGER workflow_versions_no_delete
BEFORE DELETE ON workflow_versions WHEN OLD.published_at IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow version cannot be deleted');
END;
CREATE TRIGGER workflow_states_published_no_insert
BEFORE INSERT ON workflow_states WHEN (SELECT published_at FROM workflow_versions WHERE id = NEW.workflow_version_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER workflow_states_published_no_update
BEFORE UPDATE ON workflow_states
WHEN (SELECT published_at FROM workflow_versions WHERE id = OLD.workflow_version_id) IS NOT NULL
  OR (SELECT published_at FROM workflow_versions WHERE id = NEW.workflow_version_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER workflow_states_published_no_delete
BEFORE DELETE ON workflow_states WHEN (SELECT published_at FROM workflow_versions WHERE id = OLD.workflow_version_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER artifact_templates_published_no_insert
BEFORE INSERT ON artifact_templates WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id WHERE workflow_states.id = NEW.workflow_state_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER artifact_templates_published_no_update
BEFORE UPDATE ON artifact_templates
WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id WHERE workflow_states.id = OLD.workflow_state_id) IS NOT NULL
  OR (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id WHERE workflow_states.id = NEW.workflow_state_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER artifact_templates_published_no_delete
BEFORE DELETE ON artifact_templates WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id WHERE workflow_states.id = OLD.workflow_state_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER workflow_state_effects_published_no_insert
BEFORE INSERT ON workflow_state_effects WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id WHERE workflow_states.id = NEW.workflow_state_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER workflow_state_effects_published_no_update
BEFORE UPDATE ON workflow_state_effects
WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id WHERE workflow_states.id = OLD.workflow_state_id) IS NOT NULL
  OR (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id WHERE workflow_states.id = NEW.workflow_state_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER workflow_state_effects_published_no_delete
BEFORE DELETE ON workflow_state_effects WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id WHERE workflow_states.id = OLD.workflow_state_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER artifact_requirements_published_no_insert
BEFORE INSERT ON artifact_requirements WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id WHERE workflow_states.id = NEW.workflow_state_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER artifact_requirements_published_no_update
BEFORE UPDATE ON artifact_requirements
WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id WHERE workflow_states.id = OLD.workflow_state_id) IS NOT NULL
  OR (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id WHERE workflow_states.id = NEW.workflow_state_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER artifact_requirements_published_no_delete
BEFORE DELETE ON artifact_requirements WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id WHERE workflow_states.id = OLD.workflow_state_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER artifact_requirement_states_published_no_insert
BEFORE INSERT ON artifact_requirement_states WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id JOIN artifact_requirements ON artifact_requirements.workflow_state_id = workflow_states.id WHERE artifact_requirements.id = NEW.artifact_requirement_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER artifact_requirement_states_published_no_update
BEFORE UPDATE ON artifact_requirement_states
WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id JOIN artifact_requirements ON artifact_requirements.workflow_state_id = workflow_states.id WHERE artifact_requirements.id = OLD.artifact_requirement_id) IS NOT NULL
  OR (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id JOIN artifact_requirements ON artifact_requirements.workflow_state_id = workflow_states.id WHERE artifact_requirements.id = NEW.artifact_requirement_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER artifact_requirement_states_published_no_delete
BEFORE DELETE ON artifact_requirement_states WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id JOIN artifact_requirements ON artifact_requirements.workflow_state_id = workflow_states.id WHERE artifact_requirements.id = OLD.artifact_requirement_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER workflow_transitions_published_no_insert
BEFORE INSERT ON workflow_transitions WHEN (SELECT published_at FROM workflow_versions WHERE id = NEW.workflow_version_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER workflow_transitions_published_no_update
BEFORE UPDATE ON workflow_transitions
WHEN (SELECT published_at FROM workflow_versions WHERE id = OLD.workflow_version_id) IS NOT NULL
  OR (SELECT published_at FROM workflow_versions WHERE id = NEW.workflow_version_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER workflow_transitions_published_no_delete
BEFORE DELETE ON workflow_transitions WHEN (SELECT published_at FROM workflow_versions WHERE id = OLD.workflow_version_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER workflow_transition_conditions_published_no_insert
BEFORE INSERT ON workflow_transition_conditions WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_transitions ON workflow_transitions.workflow_version_id = workflow_versions.id WHERE workflow_transitions.id = NEW.workflow_transition_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER workflow_transition_conditions_published_no_update
BEFORE UPDATE ON workflow_transition_conditions
WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_transitions ON workflow_transitions.workflow_version_id = workflow_versions.id WHERE workflow_transitions.id = OLD.workflow_transition_id) IS NOT NULL
  OR (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_transitions ON workflow_transitions.workflow_version_id = workflow_versions.id WHERE workflow_transitions.id = NEW.workflow_transition_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER workflow_transition_conditions_published_no_delete
BEFORE DELETE ON workflow_transition_conditions WHEN (SELECT workflow_versions.published_at FROM workflow_versions JOIN workflow_transitions ON workflow_transitions.workflow_version_id = workflow_versions.id WHERE workflow_transitions.id = OLD.workflow_transition_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'published workflow content is immutable');
END;
CREATE TRIGGER task_types_initial_current_version_must_be_published
BEFORE INSERT ON task_types
WHEN NEW.current_workflow_version_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM workflow_versions
    WHERE id = NEW.current_workflow_version_id
      AND task_type_id = NEW.id
      AND published_at IS NOT NULL
  )
BEGIN
  SELECT RAISE(ABORT, 'current workflow version must be published for this task type');
END;
CREATE TRIGGER task_types_current_version_must_be_published
BEFORE UPDATE OF current_workflow_version_id ON task_types
WHEN NEW.current_workflow_version_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM workflow_versions
    WHERE id = NEW.current_workflow_version_id
      AND task_type_id = NEW.id
      AND published_at IS NOT NULL
  )
BEGIN
  SELECT RAISE(ABORT, 'current workflow version must be published for this task type');
END;
CREATE TRIGGER workflow_transitions_same_version
BEFORE INSERT ON workflow_transitions
WHEN NOT EXISTS (
  SELECT 1
  FROM workflow_states source, workflow_states target
  WHERE source.id = NEW.from_state_id
    AND target.id = NEW.to_state_id
    AND source.workflow_version_id = NEW.workflow_version_id
    AND target.workflow_version_id = NEW.workflow_version_id
    AND source.terminal = 0
)
BEGIN
  SELECT RAISE(ABORT, 'transition states must belong to its workflow version');
END;
CREATE TRIGGER workflow_transitions_update_same_version
BEFORE UPDATE OF workflow_version_id, from_state_id, to_state_id ON workflow_transitions
WHEN NOT EXISTS (
  SELECT 1
  FROM workflow_states source, workflow_states target
  WHERE source.id = NEW.from_state_id
    AND target.id = NEW.to_state_id
    AND source.workflow_version_id = NEW.workflow_version_id
    AND target.workflow_version_id = NEW.workflow_version_id
    AND source.terminal = 0
)
BEGIN
  SELECT RAISE(ABORT, 'transition states must belong to its workflow version');
END;
CREATE TABLE "idempotency_records" ("id" varchar NOT NULL PRIMARY KEY, "repository_id" varchar, "command" varchar NOT NULL, "idempotency_key" varchar NOT NULL, "request_fingerprint" varchar NOT NULL, "state" varchar DEFAULT 'in_progress' NOT NULL, "intent_resource_type" varchar, "intent_resource_id" varchar, "response_status" integer, "response_data" text, "completed_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_5301cd746c"
FOREIGN KEY ("repository_id")
  REFERENCES "repositories" ("id")
, CONSTRAINT idempotency_records_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT idempotency_records_command_format CHECK (length(command) BETWEEN 1 AND 128 AND substr(command, 1, 1) GLOB '[a-z]' AND command NOT GLOB '*[^a-z0-9_.-]*'), CONSTRAINT idempotency_records_key_format CHECK (length(idempotency_key) BETWEEN 8 AND 255 AND idempotency_key NOT GLOB '*[^A-Za-z0-9._:-]*'), CONSTRAINT idempotency_records_fingerprint_format CHECK (substr(request_fingerprint, 1, 7) = 'sha256:' AND length(request_fingerprint) = 71 AND substr(request_fingerprint, 8) NOT GLOB '*[^0-9a-f]*'), CONSTRAINT idempotency_records_state_values CHECK (state IN ('in_progress', 'completed')), CONSTRAINT idempotency_records_intent_type_format CHECK (intent_resource_type IS NULL OR (length(intent_resource_type) BETWEEN 1 AND 128 AND substr(intent_resource_type, 1, 1) GLOB '[a-z]' AND intent_resource_type NOT GLOB '*[^a-z0-9_-]*')), CONSTRAINT idempotency_records_intent_id_format CHECK (intent_resource_id IS NULL OR (length(intent_resource_id) = 36 AND substr(intent_resource_id, 9, 1) = '-' AND substr(intent_resource_id, 14, 1) = '-' AND substr(intent_resource_id, 19, 1) = '-' AND substr(intent_resource_id, 24, 1) = '-' AND length(replace(intent_resource_id, '-', '')) = 32 AND replace(intent_resource_id, '-', '') NOT GLOB '*[^0-9a-f]*')), CONSTRAINT idempotency_records_response_data_json CHECK (response_data IS NULL OR (json_valid(response_data) AND json_type(response_data) = 'object')), CONSTRAINT idempotency_records_lifecycle_shape CHECK ((state = 'in_progress' AND intent_resource_type IS NOT NULL AND intent_resource_id IS NOT NULL AND response_status IS NULL AND response_data IS NULL AND completed_at IS NULL) OR (state = 'completed' AND intent_resource_type IS NULL AND intent_resource_id IS NULL AND response_status IS NOT NULL AND response_status BETWEEN 100 AND 599 AND response_data IS NOT NULL AND completed_at IS NOT NULL)));
CREATE INDEX "index_idempotency_records_on_repository_id" ON "idempotency_records" ("repository_id");
CREATE UNIQUE INDEX "index_idempotency_records_global_uniqueness" ON "idempotency_records" ("command", "idempotency_key") WHERE repository_id IS NULL;
CREATE UNIQUE INDEX "index_idempotency_records_repository_uniqueness" ON "idempotency_records" ("repository_id", "command", "idempotency_key") WHERE repository_id IS NOT NULL;
CREATE TABLE "task_artifacts" ("id" varchar NOT NULL PRIMARY KEY, "repository_id" varchar NOT NULL, "task_id" varchar NOT NULL, "workflow_attempt_id" varchar NOT NULL, "artifact_type" varchar NOT NULL, "state" varchar NOT NULL, "producer" varchar NOT NULL, "metadata" text NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_ceb8cd3b46"
FOREIGN KEY ("repository_id")
  REFERENCES "repositories" ("id")
, CONSTRAINT "fk_rails_e7be00fdcc"
FOREIGN KEY ("workflow_attempt_id", "task_id", "repository_id")
  REFERENCES "workflow_attempts" ("id", "task_id", "repository_id")
, CONSTRAINT task_artifacts_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT task_artifacts_producer_format CHECK (length(producer) BETWEEN 1 AND 128 AND substr(producer, 1, 1) GLOB '[a-z]' AND producer NOT GLOB '*[^a-z0-9_-]*'), CONSTRAINT task_artifacts_metadata_json CHECK (json_valid(metadata) AND json_type(metadata) = 'object'), CONSTRAINT task_artifacts_type_state_pair CHECK ((artifact_type IN ('document', 'candidate') AND state = 'produced') OR (artifact_type = 'test' AND state IN ('passed', 'failed')) OR (artifact_type = 'review' AND state IN ('approved', 'changes_requested')) OR (artifact_type = 'publication' AND state = 'published')), CONSTRAINT task_artifacts_metadata_kind CHECK (json_extract(metadata, '$.kind') IS artifact_type), CONSTRAINT task_artifacts_test_result_binding CHECK (artifact_type <> 'test' OR ( json_type(metadata, '$.exit_code') IS 'integer' AND ((state = 'passed' AND json_extract(metadata, '$.exit_code') = 0) OR (state = 'failed' AND json_extract(metadata, '$.exit_code') >= 1)) )), CONSTRAINT task_artifacts_review_verdict_binding CHECK (artifact_type <> 'review' OR json_extract(metadata, '$.verdict') IS state), CONSTRAINT task_artifacts_publication_reachability CHECK (artifact_type <> 'publication' OR ( json_type(metadata, '$.reachable') IS 'true' AND json_extract(metadata, '$.reachable') IS 1 )));
CREATE INDEX "index_task_artifacts_on_repository_id" ON "task_artifacts" ("repository_id");
CREATE INDEX "index_task_artifacts_for_listing" ON "task_artifacts" ("repository_id", "task_id", "created_at", "id");
CREATE INDEX "index_task_artifacts_for_contracts" ON "task_artifacts" ("repository_id", "task_id", "artifact_type", "state");
CREATE TABLE "worktree_reservations" ("id" varchar NOT NULL PRIMARY KEY, "repository_id" varchar NOT NULL, "task_id" varchar NOT NULL, "workflow_attempt_id" varchar NOT NULL, "branch" varchar NOT NULL, "path" varchar NOT NULL, "state" varchar DEFAULT 'reserved' NOT NULL, "fencing_token" integer NOT NULL, "git_common_dir_digest" varchar, "head_sha" varchar, "observed_state" varchar, "observation_digest" varchar, "confirmed_at" datetime(6), "released_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_16fb0343f9"
FOREIGN KEY ("repository_id")
  REFERENCES "repositories" ("id")
, CONSTRAINT "fk_rails_fb7d02166d"
FOREIGN KEY ("workflow_attempt_id", "task_id", "repository_id", "fencing_token")
  REFERENCES "workflow_attempts" ("id", "task_id", "repository_id", "fencing_token")
, CONSTRAINT worktree_reservations_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT worktree_reservations_path_absolute CHECK (path LIKE '/%'), CONSTRAINT worktree_reservations_branch_present CHECK (length(branch) > 0), CONSTRAINT worktree_reservations_fencing_token_positive CHECK (fencing_token >= 1), CONSTRAINT worktree_reservations_state_values CHECK (state IN ('reserved', 'confirmed', 'release_pending', 'released')), CONSTRAINT worktree_reservations_observed_state_values CHECK (observed_state IS NULL OR observed_state IN ('absent', 'clean', 'dirty', 'mismatched')), CONSTRAINT worktree_reservations_common_dir_digest_format CHECK (git_common_dir_digest IS NULL OR (substr(git_common_dir_digest, 1, 7) = 'sha256:' AND length(git_common_dir_digest) = 71 AND substr(git_common_dir_digest, 8) NOT GLOB '*[^0-9a-f]*')), CONSTRAINT worktree_reservations_head_sha_format CHECK (head_sha IS NULL OR (length(head_sha) = 40 AND head_sha NOT GLOB '*[^0-9a-f]*')), CONSTRAINT worktree_reservations_observation_digest_format CHECK (observation_digest IS NULL OR (substr(observation_digest, 1, 7) = 'sha256:' AND length(observation_digest) = 71 AND substr(observation_digest, 8) NOT GLOB '*[^0-9a-f]*')), CONSTRAINT worktree_reservations_confirmation_shape CHECK ((state = 'reserved' AND git_common_dir_digest IS NULL AND head_sha IS NULL AND confirmed_at IS NULL) OR (state IN ('confirmed', 'release_pending', 'released') AND git_common_dir_digest IS NOT NULL AND head_sha IS NOT NULL AND confirmed_at IS NOT NULL)), CONSTRAINT worktree_reservations_observation_pair CHECK ((observed_state IS NULL AND observation_digest IS NULL) OR (observed_state IS NOT NULL AND observation_digest IS NOT NULL)), CONSTRAINT worktree_reservations_release_shape CHECK ((state <> 'released' AND released_at IS NULL) OR (state = 'released' AND released_at IS NOT NULL AND observed_state = 'absent')));
CREATE INDEX "index_worktree_reservations_on_repository_id" ON "worktree_reservations" ("repository_id");
CREATE UNIQUE INDEX "index_worktree_reservations_on_id_and_repository_id" ON "worktree_reservations" ("id", "repository_id");
CREATE UNIQUE INDEX "index_worktree_reservations_on_identity_and_ownership" ON "worktree_reservations" ("id", "task_id", "repository_id");
CREATE UNIQUE INDEX "index_worktree_reservations_one_active_per_task" ON "worktree_reservations" ("repository_id", "task_id") WHERE state <> 'released';
CREATE UNIQUE INDEX "index_worktree_reservations_active_branch" ON "worktree_reservations" ("repository_id", "branch") WHERE state <> 'released';
CREATE UNIQUE INDEX "index_worktree_reservations_active_path" ON "worktree_reservations" ("path") WHERE state <> 'released';
CREATE TRIGGER idempotency_records_primary_key_immutable
BEFORE UPDATE OF id ON idempotency_records
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER task_artifacts_primary_key_immutable
BEFORE UPDATE OF id ON task_artifacts
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER worktree_reservations_primary_key_immutable
BEFORE UPDATE OF id ON worktree_reservations
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER idempotency_records_immutable_request
BEFORE UPDATE OF repository_id, command, idempotency_key, request_fingerprint ON idempotency_records
BEGIN
  SELECT RAISE(ABORT, 'idempotency request identity is immutable');
END;
CREATE TRIGGER idempotency_records_completed_immutable
BEFORE UPDATE ON idempotency_records WHEN OLD.state = 'completed'
BEGIN
  SELECT RAISE(ABORT, 'completed idempotency record is immutable');
END;
CREATE TRIGGER idempotency_records_no_delete
BEFORE DELETE ON idempotency_records
BEGIN
  SELECT RAISE(ABORT, 'idempotency record cannot be deleted');
END;
CREATE TRIGGER task_artifacts_immutable
BEFORE UPDATE ON task_artifacts
BEGIN
  SELECT RAISE(ABORT, 'task artifact is immutable');
END;
CREATE TRIGGER task_artifacts_no_delete
BEFORE DELETE ON task_artifacts
BEGIN
  SELECT RAISE(ABORT, 'task artifact cannot be deleted');
END;
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
CREATE TRIGGER worktree_reservations_immutable_allocation
BEFORE UPDATE OF repository_id, task_id, branch, path, created_at ON worktree_reservations
BEGIN
  SELECT RAISE(ABORT, 'worktree reservation allocation is immutable');
END;
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
CREATE TRIGGER worktree_reservations_no_delete
BEFORE DELETE ON worktree_reservations
BEGIN
  SELECT RAISE(ABORT, 'worktree reservation cannot be deleted');
END;
CREATE TRIGGER worktree_reservations_release_requires_detached_task
BEFORE UPDATE OF state ON worktree_reservations
WHEN NEW.state = 'released' AND EXISTS (
  SELECT 1 FROM tasks WHERE worktree_reservation_id = OLD.id
)
BEGIN
  SELECT RAISE(ABORT, 'task must release its worktree reservation pointer first');
END;
CREATE TABLE "workflow_attempts" ("id" varchar NOT NULL PRIMARY KEY, "repository_id" varchar NOT NULL, "task_id" varchar NOT NULL, "workflow_state_id" varchar NOT NULL, "owner_id" varchar NOT NULL, "idempotency_key" varchar NOT NULL, "state" varchar DEFAULT 'started' NOT NULL, "fencing_token" integer NOT NULL, "lease_expires_at" datetime(6), "heartbeat_at" datetime(6), "started_at" datetime(6) NOT NULL, "completed_at" datetime(6), "input_context" text, "input_context_digest" varchar, "result_manifest" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "reconciliation_state" varchar, "reconciliation_evidence_digest" varchar, "reconciled_at" datetime(6), "legacy_reconciliation_pending" boolean DEFAULT FALSE NOT NULL, "completed_transition_id" varchar, CONSTRAINT "fk_rails_41dd974b5a"
FOREIGN KEY ("task_id", "repository_id")
  REFERENCES "tasks" ("id", "repository_id")
, CONSTRAINT "fk_rails_bcec460837"
FOREIGN KEY ("repository_id")
  REFERENCES "repositories" ("id")
, CONSTRAINT "fk_rails_523332645d"
FOREIGN KEY ("workflow_state_id")
  REFERENCES "workflow_states" ("id")
, CONSTRAINT "fk_rails_23840df9f9"
FOREIGN KEY ("completed_transition_id")
  REFERENCES "workflow_transitions" ("id")
, CONSTRAINT workflow_attempts_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT workflow_attempts_owner_id_format CHECK (length(owner_id) BETWEEN 1 AND 128 AND substr(owner_id, 1, 1) GLOB '[a-z]' AND owner_id NOT GLOB '*[^a-z0-9_-]*'), CONSTRAINT workflow_attempts_idempotency_key_format CHECK (length(idempotency_key) BETWEEN 8 AND 255 AND idempotency_key NOT GLOB '*[^A-Za-z0-9._:-]*'), CONSTRAINT workflow_attempts_fencing_token_positive CHECK (fencing_token >= 1), CONSTRAINT workflow_attempts_state_values CHECK (state IN ('started', 'succeeded', 'failed', 'interrupted', 'needs_human')), CONSTRAINT workflow_attempts_context_digest_format CHECK (input_context_digest IS NULL OR (substr(input_context_digest, 1, 7) = 'sha256:' AND length(input_context_digest) = 71 AND substr(input_context_digest, 8) NOT GLOB '*[^0-9a-f]*')), CONSTRAINT workflow_attempts_input_context_json CHECK (input_context IS NULL OR (json_valid(input_context) AND json_type(input_context) = 'object')), CONSTRAINT workflow_attempts_result_manifest_json CHECK (result_manifest IS NULL OR (json_valid(result_manifest) AND json_type(result_manifest) = 'object')), CONSTRAINT workflow_attempts_context_pair CHECK ((input_context IS NULL AND input_context_digest IS NULL) OR (input_context IS NOT NULL AND input_context_digest IS NOT NULL)), CONSTRAINT workflow_attempts_timestamp_order CHECK (heartbeat_at IS NOT NULL AND heartbeat_at >= started_at AND (lease_expires_at IS NULL OR lease_expires_at > heartbeat_at) AND (completed_at IS NULL OR completed_at >= heartbeat_at)), CONSTRAINT workflow_attempts_lifecycle_shape CHECK ((state = 'started' AND lease_expires_at IS NOT NULL AND heartbeat_at IS NOT NULL AND completed_at IS NULL AND result_manifest IS NULL) OR (state = 'interrupted' AND lease_expires_at IS NULL AND heartbeat_at IS NOT NULL AND completed_at IS NOT NULL AND result_manifest IS NULL) OR (state IN ('succeeded', 'failed', 'needs_human') AND lease_expires_at IS NULL AND heartbeat_at IS NOT NULL AND completed_at IS NOT NULL AND input_context IS NOT NULL AND result_manifest IS NOT NULL)), CONSTRAINT workflow_attempts_result_manifest_binding CHECK (result_manifest IS NULL OR ( json_extract(result_manifest, '$.attempt_id') IS id AND json_extract(result_manifest, '$.input_context_digest') IS input_context_digest AND json_extract(result_manifest, '$.outcome') IS state )), CONSTRAINT workflow_attempts_reconciliation_state_values CHECK (reconciliation_state IS NULL OR reconciliation_state IN ( 'no_effect', 'worktree_materialized', 'repository_effect_pending', 'publication_unknown' )), CONSTRAINT workflow_attempts_reconciliation_evidence_digest_format CHECK (reconciliation_evidence_digest IS NULL OR ( substr(reconciliation_evidence_digest, 1, 7) = 'sha256:' AND length(reconciliation_evidence_digest) = 71 AND substr(reconciliation_evidence_digest, 8) NOT GLOB '*[^0-9a-f]*' )), CONSTRAINT workflow_attempts_reconciliation_shape CHECK ((reconciliation_state IS NULL AND reconciliation_evidence_digest IS NULL AND reconciled_at IS NULL AND (state <> 'interrupted' OR legacy_reconciliation_pending = 1)) OR (state = 'interrupted' AND reconciliation_state IS NOT NULL AND reconciliation_evidence_digest IS NOT NULL AND reconciled_at IS NOT NULL AND legacy_reconciliation_pending = 0)), CONSTRAINT workflow_attempts_legacy_reconciliation_pending_boolean CHECK (legacy_reconciliation_pending IN (0, 1)));
CREATE INDEX "index_workflow_attempts_on_repository_id" ON "workflow_attempts" ("repository_id") /*application='Kos'*/;
CREATE UNIQUE INDEX "index_workflow_attempts_on_id_and_repository_id" ON "workflow_attempts" ("id", "repository_id") /*application='Kos'*/;
CREATE UNIQUE INDEX "index_workflow_attempts_on_identity_and_ownership" ON "workflow_attempts" ("id", "task_id", "repository_id") /*application='Kos'*/;
CREATE UNIQUE INDEX "index_workflow_attempts_on_identity_and_fencing" ON "workflow_attempts" ("id", "task_id", "repository_id", "fencing_token") /*application='Kos'*/;
CREATE UNIQUE INDEX "index_workflow_attempts_on_task_and_fencing" ON "workflow_attempts" ("repository_id", "task_id", "fencing_token") /*application='Kos'*/;
CREATE UNIQUE INDEX "index_workflow_attempts_on_repository_id_and_idempotency_key" ON "workflow_attempts" ("repository_id", "idempotency_key") /*application='Kos'*/;
CREATE UNIQUE INDEX "index_workflow_attempts_one_started_per_task" ON "workflow_attempts" ("repository_id", "task_id") WHERE state = 'started' /*application='Kos'*/;
CREATE INDEX "index_workflow_attempts_on_completed_transition_id" ON "workflow_attempts" ("completed_transition_id") /*application='Kos'*/;
CREATE TRIGGER workflow_attempts_completed_transition_insert
BEFORE INSERT ON workflow_attempts
WHEN NEW.state = 'succeeded' OR NEW.completed_transition_id IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'a new attempt cannot be inserted as succeeded or with a completed transition');
END;
CREATE TRIGGER workflow_attempts_completed_transition_update
BEFORE UPDATE OF state, completed_transition_id ON workflow_attempts
WHEN (NEW.state = 'succeeded' AND (
  NEW.completed_transition_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM workflow_transitions transition_record
    JOIN tasks ON tasks.id = NEW.task_id AND tasks.repository_id = NEW.repository_id
    WHERE transition_record.id = NEW.completed_transition_id
      AND transition_record.from_state_id = NEW.workflow_state_id
      AND transition_record.to_state_id = tasks.workflow_state_id
      AND transition_record.workflow_version_id = tasks.workflow_version_id
  )
)) OR (NEW.state <> 'succeeded' AND NEW.completed_transition_id IS NOT NULL)
BEGIN
  SELECT RAISE(ABORT, 'completed transition must match a succeeded attempt and advanced task');
END;
CREATE TRIGGER workflow_attempts_legacy_reconciliation_pending_insert
BEFORE INSERT ON workflow_attempts
WHEN NEW.legacy_reconciliation_pending <> 0
BEGIN
  SELECT RAISE(ABORT, 'legacy reconciliation marker cannot be created');
END;
CREATE TRIGGER workflow_attempts_legacy_reconciliation_pending_update
BEFORE UPDATE OF legacy_reconciliation_pending ON workflow_attempts
WHEN NOT (
  OLD.state = 'interrupted'
  AND OLD.legacy_reconciliation_pending = 1
  AND NEW.legacy_reconciliation_pending = 0
  AND NEW.reconciliation_state IS NOT NULL
  AND NEW.reconciliation_evidence_digest IS NOT NULL
  AND NEW.reconciled_at IS NOT NULL
)
BEGIN
  SELECT RAISE(ABORT, 'legacy reconciliation marker is immutable');
END;
CREATE TRIGGER workflow_attempts_primary_key_immutable
BEFORE UPDATE OF id ON workflow_attempts
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
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
CREATE TRIGGER workflow_attempts_monotonic_fencing
BEFORE INSERT ON workflow_attempts
WHEN NEW.fencing_token <> COALESCE((
  SELECT MAX(fencing_token) + 1 FROM workflow_attempts
  WHERE task_id = NEW.task_id AND repository_id = NEW.repository_id
), 1)
BEGIN
  SELECT RAISE(ABORT, 'attempt fencing token must be the next task token');
END;
CREATE TRIGGER workflow_attempts_immutable_identity
BEFORE UPDATE OF repository_id, task_id, workflow_state_id, owner_id, idempotency_key,
  fencing_token, started_at ON workflow_attempts
BEGIN
  SELECT RAISE(ABORT, 'attempt identity is immutable');
END;
CREATE TRIGGER workflow_attempts_frozen_context
BEFORE UPDATE OF input_context, input_context_digest ON workflow_attempts
WHEN OLD.input_context IS NOT NULL
  AND (NEW.input_context IS NOT OLD.input_context OR NEW.input_context_digest IS NOT OLD.input_context_digest)
BEGIN
  SELECT RAISE(ABORT, 'attempt context is immutable after finalization');
END;
CREATE TRIGGER workflow_attempts_terminal_immutable
BEFORE UPDATE ON workflow_attempts
WHEN OLD.state <> 'started' AND NOT (OLD.state = 'interrupted' AND OLD.reconciliation_state IS NULL AND OLD.reconciliation_evidence_digest IS NULL AND OLD.reconciled_at IS NULL AND OLD.legacy_reconciliation_pending = 1 AND NEW.reconciliation_state IS NOT NULL AND NEW.reconciliation_evidence_digest IS NOT NULL AND NEW.reconciled_at IS NOT NULL AND NEW.legacy_reconciliation_pending = 0 AND NEW.id IS OLD.id AND NEW.repository_id IS OLD.repository_id AND NEW.task_id IS OLD.task_id AND NEW.workflow_state_id IS OLD.workflow_state_id AND NEW.owner_id IS OLD.owner_id AND NEW.idempotency_key IS OLD.idempotency_key AND NEW.state IS OLD.state AND NEW.fencing_token IS OLD.fencing_token AND NEW.lease_expires_at IS OLD.lease_expires_at AND NEW.heartbeat_at IS OLD.heartbeat_at AND NEW.started_at IS OLD.started_at AND NEW.completed_at IS OLD.completed_at AND NEW.input_context IS OLD.input_context AND NEW.input_context_digest IS OLD.input_context_digest AND NEW.result_manifest IS OLD.result_manifest AND NEW.created_at IS OLD.created_at)
BEGIN
  SELECT RAISE(ABORT, 'terminal attempt is immutable');
END;
CREATE TRIGGER workflow_attempts_terminal_requires_detached_task
BEFORE UPDATE OF state ON workflow_attempts
WHEN NEW.state <> 'started' AND EXISTS (
  SELECT 1 FROM tasks WHERE active_attempt_id = OLD.id
)
BEGIN
  SELECT RAISE(ABORT, 'task must release its active attempt before completion');
END;
CREATE TRIGGER workflow_attempts_no_delete
BEFORE DELETE ON workflow_attempts
BEGIN
  SELECT RAISE(ABORT, 'attempt cannot be deleted');
END;
CREATE TABLE "runtime_configs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "retrospective_enabled" boolean DEFAULT FALSE NOT NULL, "lock_version" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT runtime_configs_singleton CHECK (id = 1));
CREATE TRIGGER worktree_reservations_lifecycle
BEFORE UPDATE OF state ON worktree_reservations
WHEN NOT (
  (OLD.state = 'reserved' AND NEW.state IN ('reserved', 'confirmed'))
  OR (OLD.state = 'confirmed' AND NEW.state IN ('confirmed', 'released'))
  OR (OLD.state = 'confirmed' AND NEW.state = 'release_pending'
    AND NEW.observed_state = 'clean' AND NEW.observation_digest IS NOT NULL
    AND NEW.head_sha = OLD.head_sha)
  OR (OLD.state = 'release_pending' AND NEW.state IN ('release_pending', 'released'))
  OR (OLD.state = 'released' AND NEW.state = 'released')
)
BEGIN
  SELECT RAISE(ABORT, 'invalid worktree reservation lifecycle transition');
END;
CREATE TRIGGER worktree_reservations_confirmation_immutable
BEFORE UPDATE OF git_common_dir_digest, head_sha, confirmed_at ON worktree_reservations
WHEN (OLD.git_common_dir_digest IS NOT NULL AND NEW.git_common_dir_digest IS NOT OLD.git_common_dir_digest)
  OR (OLD.confirmed_at IS NOT NULL AND NEW.confirmed_at IS NOT OLD.confirmed_at)
  OR (OLD.state = 'release_pending' AND NEW.head_sha IS NOT OLD.head_sha)
BEGIN
  SELECT RAISE(ABORT, 'worktree reservation confirmation identity is immutable');
END;
CREATE TRIGGER worktree_reservations_released_immutable
BEFORE UPDATE ON worktree_reservations
WHEN OLD.state = 'released'
BEGIN
  SELECT RAISE(ABORT, 'released worktree reservation is immutable');
END;
CREATE TABLE "repository_effects" ("id" varchar NOT NULL PRIMARY KEY, "repository_id" varchar NOT NULL, "task_id" varchar NOT NULL, "prepared_attempt_id" varchar NOT NULL, "current_owner_attempt_id" varchar NOT NULL, "request_digest" varchar NOT NULL, "request" text NOT NULL, "state" varchar DEFAULT 'prepared' NOT NULL, "result" text, "prepared_at" datetime(6) NOT NULL, "reconciled_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_23bf5c8cb2"
FOREIGN KEY ("prepared_attempt_id", "task_id", "repository_id")
  REFERENCES "workflow_attempts" ("id", "task_id", "repository_id")
, CONSTRAINT "fk_rails_992ab68c7e"
FOREIGN KEY ("repository_id")
  REFERENCES "repositories" ("id")
, CONSTRAINT "fk_rails_674a1b8a7c"
FOREIGN KEY ("task_id", "repository_id")
  REFERENCES "tasks" ("id", "repository_id")
, CONSTRAINT "fk_rails_e26b3fe32b"
FOREIGN KEY ("current_owner_attempt_id", "task_id", "repository_id")
  REFERENCES "workflow_attempts" ("id", "task_id", "repository_id")
, CONSTRAINT repository_effects_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT repository_effects_request_digest_format CHECK (substr(request_digest, 1, 7) = 'sha256:' AND length(request_digest) = 71 AND substr(request_digest, 8) NOT GLOB '*[^0-9a-f]*'), CONSTRAINT repository_effects_request_json CHECK (json_valid(request) AND json_type(request) = 'object'), CONSTRAINT repository_effects_result_json CHECK (result IS NULL OR (json_valid(result) AND json_type(result) = 'object')), CONSTRAINT repository_effects_state_values CHECK (state IN ('prepared', 'succeeded', 'failed', 'unknown')), CONSTRAINT repository_effects_request_shape CHECK (json_extract(request, '$.schema_version') IS '1' AND json_extract(request, '$.attempt_id') IS prepared_attempt_id AND json_type(request, '$.input_context_digest') = 'text' AND substr(json_extract(request, '$.input_context_digest'), 1, 7) = 'sha256:' AND length(json_extract(request, '$.input_context_digest')) = 71 AND json_extract(request, '$.effect.operation') IN ('commit', 'fetch', 'rebase') AND COALESCE(CASE json_extract(request, '$.effect.operation') WHEN 'commit' THEN json_type(request, '$.effect.reservation_id') = 'text' AND json_type(request, '$.effect.expected_head_sha') = 'text' AND json_type(request, '$.effect.expected_diff_digest') = 'text' AND json_type(request, '$.effect.expected_index_digest') = 'text' AND json_type(request, '$.effect.paths') = 'array' AND json_array_length(request, '$.effect.paths') > 0 AND json_type(request, '$.effect.message') = 'text' AND length(json_extract(request, '$.effect.message')) > 0 AND json_type(request, '$.effect.task_number') = 'text' WHEN 'fetch' THEN json_type(request, '$.effect.remote') = 'text' AND length(json_extract(request, '$.effect.remote')) > 0 AND json_type(request, '$.effect.ref') = 'text' AND json_extract(request, '$.effect.ref') LIKE 'refs/%' WHEN 'rebase' THEN json_type(request, '$.effect.reservation_id') = 'text' AND json_type(request, '$.effect.expected_head_sha') = 'text' AND json_type(request, '$.effect.onto_sha') = 'text' ELSE 0 END, 0) = 1), CONSTRAINT repository_effects_lifecycle_shape CHECK ((state = 'prepared' AND result IS NULL AND reconciled_at IS NULL) OR (state IN ('succeeded', 'failed', 'unknown') AND result IS NOT NULL AND reconciled_at IS NOT NULL AND json_extract(result, '$.result.outcome') IS state)), CONSTRAINT repository_effects_result_binding CHECK (result IS NULL OR ( json_extract(result, '$.schema_version') IS '1' AND json_extract(result, '$.effect_intent_id') IS id AND json_extract(result, '$.request_attempt_id') IS prepared_attempt_id AND json_extract(result, '$.owner_attempt_id') IS current_owner_attempt_id AND json_extract(result, '$.input_context_digest') IS json_extract(request, '$.input_context_digest') AND json_extract(result, '$.effect_request_digest') IS request_digest AND json_extract(result, '$.result.operation') IS json_extract(request, '$.effect.operation') AND COALESCE(CASE json_extract(result, '$.result.outcome') WHEN 'succeeded' THEN CASE json_extract(result, '$.result.operation') WHEN 'commit' THEN json_type(result, '$.result.commit_sha') = 'text' AND json_type(result, '$.result.evidence_digest') = 'text' WHEN 'fetch' THEN json_type(result, '$.result.remote') = 'text' AND json_type(result, '$.result.ref') = 'text' AND json_type(result, '$.result.observed_oid') = 'text' AND json_type(result, '$.result.evidence_digest') = 'text' WHEN 'rebase' THEN json_type(result, '$.result.head_sha') = 'text' AND json_type(result, '$.result.evidence_digest') = 'text' ELSE 0 END WHEN 'failed' THEN json_type(result, '$.result.error.category') = 'text' AND json_type(result, '$.result.error.code') = 'text' AND json_type(result, '$.result.error.message') = 'text' AND json_type(result, '$.result.error.retryable') IN ('true', 'false') WHEN 'unknown' THEN json_type(result, '$.result.error.category') = 'text' AND json_type(result, '$.result.error.code') = 'text' AND json_type(result, '$.result.error.message') = 'text' AND json_type(result, '$.result.error.retryable') IN ('true', 'false') ELSE 0 END, 0) = 1 )));
CREATE INDEX "index_repository_effects_on_repository_id" ON "repository_effects" ("repository_id") /*application='Kos'*/;
CREATE UNIQUE INDEX "index_repository_effects_on_id_and_repository_id" ON "repository_effects" ("id", "repository_id") /*application='Kos'*/;
CREATE UNIQUE INDEX "index_repository_effects_on_identity_and_ownership" ON "repository_effects" ("id", "task_id", "repository_id") /*application='Kos'*/;
CREATE INDEX "index_repository_effects_on_task_and_state" ON "repository_effects" ("repository_id", "task_id", "state") /*application='Kos'*/;
CREATE INDEX "index_repository_effects_on_owner_and_state" ON "repository_effects" ("current_owner_attempt_id", "state") /*application='Kos'*/;
CREATE TRIGGER repository_effects_primary_key_immutable
BEFORE UPDATE OF id ON repository_effects
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER repository_effects_immutable_intent
BEFORE UPDATE OF repository_id, task_id, prepared_attempt_id, request_digest, request, prepared_at, created_at
  ON repository_effects
BEGIN
  SELECT RAISE(ABORT, 'repository effect intent is immutable');
END;
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
CREATE TRIGGER repository_effects_terminal_immutable
BEFORE UPDATE ON repository_effects
WHEN OLD.state IN ('succeeded', 'failed')
BEGIN
  SELECT RAISE(ABORT, 'terminal repository effect is immutable');
END;
CREATE TRIGGER repository_effects_no_delete
BEFORE DELETE ON repository_effects
BEGIN
  SELECT RAISE(ABORT, 'repository effect cannot be deleted');
END;
CREATE TRIGGER workflow_attempts_unresolved_effect_guard
BEFORE UPDATE OF state ON workflow_attempts
WHEN NEW.state IN ('succeeded', 'failed', 'needs_human') AND EXISTS (
  SELECT 1 FROM repository_effects
  WHERE current_owner_attempt_id = OLD.id AND state IN ('prepared', 'unknown')
)
BEGIN
  SELECT RAISE(ABORT, 'attempt cannot finish with an unresolved repository effect');
END;
CREATE TABLE "publications" ("id" varchar NOT NULL PRIMARY KEY, "repository_id" varchar NOT NULL, "task_id" varchar NOT NULL, "prepared_attempt_id" varchar NOT NULL, "current_owner_attempt_id" varchar NOT NULL, "observation_owner_attempt_id" varchar, "candidate_sha" varchar NOT NULL, "remote" varchar NOT NULL, "base_ref" varchar NOT NULL, "expected_remote_oid" varchar NOT NULL, "state" varchar DEFAULT 'prepared' NOT NULL, "observed_remote_tip" varchar, "candidate_reachable" boolean, "observation_digest" varchar, "observed_at" datetime(6), "prepared_at" datetime(6) NOT NULL, "reconciled_at" datetime(6), "completed_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_715ae2a4f9"
FOREIGN KEY ("current_owner_attempt_id", "task_id", "repository_id")
  REFERENCES "workflow_attempts" ("id", "task_id", "repository_id")
, CONSTRAINT "fk_rails_1a986fba8e"
FOREIGN KEY ("task_id", "repository_id")
  REFERENCES "tasks" ("id", "repository_id")
, CONSTRAINT "fk_rails_eb3ee5888c"
FOREIGN KEY ("repository_id")
  REFERENCES "repositories" ("id")
, CONSTRAINT "fk_rails_baef9f9805"
FOREIGN KEY ("prepared_attempt_id", "task_id", "repository_id")
  REFERENCES "workflow_attempts" ("id", "task_id", "repository_id")
, CONSTRAINT "fk_rails_07f68c8e4f"
FOREIGN KEY ("observation_owner_attempt_id", "task_id", "repository_id")
  REFERENCES "workflow_attempts" ("id", "task_id", "repository_id")
, CONSTRAINT publications_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT publications_candidate_sha_format CHECK (length(candidate_sha) = 40 AND candidate_sha NOT GLOB '*[^0-9a-f]*'), CONSTRAINT publications_expected_oid_format CHECK (length(expected_remote_oid) = 40 AND expected_remote_oid NOT GLOB '*[^0-9a-f]*'), CONSTRAINT publications_observed_tip_format CHECK (observed_remote_tip IS NULL OR (length(observed_remote_tip) = 40 AND observed_remote_tip NOT GLOB '*[^0-9a-f]*')), CONSTRAINT publications_observation_digest_format CHECK (observation_digest IS NULL OR (substr(observation_digest, 1, 7) = 'sha256:' AND length(observation_digest) = 71 AND substr(observation_digest, 8) NOT GLOB '*[^0-9a-f]*')), CONSTRAINT publications_candidate_reachable_boolean CHECK (candidate_reachable IS NULL OR candidate_reachable IN (0, 1)), CONSTRAINT publications_remote_present CHECK (length(remote) > 0), CONSTRAINT publications_base_ref_format CHECK (base_ref LIKE 'refs/heads/%' AND length(base_ref) > 11), CONSTRAINT publications_state_values CHECK (state IN ('prepared', 'reconciled', 'superseded', 'completed')), CONSTRAINT publications_observation_shape CHECK ((state = 'prepared' AND observation_owner_attempt_id IS NULL AND observed_remote_tip IS NULL AND candidate_reachable IS NULL AND observation_digest IS NULL AND observed_at IS NULL AND reconciled_at IS NULL AND completed_at IS NULL) OR (state IN ('reconciled', 'superseded') AND observation_owner_attempt_id IS NOT NULL AND observed_remote_tip IS NOT NULL AND candidate_reachable IS NOT NULL AND observation_digest IS NOT NULL AND observed_at IS NOT NULL AND reconciled_at IS NOT NULL AND completed_at IS NULL) OR (state = 'completed' AND observation_owner_attempt_id IS NOT NULL AND observed_remote_tip IS NOT NULL AND candidate_reachable = 1 AND observation_digest IS NOT NULL AND observed_at IS NOT NULL AND reconciled_at IS NOT NULL AND completed_at IS NOT NULL)), CONSTRAINT publications_superseded_unreachable CHECK (state <> 'superseded' OR candidate_reachable = 0));
CREATE INDEX "index_publications_on_repository_id" ON "publications" ("repository_id");
CREATE UNIQUE INDEX "index_publications_on_id_and_repository_id" ON "publications" ("id", "repository_id");
CREATE UNIQUE INDEX "index_publications_on_identity_and_ownership" ON "publications" ("id", "task_id", "repository_id");
CREATE UNIQUE INDEX "index_publications_one_unresolved_per_task" ON "publications" ("repository_id", "task_id") WHERE state IN ('prepared', 'reconciled');
CREATE INDEX "index_publications_on_owner_and_state" ON "publications" ("current_owner_attempt_id", "state");
CREATE TABLE "tasks" ("id" varchar NOT NULL PRIMARY KEY, "repository_id" varchar NOT NULL, "sequence" integer NOT NULL, "title" varchar NOT NULL, "task_type_id" varchar NOT NULL, "workflow_version_id" varchar NOT NULL, "workflow_state_id" varchar NOT NULL, "lock_version" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "active_attempt_id" varchar, "worktree_reservation_id" varchar, "active_publication_id" varchar, CONSTRAINT "fk_rails_b8caabc2f7"
FOREIGN KEY ("active_attempt_id", "id", "repository_id")
  REFERENCES "workflow_attempts" ("id", "task_id", "repository_id")
, CONSTRAINT "fk_rails_895b56a423"
FOREIGN KEY ("workflow_version_id", "task_type_id")
  REFERENCES "workflow_versions" ("id", "task_type_id")
, CONSTRAINT "fk_rails_172410944d"
FOREIGN KEY ("repository_id")
  REFERENCES "repositories" ("id")
, CONSTRAINT "fk_rails_f6eab2208f"
FOREIGN KEY ("task_type_id")
  REFERENCES "task_types" ("id")
, CONSTRAINT "fk_rails_75855fcbda"
FOREIGN KEY ("workflow_state_id", "workflow_version_id")
  REFERENCES "workflow_states" ("id", "workflow_version_id")
, CONSTRAINT "fk_rails_95215c6001"
FOREIGN KEY ("worktree_reservation_id", "id", "repository_id")
  REFERENCES "worktree_reservations" ("id", "task_id", "repository_id")
, CONSTRAINT "fk_rails_7c69a571af"
FOREIGN KEY ("active_publication_id", "id", "repository_id")
  REFERENCES "publications" ("id", "task_id", "repository_id")
, CONSTRAINT tasks_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT tasks_sequence_range CHECK (sequence BETWEEN 1 AND 999999), CONSTRAINT tasks_title_present CHECK (length(title) > 0), CONSTRAINT tasks_lock_version_nonnegative CHECK (lock_version >= 0));
CREATE INDEX "index_tasks_on_repository_id" ON "tasks" ("repository_id");
CREATE UNIQUE INDEX "index_tasks_on_repository_id_and_sequence" ON "tasks" ("repository_id", "sequence");
CREATE UNIQUE INDEX "index_tasks_on_id_and_repository_id" ON "tasks" ("id", "repository_id");
CREATE UNIQUE INDEX "index_tasks_on_active_attempt_id" ON "tasks" ("active_attempt_id");
CREATE UNIQUE INDEX "index_tasks_on_worktree_reservation_id" ON "tasks" ("worktree_reservation_id");
CREATE UNIQUE INDEX "index_tasks_on_active_publication_id" ON "tasks" ("active_publication_id");
CREATE TRIGGER tasks_primary_key_immutable
BEFORE UPDATE OF id ON tasks
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER tasks_workflow_version_must_be_published
BEFORE INSERT ON tasks
WHEN NOT EXISTS (
  SELECT 1 FROM workflow_versions
  WHERE id = NEW.workflow_version_id AND published_at IS NOT NULL
)
BEGIN
  SELECT RAISE(ABORT, 'task workflow version must be published');
END;
CREATE TRIGGER tasks_immutable_identity
BEFORE UPDATE OF repository_id, sequence, task_type_id, workflow_version_id ON tasks
BEGIN
  SELECT RAISE(ABORT, 'task identity and workflow version are immutable');
END;
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
CREATE TRIGGER publications_primary_key_immutable
BEFORE UPDATE OF id ON publications
BEGIN
  SELECT RAISE(ABORT, 'primary key is immutable');
END;
CREATE TRIGGER publications_immutable_intent
BEFORE UPDATE OF repository_id, task_id, prepared_attempt_id, candidate_sha, remote, base_ref,
  expected_remote_oid, prepared_at, created_at ON publications
BEGIN
  SELECT RAISE(ABORT, 'publication intent is immutable');
END;
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
CREATE TRIGGER publications_observation_update
BEFORE UPDATE OF observation_owner_attempt_id, observed_remote_tip, candidate_reachable,
  observation_digest, observed_at, reconciled_at ON publications
WHEN NEW.observed_at IS NOT NULL AND (
  julianday(NEW.observed_at) IS NULL
  OR julianday(NEW.observed_at) < julianday(NEW.prepared_at)
  OR julianday(NEW.observed_at) >
    julianday(CURRENT_TIMESTAMP, '+5 minutes')
  OR (OLD.observed_at IS NOT NULL
    AND julianday(NEW.observed_at) <= julianday(OLD.observed_at))
  OR NEW.observation_owner_attempt_id IS NOT NEW.current_owner_attempt_id
)
BEGIN
  SELECT RAISE(ABORT, 'invalid publication observation update');
END;
CREATE TRIGGER publications_terminal_immutable
BEFORE UPDATE ON publications
WHEN OLD.state IN ('superseded', 'completed')
BEGIN
  SELECT RAISE(ABORT, 'terminal publication is immutable');
END;
CREATE TRIGGER publications_no_delete
BEFORE DELETE ON publications
BEGIN
  SELECT RAISE(ABORT, 'publication cannot be deleted');
END;
CREATE TRIGGER publications_terminal_requires_detached_task
BEFORE UPDATE OF state ON publications
WHEN NEW.state IN ('superseded', 'completed') AND EXISTS (
  SELECT 1 FROM tasks WHERE active_publication_id = OLD.id
)
BEGIN
  SELECT RAISE(ABORT, 'task must release its active publication before termination');
END;
CREATE TRIGGER tasks_active_publication_must_be_unresolved
BEFORE UPDATE OF active_publication_id ON tasks
WHEN NEW.active_publication_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM publications WHERE id = NEW.active_publication_id AND task_id = NEW.id
    AND repository_id = NEW.repository_id AND state IN ('prepared', 'reconciled')
)
BEGIN
  SELECT RAISE(ABORT, 'task active publication must be unresolved');
END;
CREATE TRIGGER workflow_attempts_unresolved_publication_guard
BEFORE UPDATE OF state ON workflow_attempts
WHEN NEW.state IN ('succeeded', 'failed', 'needs_human') AND EXISTS (
  SELECT 1 FROM publications
  WHERE current_owner_attempt_id = OLD.id AND state IN ('prepared', 'reconciled')
)
BEGIN
  SELECT RAISE(ABORT, 'attempt cannot finish with an unresolved publication');
END;
INSERT INTO "schema_migrations" (version) VALUES
('20260912010000'),
('20260912000000'),
('20260911030000'),
('20260911020000'),
('20260911010000'),
('20260911000000'),
('20260910000000'),
('20260909000000');
