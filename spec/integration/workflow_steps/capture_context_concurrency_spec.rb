require "json"
require "open3"
require "rails_helper"
require "tmpdir"

RSpec.describe WorkflowSteps::CaptureContext, :aggregate_failures do
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
      repository = Repository.create!(git_common_dir: "/tmp/context-concurrency.git", task_prefix: "KOS",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      task = Task.create!(repository: repository, sequence: 1, title: "Concurrent context", task_type: type,
        workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
      attempt = WorkflowAttempts::Claim.call(repository: repository, task_number: task.number,
        owner_id: "orchestrator-1", lease_seconds: 300, expected_lock_version: 0,
        idempotency_key: "context-concurrent-claim")
      reservation = WorktreeReservation.create!(repository: repository, task: task, workflow_attempt: attempt,
        branch: "kos/task-" + task.number, path: "/tmp/context-concurrency-worktree", state: "confirmed",
        fencing_token: attempt.fencing_token, git_common_dir_digest: "sha256:" + ("a" * 64),
        head_sha: "b" * 40, confirmed_at: Time.current)
      task.reload.update!(worktree_reservation: reservation)
      puts JSON.generate([repository.id, attempt.id, task.reload.lock_version, attempt.fencing_token])
    RUBY
  end

  def runner_script
    <<~'RUBY'
      begin
        sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
        repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
        body = { "preconditions" => { "expected_lock_version" => Integer(ENV.fetch("LOCK_VERSION")),
          "attempt_id" => ENV.fetch("ATTEMPT_ID"), "fencing_token" => Integer(ENV.fetch("FENCING_TOKEN")) } }
        result = Idempotency::Execute.call(command: "step.context", key: ENV.fetch("IDEMPOTENCY_KEY"), body: body,
          status: 200, repository: repository, serialize: ->(context) { context }) do
          WorkflowSteps::CaptureContext.call(repository: repository, attempt_id: ENV.fetch("ATTEMPT_ID"),
            fencing_token: Integer(ENV.fetch("FENCING_TOKEN")),
            expected_lock_version: Integer(ENV.fetch("LOCK_VERSION")))
        end
        puts JSON.generate(result.data)
      rescue OperationError => error
        puts JSON.generate("error" => error.code)
        exit 6
      end
    RUBY
  end

  def run_contenders
    Dir.mktmpdir("kos-step-context") do |directory|
      env = environment(directory)
      output, status = Open3.capture2e(env, File.join(root, "bin/rails"), "db:prepare")
      expect(status).to be_success, output
      repository_id, attempt_id, lock_version, fencing_token = prepare_state(env)
      start_file = File.join(directory, "start")
      values = { "START_FILE" => start_file, "REPOSITORY_ID" => repository_id, "ATTEMPT_ID" => attempt_id,
        "LOCK_VERSION" => lock_version.to_s, "FENCING_TOKEN" => fencing_token.to_s }
      processes = 2.times.map do |index|
        Open3.popen3(env.merge(values, "IDEMPOTENCY_KEY" => "context-key-#{index + 1}"),
          File.join(root, "bin/rails"), "runner", runner_script)
      end
      File.write(start_file, "start")
      results = processes.map do |stdin, stdout, stderr, wait|
        stdin.close
        [ JSON.parse(stdout.read.lines.last), stderr.read, wait.value.exitstatus ]
      end
      state = JSON.parse(run_script(env, <<~'RUBY'))
        attempt = WorkflowAttempt.first
        puts JSON.generate([attempt.input_context, attempt.input_context_digest,
          IdempotencyRecord.where(command: "step.context").count])
      RUBY
      [ results, state ]
    end
  end

  def expect_consistent_results(results, state)
    contexts = results.map(&:first)
    expect(results.map { _1.fetch(1) }).to all(be_empty)
    expect(results.map(&:last)).to eq([ 0, 0 ])
    expect(contexts.uniq).to eq([ state.fetch(0) ])
    expect(state.values_at(1, 2)).to eq([ state.dig(0, "input_context_digest"), 2 ])
  end

  it "persists one exact context for simultaneous keys in separate processes" do
    results, state = run_contenders
    expect_consistent_results(results, state)
  end
end
