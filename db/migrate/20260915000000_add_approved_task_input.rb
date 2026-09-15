class AddApprovedTaskInput < ActiveRecord::Migration[8.1]
  def up
    execute "DROP TRIGGER tasks_immutable_identity"
    add_column :tasks, :task_input_schema_version, :string
    add_column :tasks, :approved_brief, :text
    create_task_input_triggers
  end

  def down
    retained_triggers = select_values(<<~SQL).compact.reject do |statement|
      SELECT sql FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'tasks'
    SQL
      statement.match?(/CREATE TRIGGER tasks_(approved_input_required|immutable_identity)/)
    end
    execute "DROP TRIGGER tasks_approved_input_required"
    execute "DROP TRIGGER tasks_immutable_identity"
    remove_column :tasks, :approved_brief
    remove_column :tasks, :task_input_schema_version
    retained_triggers.each { execute(_1) }
    execute <<~SQL
      CREATE TRIGGER tasks_immutable_identity
      BEFORE UPDATE OF repository_id, sequence, task_type_id, workflow_version_id ON tasks
      BEGIN
        SELECT RAISE(ABORT, 'task identity and workflow version are immutable');
      END;
    SQL
  end

  private

  def create_task_input_triggers
    execute <<~SQL
      CREATE TRIGGER tasks_approved_input_required
      BEFORE INSERT ON tasks
      WHEN typeof(NEW.title) <> 'text'
        OR length(trim(NEW.title, char(9) || char(10) || char(11) || char(12) || char(13) || ' ')) = 0
        OR NEW.task_input_schema_version IS NULL
        OR NEW.task_input_schema_version <> '1'
        OR NEW.approved_brief IS NULL
        OR typeof(NEW.approved_brief) <> 'text'
        OR length(trim(NEW.approved_brief,
          char(9) || char(10) || char(11) || char(12) || char(13) || ' ')) = 0
        OR length(CAST(NEW.approved_brief AS BLOB)) > 131072
      BEGIN
        SELECT RAISE(ABORT, 'approved task input is required');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER tasks_immutable_identity
      BEFORE UPDATE OF repository_id, sequence, title, task_type_id, workflow_version_id,
        task_input_schema_version, approved_brief ON tasks
      BEGIN
        SELECT RAISE(ABORT, 'task identity, workflow version, and approved input are immutable');
      END;
    SQL
  end
end
