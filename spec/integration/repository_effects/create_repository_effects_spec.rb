require "json"
require "open3"
require "rails_helper"
require "tmpdir"
require Rails.root.join("db/migrate/20260912000000_create_repository_effects")

RSpec.describe CreateRepositoryEffects, :aggregate_failures do
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

  def runner!(environment, script)
    JSON.parse(command!(environment, script).lines.last)
  end

  def seed_state(environment)
    fixture = File.join(root, "spec/fixtures/workflow_definitions/v1/valid/quick-fix.json")
    runner!(environment, <<~RUBY)
      type = TaskType.find_or_create_by!(id: "quick-fix") do |record|
        record.name = "quick-fix"
        record.workflow_id = "quick-fix"
      end
      definition = JSON.parse(File.read(#{fixture.dump}))
      draft = WorkflowCatalog::ImportDraft.call(workflow_id: "quick-fix", definition: definition,
        expected_lock_version: 0)
      version = WorkflowCatalog::PublishDraft.call(workflow_id: "quick-fix",
        expected_lock_version: draft.lock_version)
      repository = Repository.create!(git_common_dir: "/tmp/effect-migration.git", task_prefix: "KOS",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      task = Task.create!(repository: repository, sequence: 1, title: "Existing task", task_type: type,
        workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
      now = Time.current
      attempt = WorkflowAttempt.create!(repository: repository, task: task, workflow_state: task.workflow_state,
        owner_id: "owner", idempotency_key: "migration-claim", fencing_token: 1,
        started_at: now, heartbeat_at: now, lease_expires_at: now + 300)
      task.update!(active_attempt: attempt)
      digest = "sha256:" + ("a" * 64)
      attempt.update!(input_context: { "allowed_repository_effects" => ["fetch"] }, input_context_digest: digest)
      puts JSON.generate([repository.id, task.number, attempt.id, digest])
    RUBY
  end

  def migration_result
    Dir.mktmpdir("kos-effect-migration") do |directory|
      env = environment(directory)
      migrate!(env, 20_260_911_030_000)
      repository_id, task_number, attempt_id, digest = seed_state(env)
      migrate!(env)
      upgraded = runner!(env.merge("REPOSITORY_ID" => repository_id, "TASK_NUMBER" => task_number,
        "ATTEMPT_ID" => attempt_id, "DIGEST" => digest), <<~'RUBY')
        repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
        attempt = WorkflowAttempt.find(ENV.fetch("ATTEMPT_ID"))
        request = { "schema_version" => "1", "attempt_id" => attempt.id,
          "input_context_digest" => ENV.fetch("DIGEST"),
          "effect" => { "operation" => "fetch", "remote" => "origin", "ref" => "refs/heads/main" } }
        effect = RepositoryEffects::Prepare.call(repository: repository, task_number: ENV.fetch("TASK_NUMBER"),
          effect_request: request, attempt_id: attempt.id, fencing_token: attempt.fencing_token,
          expected_lock_version: attempt.task.lock_version)
        guarded = begin
          attempt.update_columns(state: "failed", lease_expires_at: nil, completed_at: Time.current,
            result_manifest: {}.to_json)
          false
        rescue ActiveRecord::StatementInvalid
          true
        end
        puts JSON.generate([RepositoryEffect.count, effect.state, guarded, Task.count, WorkflowAttempt.count])
      RUBY
      command!(env, "ActiveRecord::Base.connection_pool.migration_context.rollback(1)")
      rolled_back = runner!(env, <<~'RUBY')
        tables = ActiveRecord::Base.connection.tables
        puts JSON.generate([tables.include?("repository_effects"), Task.count, WorkflowAttempt.count])
      RUBY
      [ upgraded, rolled_back ]
    end
  end

  it "upgrades populated execution state and rolls back without changing existing rows" do
    expect(migration_result).to eq([ [ 1, "prepared", true, 1, 1 ], [ false, 1, 1 ] ])
  end
end
