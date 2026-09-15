require "json"
require "open3"
require "rails_helper"
require "tmpdir"

RSpec.describe Task, ".approved task input migration", :aggregate_failures do
  let(:previous_version) { 20_260_912_010_000 }

  def root
    File.expand_path("../../..", __dir__)
  end

  def environment(directory)
    { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3") }
  end

  def command!(environment, *arguments)
    output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), *arguments)
    expect(status).to be_success, output
    output
  end

  def runner!(environment, script)
    JSON.parse(command!(environment, "runner", script).lines.last)
  end

  def migrate!(environment, target = nil)
    invocation = target ? "context.migrate(#{target})" : "context.migrate"
    command!(environment, "runner", "context = ActiveRecord::Base.connection_pool.migration_context; #{invocation}")
  end

  def seed_legacy_task(environment)
    runner!(environment, <<~'RUBY')
      definition = JSON.parse(File.read(Rails.root.join("workflows/quick-fix/1.0.1.json")))
      repository = Repository.create!(git_common_dir: "/tmp/legacy-input.git", task_prefix: "LEG",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      TaskType.create!(id: "quick-fix", name: "quick-fix", workflow_id: "quick-fix")
      draft = WorkflowCatalog::ImportDraft.call(workflow_id: "quick-fix", definition: definition,
        expected_lock_version: 0)
      version = WorkflowCatalog::PublishDraft.call(workflow_id: "quick-fix",
        expected_lock_version: draft.lock_version)
      TaskType.find("quick-fix").update!(current_workflow_version: version)
      task = Task.create!(repository: repository, sequence: 1, title: "Legacy task", task_type: version.task_type,
        workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
      puts JSON.generate("repository_id" => repository.id, "task_id" => task.id)
    RUBY
  end

  def verify_upgrade(environment, identifiers)
    runner!(environment.merge(identifiers.transform_keys(&:upcase)), <<~'RUBY')
      repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
      task = Task.find(ENV.fetch("TASK_ID"))
      resource = Api::V1::Serializer.task(task)
      attempt = WorkflowAttempts::Claim.call(repository: repository, task_number: task.number,
        owner_id: "legacy-owner", lease_seconds: 300, expected_lock_version: task.lock_version,
        idempotency_key: "legacy-input-claim")
      error = begin
        WorkflowSteps::CaptureContext.call(repository: repository, attempt_id: attempt.id,
          fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version)
      rescue OperationError => exception
        exception.code
      end
      missing_insert_blocked = begin
        Task.insert_all!([{ id: SecureRandom.uuid, repository_id: repository.id, sequence: 2, title: "Missing input",
          task_type_id: task.task_type_id, workflow_version_id: task.workflow_version_id,
          workflow_state_id: task.workflow_state_id, lock_version: 0, created_at: Time.current, updated_at: Time.current }])
        false
      rescue ActiveRecord::StatementInvalid
        true
      end
      invalid_values_blocked = [
        { title: " \t\n", task_input_schema_version: "1", approved_brief: "Approved." },
        { title: "Blank brief", task_input_schema_version: "1", approved_brief: " \t\r\n" },
        { title: "Invalid brief", task_input_schema_version: "1", approved_brief: "\xFF".b }
      ].each_with_index.all? do |values, index|
        Task.insert_all!([{ id: SecureRandom.uuid, repository_id: repository.id,
          sequence: index + 3, task_type_id: task.task_type_id,
          workflow_version_id: task.workflow_version_id, workflow_state_id: task.workflow_state_id,
          lock_version: 0, created_at: Time.current, updated_at: Time.current, **values }])
        false
      rescue ActiveRecord::StatementInvalid
        true
      end
      puts JSON.generate("task_input" => task.task_input, "resource" => resource, "context_error" => error,
        "missing_insert_blocked" => missing_insert_blocked, "invalid_values_blocked" => invalid_values_blocked)
    RUBY
  end

  def rollback_summary(environment)
    migrate!(environment, previous_version)
    runner!(environment, <<~'RUBY')
      triggers = ActiveRecord::Base.connection.select_values(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'tasks' ORDER BY name"
      )
      puts JSON.generate("columns" => Task.column_names.grep(/task_input|approved_brief/), "triggers" => triggers)
    RUBY
  end

  def migration_summary
    Dir.mktmpdir("kos-approved-input-migration") do |directory|
      env = environment(directory)
      migrate!(env, previous_version)
      identifiers = seed_legacy_task(env)
      migrate!(env)
      result = verify_upgrade(env, identifiers)
      rollback = rollback_summary(env)
      [ result.fetch("task_input"), result.dig("resource", "task_input"), result.fetch("context_error"),
        result.fetch("missing_insert_blocked"), result.fetch("invalid_values_blocked"),
        Kos::Cli::SchemaRegistry.new.valid?("resources.json", "task", result.fetch("resource")),
        rollback.fetch("columns"), rollback.fetch("triggers") ]
    end
  end

  def expected_migration_summary
    [ nil, nil, "context_unavailable", true, true, true, [], %w[
      tasks_active_attempt_must_be_started
      tasks_active_publication_must_be_unresolved
      tasks_immutable_identity
      tasks_primary_key_immutable
      tasks_workflow_state_requires_matching_attempt
      tasks_workflow_version_must_be_published
      tasks_worktree_reservation_must_be_active
    ] ]
  end

  it "preserves readable legacy tasks while failing closed for new execution" do
    expect(migration_summary).to eq(expected_migration_summary)
  end
end
