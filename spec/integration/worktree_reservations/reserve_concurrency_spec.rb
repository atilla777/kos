require "json"
require "open3"
require "rails_helper"
require "tmpdir"

RSpec.describe WorktreeReservations::Reserve, :aggregate_failures do
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
    JSON.parse(run_script(environment.merge("FIXTURE" => fixture), <<~'RUBY'))
      type = TaskType.find_or_create_by!(id: "quick-fix") do |record|
        record.name = "quick-fix"
        record.workflow_id = "quick-fix"
      end
      definition = JSON.parse(File.read(ENV.fetch("FIXTURE")))
      draft = WorkflowCatalog::ImportDraft.call(workflow_id: "quick-fix", definition: definition,
        expected_lock_version: 0)
      version = WorkflowCatalog::PublishDraft.call(workflow_id: "quick-fix",
        expected_lock_version: draft.lock_version)
      type.update!(current_workflow_version: version)
      repositories = ["KOS", "ALT"].map.with_index do |prefix, index|
        repository = Repository.create!(git_common_dir: "/tmp/reserve-concurrency-#{index}.git",
          task_prefix: prefix, trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git",
          base_ref: "refs/heads/main")
        task = Task.create!(repository: repository, sequence: 1, title: "Concurrent reserve", task_type: type,
          workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
        attempt = WorkflowAttempts::Claim.call(repository: repository, task_number: task.number,
          owner_id: "orchestrator-#{index}", lease_seconds: 300, expected_lock_version: 0,
          idempotency_key: "claim-key-#{index}")
        [repository.id, task.number, attempt.id, attempt.fencing_token]
      end
      puts JSON.generate(repositories)
    RUBY
  end

  def runner_script
    <<~'RUBY'
      begin
        sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
        repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
        body = { "task_number" => ENV.fetch("TASK_NUMBER"), "branch" => ENV.fetch("BRANCH"),
          "path" => "/tmp/worktrees/shared", "preconditions" => { "expected_lock_version" => 1,
            "attempt_id" => ENV.fetch("ATTEMPT_ID"), "fencing_token" => ENV.fetch("FENCING_TOKEN").to_i } }
        result = Idempotency::Execute.call(command: "worktree.reserve", key: ENV.fetch("IDEMPOTENCY_KEY"),
          body: body, status: 201, repository: repository,
          serialize: ->(reservation) { { "id" => reservation.id } }) do
          WorktreeReservations::Reserve.call(repository: repository, task_number: body.fetch("task_number"),
            branch: body.fetch("branch"), path: body.fetch("path"),
            attempt_id: body.dig("preconditions", "attempt_id"),
            fencing_token: body.dig("preconditions", "fencing_token"), expected_lock_version: 1)
        end
        puts JSON.generate(result.data)
      rescue OperationError => error
        puts JSON.generate("error" => error.code)
        exit 6
      end
    RUBY
  end

  def contender(environment, start_file, identity, index)
    repository_id, task_number, attempt_id, fencing_token = identity
    values = { "START_FILE" => start_file, "REPOSITORY_ID" => repository_id, "TASK_NUMBER" => task_number,
      "BRANCH" => "kos/task-#{task_number}", "ATTEMPT_ID" => attempt_id,
      "FENCING_TOKEN" => fencing_token.to_s, "IDEMPOTENCY_KEY" => "reserve-key-#{index}" }
    Open3.popen3(environment.merge(values), File.join(root, "bin/rails"), "runner", runner_script)
  end

  def run_contenders
    Dir.mktmpdir("kos-worktree-reserve") do |directory|
      env = environment(directory)
      output, status = Open3.capture2e(env, File.join(root, "bin/rails"), "db:prepare")
      expect(status).to be_success, output
      identities = prepare_state(env)
      start_file = File.join(directory, "start")
      processes = identities.map.with_index { |identity, index| contender(env, start_file, identity, index) }
      File.write(start_file, "start")
      results = processes.map do |stdin, stdout, stderr, wait|
        stdin.close
        output = stdout.read
        [ output.empty? ? {} : JSON.parse(output.lines.last), stderr.read, wait.value.exitstatus ]
      end
      state = JSON.parse(run_script(env, <<~'RUBY'))
        puts JSON.generate([WorktreeReservation.count, IdempotencyRecord.count,
          Task.order(:repository_id).pluck(:lock_version).sort])
      RUBY
      [ results, state ]
    end
  end

  it "allows only one task to reserve an installation-wide path" do
    results, state = run_contenders
    expect(results.map { |result| result.fetch(1) }).to all(be_empty)
    expect(results.map(&:last).sort).to eq([ 0, 6 ])
    expect(results.filter_map { |result| result.first["error"] }).to eq([ "invalid_transition" ])
    expect(state).to eq([ 1, 2, [ 1, 2 ] ])
  end
end
