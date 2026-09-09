class CreateBasePersistence < ActiveRecord::Migration[8.1]
  PUBLISHED_WORKFLOW_TABLES = %w[
    workflow_states
    artifact_templates
    workflow_state_effects
    artifact_requirements
    artifact_requirement_states
    workflow_transitions
    workflow_transition_conditions
  ].freeze
  PRIMARY_KEY_TABLES = ([ "task_types" ] + PUBLISHED_WORKFLOW_TABLES + %w[
    repositories
    workflow_drafts
    workflow_versions
    tasks
  ]).freeze

  def change
    create_repositories
    create_task_types
    create_workflow_catalog
    create_tasks
    add_catalog_foreign_keys
    add_immutability_triggers
  end

  private

  def create_repositories
    create_table :repositories, id: :string do |table|
      table.string :git_common_dir, null: false
      table.string :task_prefix, null: false
      table.string :trusted_remote, null: false
      table.string :trusted_remote_url, null: false
      table.string :base_ref, null: false
      table.integer :next_task_sequence, null: false, default: 1
      table.timestamps

      table.check_constraint uuid_check("id"), name: "repositories_id_format"
      table.check_constraint "git_common_dir LIKE '/%'", name: "repositories_git_common_dir_absolute"
      table.check_constraint <<~SQL.squish, name: "repositories_task_prefix_format"
        length(task_prefix) BETWEEN 2 AND 10
        AND substr(task_prefix, 1, 1) GLOB '[A-Z]'
        AND task_prefix NOT GLOB '*[^A-Z0-9]*'
      SQL
      table.check_constraint "base_ref LIKE 'refs/heads/%'", name: "repositories_base_ref_format"
      table.check_constraint "next_task_sequence BETWEEN 1 AND 1000000", name: "repositories_next_task_sequence_range"
    end

    add_index :repositories, :git_common_dir, unique: true
    add_index :repositories, :task_prefix, unique: true
  end

  def create_task_types
    create_table :task_types, id: :string do |table|
      table.string :name, null: false
      table.string :workflow_id, null: false
      table.string :current_workflow_version_id
      table.integer :lock_version, null: false, default: 0
      table.timestamps

      table.check_constraint identifier_check("id"), name: "task_types_id_format"
      table.check_constraint identifier_check("name"), name: "task_types_name_format"
      table.check_constraint identifier_check("workflow_id"), name: "task_types_workflow_id_format"
      table.check_constraint "lock_version >= 0", name: "task_types_lock_version_nonnegative"
    end

    add_index :task_types, :name, unique: true
    add_index :task_types, :workflow_id, unique: true
    add_index :task_types, %i[id workflow_id], unique: true
  end

  def create_workflow_catalog
    create_table :workflow_drafts, id: :string do |table|
      table.string :task_type_id, null: false
      table.string :workflow_id, null: false
      table.text :definition, null: false
      table.integer :lock_version, null: false, default: 0
      table.timestamps

      table.check_constraint uuid_check("id"), name: "workflow_drafts_id_format"
      table.check_constraint "json_valid(definition)", name: "workflow_drafts_definition_json"
      table.check_constraint "lock_version >= 0", name: "workflow_drafts_lock_version_nonnegative"
    end
    add_index :workflow_drafts, :workflow_id, unique: true
    add_index :workflow_drafts, %i[task_type_id workflow_id], unique: true

    create_table :workflow_versions, id: :string do |table|
      table.string :task_type_id, null: false
      table.string :workflow_id, null: false
      table.string :version, null: false
      table.string :content_digest, null: false
      table.datetime :published_at
      table.timestamps

      table.check_constraint uuid_check("id"), name: "workflow_versions_id_format"
      table.check_constraint <<~SQL.squish, name: "workflow_versions_digest_format"
        substr(content_digest, 1, 7) = 'sha256:'
        AND length(content_digest) = 71
        AND substr(content_digest, 8) NOT GLOB '*[^0-9a-f]*'
      SQL
    end
    add_index :workflow_versions, %i[workflow_id version], unique: true
    add_index :workflow_versions, %i[id task_type_id], unique: true

    create_table :workflow_states, id: :string do |table|
      table.references :workflow_version, type: :string, null: false, foreign_key: true
      table.string :identifier, null: false
      table.boolean :initial, null: false, default: false
      table.boolean :terminal, null: false, default: false
      table.string :execution_mode
      table.text :instruction
      table.string :worktree_policy
      table.string :repository_changes_policy
      table.timestamps

      table.check_constraint uuid_check("id"), name: "workflow_states_id_format"
      table.check_constraint identifier_check("identifier"), name: "workflow_states_identifier_format"
      table.check_constraint "initial IN (0, 1) AND terminal IN (0, 1)", name: "workflow_states_boolean_values"
      table.check_constraint <<~SQL.squish, name: "workflow_states_execution_shape"
        (terminal = 1 AND initial = 0 AND execution_mode IS NULL AND instruction IS NULL
          AND worktree_policy IS NULL AND repository_changes_policy IS NULL)
        OR
        (terminal = 0 AND execution_mode IN ('main_session', 'subagent')
          AND length(instruction) > 0 AND worktree_policy IN ('required', 'none')
          AND repository_changes_policy IN ('allowed', 'forbidden'))
      SQL
    end
    add_index :workflow_states, %i[workflow_version_id identifier], unique: true
    add_index :workflow_states, %i[id workflow_version_id], unique: true
    add_index :workflow_states, :workflow_version_id, unique: true, where: "initial = 1", name: "index_workflow_states_one_initial"
    add_index :workflow_states, :workflow_version_id, unique: true, where: "terminal = 1", name: "index_workflow_states_one_terminal"

    create_table :artifact_templates, id: :string do |table|
      table.references :workflow_state, type: :string, null: false, foreign_key: true
      table.string :identifier, null: false
      table.string :media_type, null: false
      table.text :content, null: false
      table.timestamps

      table.check_constraint uuid_check("id"), name: "artifact_templates_id_format"
      table.check_constraint identifier_check("identifier"), name: "artifact_templates_identifier_format"
      table.check_constraint "media_type = 'text/markdown; charset=utf-8'", name: "artifact_templates_media_type"
      table.check_constraint "length(content) > 0", name: "artifact_templates_content_present"
    end
    add_index :artifact_templates, %i[workflow_state_id identifier], unique: true

    create_table :workflow_state_effects, id: :string do |table|
      table.references :workflow_state, type: :string, null: false, foreign_key: true
      table.string :effect, null: false
      table.timestamps

      table.check_constraint uuid_check("id"), name: "workflow_state_effects_id_format"
      table.check_constraint "effect IN ('worktree_remove', 'commit', 'fetch', 'rebase', 'push')", name: "workflow_state_effects_effect_values"
    end
    add_index :workflow_state_effects, %i[workflow_state_id effect], unique: true

    create_table :artifact_requirements, id: :string do |table|
      table.references :workflow_state, type: :string, null: false, foreign_key: true
      table.string :artifact_type, null: false
      table.string :cardinality, null: false
      table.string :subject, null: false
      table.timestamps

      table.check_constraint uuid_check("id"), name: "artifact_requirements_id_format"
      table.check_constraint "artifact_type IN ('document', 'candidate', 'test', 'review', 'publication')", name: "artifact_requirements_type_values"
      table.check_constraint "cardinality IN ('one', 'many')", name: "artifact_requirements_cardinality_values"
      table.check_constraint "subject IN ('task', 'candidate')", name: "artifact_requirements_subject_values"
    end
    add_index :artifact_requirements, %i[workflow_state_id artifact_type], unique: true

    create_table :artifact_requirement_states, id: :string do |table|
      table.references :artifact_requirement, type: :string, null: false, foreign_key: true, index: false
      table.string :state, null: false
      table.timestamps

      table.check_constraint uuid_check("id"), name: "artifact_requirement_states_id_format"
      table.check_constraint "state IN ('produced', 'passed', 'failed', 'approved', 'changes_requested', 'published')", name: "artifact_requirement_states_state_values"
    end
    add_index :artifact_requirement_states, %i[artifact_requirement_id state], unique: true, name: "index_artifact_requirement_states_uniqueness"

    create_table :workflow_transitions, id: :string do |table|
      table.references :workflow_version, type: :string, null: false, foreign_key: true
      table.string :from_state_id, null: false
      table.string :to_state_id, null: false
      table.timestamps

      table.check_constraint uuid_check("id"), name: "workflow_transitions_id_format"
      table.check_constraint "from_state_id <> to_state_id", name: "workflow_transitions_distinct_states"
    end
    add_index :workflow_transitions, %i[workflow_version_id from_state_id to_state_id], unique: true, name: "index_workflow_transitions_uniqueness"

    create_table :workflow_transition_conditions, id: :string do |table|
      table.references :workflow_transition, type: :string, null: false, foreign_key: true, index: false
      table.integer :position, null: false
      table.string :condition_type, null: false
      table.string :artifact_type
      table.string :artifact_state
      table.string :decision
      table.string :value
      table.timestamps

      table.check_constraint uuid_check("id"), name: "workflow_transition_conditions_id_format"
      table.check_constraint "position >= 0", name: "workflow_transition_conditions_position_nonnegative"
      table.check_constraint <<~SQL.squish, name: "workflow_transition_conditions_artifact_values"
        artifact_type IS NULL OR artifact_type IN ('document', 'candidate', 'test', 'review', 'publication')
      SQL
      table.check_constraint <<~SQL.squish, name: "workflow_transition_conditions_artifact_state_values"
        artifact_state IS NULL OR artifact_state IN ('produced', 'passed', 'failed', 'approved', 'changes_requested', 'published')
      SQL
      table.check_constraint "decision IS NULL OR (#{identifier_check("decision")})", name: "workflow_transition_conditions_decision_format"
      table.check_constraint "value IS NULL OR (#{identifier_check("value")})", name: "workflow_transition_conditions_value_format"
      table.check_constraint <<~SQL.squish, name: "workflow_transition_conditions_shape"
        (condition_type = 'always' AND artifact_type IS NULL AND artifact_state IS NULL AND decision IS NULL AND value IS NULL)
        OR (condition_type IN ('artifact-present', 'not-applicable') AND artifact_type IS NOT NULL
          AND artifact_state IS NULL AND decision IS NULL AND value IS NULL)
        OR (condition_type = 'artifact-state' AND artifact_type IS NOT NULL
          AND artifact_state IS NOT NULL AND decision IS NULL AND value IS NULL)
        OR (condition_type = 'decision' AND artifact_type IS NULL AND artifact_state IS NULL
          AND decision IS NOT NULL AND value IS NOT NULL)
      SQL
    end
    add_index :workflow_transition_conditions, %i[workflow_transition_id position], unique: true, name: "index_workflow_transition_conditions_position"
  end

  def create_tasks
    create_table :tasks, id: :string do |table|
      table.references :repository, type: :string, null: false, foreign_key: true
      table.integer :sequence, null: false
      table.string :title, null: false
      table.string :task_type_id, null: false
      table.string :workflow_version_id, null: false
      table.string :workflow_state_id, null: false
      table.integer :lock_version, null: false, default: 0
      table.timestamps

      table.check_constraint uuid_check("id"), name: "tasks_id_format"
      table.check_constraint "sequence BETWEEN 1 AND 999999", name: "tasks_sequence_range"
      table.check_constraint "length(title) > 0", name: "tasks_title_present"
      table.check_constraint "lock_version >= 0", name: "tasks_lock_version_nonnegative"
    end
    add_index :tasks, %i[repository_id sequence], unique: true
  end

  def add_catalog_foreign_keys
    add_foreign_key :workflow_drafts, :task_types,
      column: %i[task_type_id workflow_id], primary_key: %i[id workflow_id]
    add_foreign_key :workflow_versions, :task_types,
      column: %i[task_type_id workflow_id], primary_key: %i[id workflow_id]
    add_foreign_key :task_types, :workflow_versions, column: :current_workflow_version_id
    add_foreign_key :workflow_transitions, :workflow_states,
      column: %i[from_state_id workflow_version_id], primary_key: %i[id workflow_version_id]
    add_foreign_key :workflow_transitions, :workflow_states,
      column: %i[to_state_id workflow_version_id], primary_key: %i[id workflow_version_id]
    add_foreign_key :tasks, :task_types
    add_foreign_key :tasks, :workflow_versions,
      column: %i[workflow_version_id task_type_id], primary_key: %i[id task_type_id]
    add_foreign_key :tasks, :workflow_states,
      column: %i[workflow_state_id workflow_version_id], primary_key: %i[id workflow_version_id]
  end

  def identifier_check(column)
    <<~SQL.squish
      length(#{column}) BETWEEN 1 AND 128
      AND substr(#{column}, 1, 1) GLOB '[a-z]'
      AND #{column} NOT GLOB '*[^a-z0-9_-]*'
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

  def add_immutability_triggers
    PRIMARY_KEY_TABLES.each do |table|
      execute <<~SQL
        CREATE TRIGGER #{table}_primary_key_immutable
        BEFORE UPDATE OF id ON #{table}
        BEGIN
          SELECT RAISE(ABORT, 'primary key is immutable');
        END;
      SQL
    end

    execute <<~SQL
      CREATE TRIGGER repositories_immutable_registration
      BEFORE UPDATE OF git_common_dir, task_prefix, trusted_remote, trusted_remote_url, base_ref ON repositories
      BEGIN
        SELECT RAISE(ABORT, 'repository registration is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER repositories_no_delete
      BEFORE DELETE ON repositories
      BEGIN
        SELECT RAISE(ABORT, 'repository registration cannot be deleted');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_versions_immutable
      BEFORE UPDATE ON workflow_versions WHEN OLD.published_at IS NOT NULL
      BEGIN
        SELECT RAISE(ABORT, 'published workflow version is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_versions_no_delete
      BEFORE DELETE ON workflow_versions WHEN OLD.published_at IS NOT NULL
      BEGIN
        SELECT RAISE(ABORT, 'published workflow version cannot be deleted');
      END;
    SQL

    PUBLISHED_WORKFLOW_TABLES.each do |table|
      workflow_version_lookup = workflow_version_lookup_for(table)
      execute <<~SQL
        CREATE TRIGGER #{table}_published_no_insert
        BEFORE INSERT ON #{table} WHEN (#{workflow_version_lookup.call(:new)}) IS NOT NULL
        BEGIN
          SELECT RAISE(ABORT, 'published workflow content is immutable');
        END;
      SQL
      execute <<~SQL
        CREATE TRIGGER #{table}_published_no_update
        BEFORE UPDATE ON #{table}
        WHEN (#{workflow_version_lookup.call(:old)}) IS NOT NULL
          OR (#{workflow_version_lookup.call(:new)}) IS NOT NULL
        BEGIN
          SELECT RAISE(ABORT, 'published workflow content is immutable');
        END;
      SQL
      execute <<~SQL
        CREATE TRIGGER #{table}_published_no_delete
        BEFORE DELETE ON #{table} WHEN (#{workflow_version_lookup.call(:old)}) IS NOT NULL
        BEGIN
          SELECT RAISE(ABORT, 'published workflow content is immutable');
        END;
      SQL
    end

    execute <<~SQL
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
    SQL
    execute <<~SQL
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
    SQL
    execute <<~SQL
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
    SQL
  end

  def workflow_version_lookup_for(table)
    case table
    when "workflow_states", "workflow_transitions"
      ->(row) { "SELECT published_at FROM workflow_versions WHERE id = #{row.to_s.upcase}.workflow_version_id" }
    when "artifact_templates", "workflow_state_effects", "artifact_requirements"
      lambda do |row|
        <<~SQL.squish
          SELECT workflow_versions.published_at FROM workflow_versions
          JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id
          WHERE workflow_states.id = #{row.to_s.upcase}.workflow_state_id
        SQL
      end
    when "artifact_requirement_states"
      lambda do |row|
        <<~SQL.squish
          SELECT workflow_versions.published_at FROM workflow_versions
          JOIN workflow_states ON workflow_states.workflow_version_id = workflow_versions.id
          JOIN artifact_requirements ON artifact_requirements.workflow_state_id = workflow_states.id
          WHERE artifact_requirements.id = #{row.to_s.upcase}.artifact_requirement_id
        SQL
      end
    when "workflow_transition_conditions"
      lambda do |row|
        <<~SQL.squish
          SELECT workflow_versions.published_at FROM workflow_versions
          JOIN workflow_transitions ON workflow_transitions.workflow_version_id = workflow_versions.id
          WHERE workflow_transitions.id = #{row.to_s.upcase}.workflow_transition_id
        SQL
      end
    end
  end
end
