require "json"
require "open3"
require "rails_helper"
require "tmpdir"

RSpec.describe WorkflowAttempts::Reconcile, :aggregate_failures do
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
    command!(environment, "runner",
      "context = ActiveRecord::Base.connection_pool.migration_context; #{invocation}")
  end

  def rollback!(environment)
    command!(environment, "runner", "ActiveRecord::Base.connection_pool.migration_context.rollback(1)")
  end

  def seed_legacy_attempt(environment)
    runner!(environment, <<~'RUBY')
      digest = "sha256:" + ("a" * 64)
      type = TaskType.create!(id: "legacy-type", name: "legacy-type", workflow_id: "legacy-workflow")
      version = WorkflowVersion.create!(task_type: type, workflow_id: type.workflow_id, version: "1.0.0",
        content_digest: digest)
      state = WorkflowState.create!(workflow_version: version, identifier: "development", initial: true,
        execution_mode: "subagent", instruction: "Work.", worktree_policy: "required",
        repository_changes_policy: "allowed")
      WorkflowState.create!(workflow_version: version, identifier: "completed", terminal: true)
      version.update!(published_at: Time.current)
      repository = Repository.create!(git_common_dir: "/tmp/legacy-attempt.git", task_prefix: "LEG",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      task = Task.create!(repository: repository, sequence: 1, title: "Legacy attempt", task_type: type,
        workflow_version: version, workflow_state: state)
      now = Time.current
      attempt_id = SecureRandom.uuid
      WorkflowAttempt.insert_all!([{ id: attempt_id, repository_id: repository.id, task_id: task.id,
        workflow_state_id: state.id, owner_id: "legacy-owner", idempotency_key: "legacy-claim-key",
        state: "interrupted", fencing_token: 1, heartbeat_at: now, started_at: now, completed_at: now,
        created_at: now, updated_at: now }])
      puts JSON.generate([repository.id, attempt_id])
    RUBY
  end

  def verify_upgrade(environment, repository_id, attempt_id)
    runner!(environment.merge("REPOSITORY_ID" => repository_id, "ATTEMPT_ID" => attempt_id), <<~'RUBY')
      repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
      attempt = WorkflowAttempt.find(ENV.fetch("ATTEMPT_ID"))
      before_valid = Kos::Cli::SchemaRegistry.new.valid?("resources.json", "attempt",
        Api::V1::Serializer.attempt(attempt))
      result = WorkflowAttempts::Reconcile.call(repository: repository, attempt_id: attempt.id,
        observed_state: "no_effect", evidence_digest: "sha256:" + ("b" * 64), expected_lock_version: 0)
      now = Time.current
      new_attempt = WorkflowAttempt.create!(repository: repository, task: attempt.task,
        workflow_state: attempt.workflow_state, owner_id: "new-owner", idempotency_key: "new-claim-key",
        fencing_token: 2, heartbeat_at: now, started_at: now, lease_expires_at: now + 5.minutes)
      invalid_interruption = begin
        new_attempt.update!(state: "interrupted", lease_expires_at: nil, completed_at: Time.current)
        false
      rescue ActiveRecord::StatementInvalid
        true
      end
      immutable = begin
        result.touch
        false
      rescue ActiveRecord::StatementInvalid
        true
      end
      triggers = ActiveRecord::Base.connection.select_values(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'workflow_attempts_%'"
      )
      puts JSON.generate([before_valid, result.legacy_reconciliation_pending,
        result.reconciliation_state, invalid_interruption, immutable, triggers.length])
    RUBY
  end

  def verify_rollback(environment, attempt_id)
    runner!(environment.merge("ATTEMPT_ID" => attempt_id), <<~'RUBY')
      WorkflowAttempt.reset_column_information
      attempt = WorkflowAttempt.find(ENV.fetch("ATTEMPT_ID"))
      immutable = begin
        attempt.touch
        false
      rescue ActiveRecord::StatementInvalid
        true
      end
      puts JSON.generate([WorkflowAttempt.column_names.include?("legacy_reconciliation_pending"), immutable])
    RUBY
  end

  def migration_result
    Dir.mktmpdir("kos-reconciliation-migration") do |directory|
      env = environment(directory)
      migrate!(env, 20_260_910_000_000)
      repository_id, attempt_id = seed_legacy_attempt(env)
      migrate!(env)
      upgraded = verify_upgrade(env, repository_id, attempt_id)
      rollback!(env)
      [ upgraded, verify_rollback(env, attempt_id) ]
    end
  end

  it "preserves legacy interrupted rows and attempt triggers across migration and rollback" do
    expect(migration_result).to eq([ [ true, false, "no_effect", true, true, 10 ], [ false, true ] ])
  end
end
