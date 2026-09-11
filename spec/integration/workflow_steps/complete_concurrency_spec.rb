require "json"
require "open3"
require "rails_helper"
require "tmpdir"

RSpec.describe WorkflowSteps::Complete, :aggregate_failures do
  def root
    File.expand_path("../../..", __dir__)
  end

  def environment(directory)
    { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3") }
  end

  def run_script(environment, script)
    output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "runner", script)
    expect(status).to be_success, output
    output.lines.last
  end

  def prepare_state(environment)
    fixture = File.join(root, "spec/fixtures/workflow_definitions/v1/valid/quick-fix.json")
    JSON.parse(run_script(environment, <<~RUBY))
      type = TaskType.find_by!(id: "quick-fix")
      definition = JSON.parse(File.read(#{fixture.dump}))
      draft = WorkflowCatalog::ImportDraft.call(workflow_id: "quick-fix", definition: definition,
        expected_lock_version: 0)
      version = WorkflowCatalog::PublishDraft.call(workflow_id: "quick-fix",
        expected_lock_version: draft.lock_version)
      repository = Repository.create!(git_common_dir: "/tmp/complete-concurrency.git", task_prefix: "KOS",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      task = Task.create!(repository: repository, sequence: 1, title: "Concurrent completion", task_type: type,
        workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
      attempt = WorkflowAttempts::Claim.call(repository: repository, task_number: task.number,
        owner_id: "orchestrator-1", lease_seconds: 300, expected_lock_version: 0,
        idempotency_key: "concurrent-claim")
      digest = "sha256:#{"a" * 64}"
      attempt.update!(input_context: { "schema_version" => "1" }, input_context_digest: digest)
      artifact = { "schema_version" => "1", "type" => "document", "state" => "produced",
        "producer" => "workflow-step", "metadata" => { "kind" => "document", "path" => "tasks/KOS-000001/task.md",
          "commit_sha" => "#{"a" * 40}", "content_digest" => digest } }
      puts JSON.generate([repository.id, task.number, attempt.id, artifact, digest])
    RUBY
  end

  def runner_script
    <<~'RUBY'
      begin
        sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
        repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
        artifact = JSON.parse(ENV.fetch("ARTIFACT"))
        digest = ENV.fetch("DIGEST")
        body = { "task_number" => ENV.fetch("TASK_NUMBER"), "to_status" => "development",
          "result_manifest" => { "schema_version" => "1", "attempt_id" => ENV.fetch("ATTEMPT_ID"),
            "input_context_digest" => digest, "outcome" => "succeeded", "artifacts" => [artifact] },
          "preconditions" => { "expected_lock_version" => 1, "attempt_id" => ENV.fetch("ATTEMPT_ID"),
            "fencing_token" => 1 } }
        canonical = WorkflowCatalog::CanonicalDefinition.canonical_json([artifact])
        verification = RepositoryEvidence::VerifyArtifacts::Verification.new(repository.id, body.fetch("task_number"),
          "sha256:#{Digest::SHA256.hexdigest(canonical)}")
        result = Idempotency::Execute.call(command: "step.complete", key: ENV.fetch("IDEMPOTENCY_KEY"), body: body,
          status: 200, repository: repository, serialize: ->(value) { { "task_id" => value.task.id,
            "artifact_ids" => value.artifacts.map(&:id) } }) do
          WorkflowSteps::Complete.call(repository: repository, task_number: body.fetch("task_number"),
            to_status: "development", attempt_id: ENV.fetch("ATTEMPT_ID"), fencing_token: 1,
            expected_lock_version: 1, manifest: body.fetch("result_manifest"), verified_evidence: verification)
        end
        puts JSON.generate(result.data)
      rescue OperationError => error
        puts JSON.generate("error" => error.code)
        exit 6
      end
    RUBY
  end

  def run_contenders
    Dir.mktmpdir("kos-step-complete") do |directory|
      env = environment(directory)
      output, status = Open3.capture2e(env, File.join(root, "bin/rails"), "db:prepare")
      expect(status).to be_success, output
      repository_id, task_number, attempt_id, artifact, digest = prepare_state(env)
      start_file = File.join(directory, "start")
      values = { "START_FILE" => start_file, "REPOSITORY_ID" => repository_id, "TASK_NUMBER" => task_number,
        "ATTEMPT_ID" => attempt_id, "ARTIFACT" => JSON.generate(artifact), "DIGEST" => digest }
      processes = 2.times.map do |index|
        Open3.popen3(env.merge(values, "IDEMPOTENCY_KEY" => "complete-key-#{index + 1}"),
          File.join(root, "bin/rails"), "runner", runner_script)
      end
      File.write(start_file, "start")
      results = processes.map do |stdin, stdout, stderr, wait|
        stdin.close
        output = stdout.read
        [ output.empty? ? {} : JSON.parse(output.lines.last), stderr.read, wait.value.exitstatus ]
      end
      state = JSON.parse(run_script(env, <<~'RUBY'))
        task = Task.first
        attempt = WorkflowAttempt.first
        puts JSON.generate([TaskArtifact.count, IdempotencyRecord.where(command: "step.complete").count,
          task.workflow_state.identifier, task.lock_version, task.active_attempt_id, attempt.state])
      RUBY
      [ results, state ]
    end
  end

  it "allows only one process to complete the active attempt" do
    results, state = run_contenders
    expect(results.map { _1.fetch(1) }).to all(be_empty)
    expect(results.map(&:last).sort).to eq([ 0, 6 ])
    expect(results.filter_map { _1.first["error"] }).to eq([ "stale_lock_version" ])
    expect(state).to eq([ 1, 2, "development", 2, nil, "succeeded" ])
  end
end
