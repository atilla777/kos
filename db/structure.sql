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
CREATE TABLE "tasks" ("id" varchar NOT NULL PRIMARY KEY, "repository_id" varchar NOT NULL, "sequence" integer NOT NULL, "title" varchar NOT NULL, "task_type_id" varchar NOT NULL, "workflow_version_id" varchar NOT NULL, "workflow_state_id" varchar NOT NULL, "lock_version" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_895b56a423"
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
, CONSTRAINT tasks_id_format CHECK (length(id) = 36 AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' AND length(replace(id, '-', '')) = 32 AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'), CONSTRAINT tasks_sequence_range CHECK (sequence BETWEEN 1 AND 999999), CONSTRAINT tasks_title_present CHECK (length(title) > 0), CONSTRAINT tasks_lock_version_nonnegative CHECK (lock_version >= 0));
CREATE INDEX "index_tasks_on_repository_id" ON "tasks" ("repository_id");
CREATE UNIQUE INDEX "index_tasks_on_repository_id_and_sequence" ON "tasks" ("repository_id", "sequence");
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
CREATE TRIGGER tasks_primary_key_immutable
BEFORE UPDATE OF id ON tasks
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
INSERT INTO "schema_migrations" (version) VALUES
('20260909000000');
