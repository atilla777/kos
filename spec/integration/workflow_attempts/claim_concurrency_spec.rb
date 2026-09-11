require "json"
require "open3"
require "rails_helper"
require "tmpdir"

RSpec.describe WorkflowAttempts::Claim, :aggregate_failures do
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
      type = TaskType.find_or_create_by!(id: "quick-fix") do |record|
        record.name = "quick-fix"
        record.workflow_id = "quick-fix"
      end
      definition = JSON.parse(File.read(#{fixture.dump}))
      draft = WorkflowCatalog::ImportDraft.call(workflow_id: "quick-fix", definition: definition,
        expected_lock_version: 0)
      version = WorkflowCatalog::PublishDraft.call(workflow_id: "quick-fix",
        expected_lock_version: draft.lock_version)
      type.update!(current_workflow_version: version)
      repository = Repository.create!(git_common_dir: "/tmp/claim-concurrency.git", task_prefix: "KOS",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      task = Task.create!(repository: repository, sequence: 1, title: "Concurrent claim", task_type: type,
        workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
      puts JSON.generate([repository.id, task.number])
    RUBY
  end

  def runner_script
    <<~'RUBY'
      begin
        sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
        repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
        body = { "task_number" => ENV.fetch("TASK_NUMBER"), "owner_id" => ENV.fetch("OWNER_ID"),
          "lease_seconds" => 300, "preconditions" => { "expected_lock_version" => 0 } }
        result = Idempotency::Execute.call(command: "attempt.claim", key: ENV.fetch("IDEMPOTENCY_KEY"), body: body,
          status: 201, repository: repository, serialize: ->(attempt) { { "id" => attempt.id } }) do
          WorkflowAttempts::Claim.call(repository: repository, task_number: body.fetch("task_number"),
            owner_id: body.fetch("owner_id"), lease_seconds: 300, expected_lock_version: 0,
            idempotency_key: ENV.fetch("IDEMPOTENCY_KEY"))
        end
        puts JSON.generate(result.data)
      rescue OperationError => error
        puts JSON.generate("error" => error.code)
        exit 6
      end
    RUBY
  end

  def run_contenders
    Dir.mktmpdir("kos-attempt-claim") do |directory|
      env = environment(directory)
      output, status = Open3.capture2e(env, File.join(root, "bin/rails"), "db:prepare")
      expect(status).to be_success, output
      repository_id, task_number = prepare_state(env)
      start_file = File.join(directory, "start")
      processes = 2.times.map do |index|
        values = { "START_FILE" => start_file, "REPOSITORY_ID" => repository_id, "TASK_NUMBER" => task_number,
          "OWNER_ID" => "orchestrator-#{index + 1}", "IDEMPOTENCY_KEY" => "claim-key-#{index + 1}" }
        Open3.popen3(env.merge(values), File.join(root, "bin/rails"), "runner", runner_script)
      end
      File.write(start_file, "start")
      results = processes.map do |stdin, stdout, stderr, wait|
        stdin.close
        output = stdout.read
        [ output.empty? ? {} : JSON.parse(output.lines.last), stderr.read, wait.value.exitstatus ]
      end
      state = JSON.parse(run_script(env, <<~'RUBY'))
        task = Task.first
        puts JSON.generate([WorkflowAttempt.count, IdempotencyRecord.count, task.lock_version,
          task.active_attempt_id, WorkflowAttempt.first&.fencing_token])
      RUBY
      [ results, state ]
    end
  end

  it "allows exactly one process to claim the same task lock version" do
    results, state = run_contenders
    expect(results.map { |result| result.fetch(1) }).to all(be_empty)
    expect(results.map(&:last).sort).to eq([ 0, 6 ])
    expect(results.filter_map { |result| result.first["error"] }).to eq([ "stale_lock_version" ])
    expect(state).to eq([ 1, 2, 1, results.filter_map { |result| result.first["id"] }.first, 1 ])
  end
end
