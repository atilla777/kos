require "json"
require "open3"
require "rails_helper"
require "tmpdir"
require Rails.root.join("db/migrate/20260911010000_add_completed_transition_to_workflow_attempts")

RSpec.describe AddCompletedTransitionToWorkflowAttempts, :aggregate_failures do
  def root
    File.expand_path("../../..", __dir__)
  end

  def environment(directory)
    { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3") }
  end

  def command!(environment, script)
    output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "runner", script)
    expect(status).to be_success, output
    output
  end

  def migrate!(environment, target = nil)
    invocation = target ? "context.migrate(#{target})" : "context.migrate"
    command!(environment, "context = ActiveRecord::Base.connection_pool.migration_context; #{invocation}")
  end

  def seed_attempt(environment)
    JSON.parse(command!(environment, <<~'RUBY').lines.last)
      type = TaskType.create!(id: "quick-fix", name: "quick-fix", workflow_id: "quick-fix")
      digest = "sha256:" + ("a" * 64)
      version = WorkflowVersion.create!(task_type: type, workflow_id: "quick-fix", version: "1.0.0",
        content_digest: digest)
      source = WorkflowState.create!(workflow_version: version, identifier: "planning", initial: true,
        execution_mode: "subagent", instruction: "Plan.", worktree_policy: "none",
        repository_changes_policy: "allowed")
      target = WorkflowState.create!(workflow_version: version, identifier: "development",
        execution_mode: "subagent", instruction: "Develop.", worktree_policy: "none",
        repository_changes_policy: "allowed")
      transition = WorkflowTransition.create!(workflow_version: version, from_state: source, to_state: target)
      other_transition = WorkflowTransition.create!(workflow_version: version, from_state: target, to_state: source)
      version.update!(published_at: Time.current)
      repository = Repository.create!(git_common_dir: "/tmp/completed-transition.git", task_prefix: "KOS",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      task = Task.create!(repository: repository, sequence: 1, title: "Migration", task_type: type,
        workflow_version: version, workflow_state: source)
      now = Time.current
      attempt = WorkflowAttempt.create!(repository: repository, task: task, workflow_state: source,
        owner_id: "owner", idempotency_key: "migration-claim", fencing_token: 1, heartbeat_at: now,
        started_at: now, lease_expires_at: now + 5.minutes, input_context: { "schema_version" => "1" },
        input_context_digest: digest)
      task.update!(active_attempt: attempt)
      puts JSON.generate([task.id, attempt.id, transition.id, other_transition.id, digest])
    RUBY
  end

  def verify_upgrade(environment, task_id, attempt_id, transition_id, other_transition_id, digest)
    values = { "TASK_ID" => task_id, "ATTEMPT_ID" => attempt_id, "TRANSITION_ID" => transition_id,
      "OTHER_TRANSITION_ID" => other_transition_id, "DIGEST" => digest }
    JSON.parse(command!(environment.merge(values), <<~'RUBY').lines.last)
      WorkflowAttempt.reset_column_information
      task = Task.find(ENV.fetch("TASK_ID"))
      attempt = WorkflowAttempt.find(ENV.fetch("ATTEMPT_ID"))
      transition = WorkflowTransition.find(ENV.fetch("TRANSITION_ID"))
      inserted_id = SecureRandom.uuid
      inserted_manifest = { "schema_version" => "1", "attempt_id" => inserted_id,
        "input_context_digest" => ENV.fetch("DIGEST"), "outcome" => "succeeded", "artifacts" => [] }
      insert_rejected = begin
        WorkflowAttempt.create!(id: inserted_id, repository: task.repository, task: task,
          workflow_state: attempt.workflow_state, owner_id: "inserted", idempotency_key: "inserted-success",
          state: "succeeded", fencing_token: 2, heartbeat_at: Time.current, started_at: Time.current,
          completed_at: Time.current, input_context: { "schema_version" => "1" },
          input_context_digest: ENV.fetch("DIGEST"), result_manifest: inserted_manifest)
        false
      rescue ActiveRecord::StatementInvalid
        true
      end
      task.update!(active_attempt: nil, workflow_state: transition.to_state)
      manifest = { "schema_version" => "1", "attempt_id" => attempt.id,
        "input_context_digest" => ENV.fetch("DIGEST"), "outcome" => "succeeded", "artifacts" => [] }
      attributes = { state: "succeeded", heartbeat_at: Time.current, lease_expires_at: nil,
        completed_at: Time.current, result_manifest: manifest }
      missing_rejected = begin
        attempt.update!(attributes)
        false
      rescue ActiveRecord::StatementInvalid
        true
      end
      mismatch_rejected = begin
        attempt.update!(attributes.merge(completed_transition_id: ENV.fetch("OTHER_TRANSITION_ID")))
        false
      rescue ActiveRecord::StatementInvalid
        true
      end
      attempt.update!(attributes.merge(completed_transition: transition))
      triggers = ActiveRecord::Base.connection.select_values(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'workflow_attempts_%'"
      )
      puts JSON.generate([insert_rejected, missing_rejected, mismatch_rejected,
        attempt.completed_transition_id, triggers.sort])
    RUBY
  end

  def verify_rollback(environment, attempt_id)
    JSON.parse(command!(environment.merge("ATTEMPT_ID" => attempt_id), <<~'RUBY').lines.last)
      WorkflowAttempt.reset_column_information
      columns = WorkflowAttempt.column_names
      attempt = WorkflowAttempt.find(ENV.fetch("ATTEMPT_ID"))
      immutable = begin
        attempt.touch
        false
      rescue ActiveRecord::StatementInvalid
        true
      end
      triggers = ActiveRecord::Base.connection.select_values(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'workflow_attempts_%'"
      )
      puts JSON.generate([columns.include?("completed_transition_id"), immutable, triggers.sort])
    RUBY
  end

  def migration_summary
    Dir.mktmpdir("kos-completed-transition") do |directory|
      env = environment(directory)
      migrate!(env, 20_260_911_000_000)
      original_triggers = attempt_trigger_names(env)
      task_id, attempt_id, transition_id, other_transition_id, digest = seed_attempt(env)
      migrate!(env, 20_260_911_010_000)
      upgraded = verify_upgrade(env, task_id, attempt_id, transition_id, other_transition_id, digest)
      command!(env, "ActiveRecord::Base.connection_pool.migration_context.rollback(1)")
      [ original_triggers, upgraded, verify_rollback(env, attempt_id) ]
    end
  end

  def attempt_trigger_names(environment)
    JSON.parse(command!(environment, <<~'RUBY').lines.last)
      values = ActiveRecord::Base.connection.select_values(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'workflow_attempts_%' ORDER BY name"
      )
      puts JSON.generate(values)
    RUBY
  end

  def expect_valid_summary(original, upgraded, rolled_back)
    expect(upgraded.values_at(0, 1, 2, 3)).to eq([ true, true, true, upgraded.fetch(3) ])
    expect(upgraded.last).to match_array(original + %w[workflow_attempts_completed_transition_insert
      workflow_attempts_completed_transition_update])
    expect(rolled_back.values_at(0, 1)).to eq([ false, true ])
    expect(rolled_back.last).to eq(original)
  end

  it "preserves attempt guards across upgrade and rollback" do
    original, upgraded, rolled_back = migration_summary
    expect_valid_summary(original, upgraded, rolled_back)
  end
end
