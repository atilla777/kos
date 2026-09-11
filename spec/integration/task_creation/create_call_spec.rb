require "json"
require "open3"
require "rails_helper"
require "tmpdir"
require "timeout"

RSpec.describe TaskCreation::Create, ".call", :aggregate_failures do
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

  def prepare(environment)
    _output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "db:prepare")
    expect(status).to be_success
    fixture = File.join(root, "spec/fixtures/workflow_definitions/v1/valid/quick-fix.json")
    JSON.parse(run_script(environment, <<~RUBY))
      repository = Repository.create!(git_common_dir: "/tmp/concurrent.git", task_prefix: "KOS",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      definition = JSON.parse(File.read(#{fixture.dump}))
      draft = WorkflowCatalog::ImportDraft.call(workflow_id: "quick-fix", definition: definition,
        expected_lock_version: 0)
      version = WorkflowCatalog::PublishDraft.call(workflow_id: "quick-fix",
        expected_lock_version: draft.lock_version)
      TaskType.find("quick-fix").update!(current_workflow_version: version)
      definition["version"] = "2.0.0"
      draft = WorkflowCatalog::ImportDraft.call(workflow_id: "quick-fix", definition: definition,
        expected_lock_version: draft.lock_version)
      second = WorkflowCatalog::PublishDraft.call(workflow_id: "quick-fix",
        expected_lock_version: draft.lock_version)
      puts JSON.generate("repository_id" => repository.id, "first_version_id" => version.id,
        "second_version_id" => second.id)
    RUBY
  end

  def runner_script
    <<~'RUBY'
      begin
        sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
        if ENV["ATTEMPT_FILE"]
          selects = 0
          ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
            next unless payload.fetch(:sql).match?(/SELECT .*idempotency_records/)

            selects += 1
            File.write(ENV.fetch("ATTEMPT_FILE"), "attempt") if selects == 2
          end
        end
        if ENV["SELECTED_FILE"]
          selected = false
          ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
            next if selected || !payload.fetch(:sql).include?("workflow_states")

            selected = true
            File.write(ENV.fetch("SELECTED_FILE"), "selected")
            sleep 0.01 until File.exist?(ENV.fetch("RELEASE_FILE"))
          end
        end
        repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
        body = { "title" => ENV.fetch("TITLE"), "task_type" => "quick-fix" }
        result = Idempotency::Execute.call(command: "task.create", key: ENV.fetch("IDEMPOTENCY_KEY"), body: body,
          status: 201, repository: repository, serialize: ->(task) { { "number" => task.number } }) do
          if ENV["ENTERED_FILE"]
            File.write(ENV.fetch("ENTERED_FILE"), "entered")
            sleep 0.01 until File.exist?(ENV.fetch("RELEASE_FILE"))
          end
          TaskCreation::Create.call(repository: repository, title: body.fetch("title"),
            task_type_name: body.fetch("task_type"))
        end
        puts JSON.generate(result.data)
      rescue OperationError => error
        puts JSON.generate("error" => error.code)
        exit 6
      end
    RUBY
  end

  def wait_for(path)
    Timeout.timeout(10) { sleep 0.01 until File.exist?(path) }
  end

  def run_pair(environment, repository_id, keys)
    directory = File.dirname(environment.fetch("KOS_DATABASE_PATH"))
    entered = File.join(directory, "entered")
    attempted = File.join(directory, "attempted")
    release = File.join(directory, "release")
    starts = Array.new(2) { |index| File.join(directory, "start-#{index}") }
    processes = keys.map.with_index do |key, index|
      values = { "REPOSITORY_ID" => repository_id, "IDEMPOTENCY_KEY" => key,
        "TITLE" => "Task #{key}", "START_FILE" => starts.fetch(index) }
      values.merge!("ENTERED_FILE" => entered, "RELEASE_FILE" => release) if index.zero?
      values["ATTEMPT_FILE"] = attempted unless index.zero?
      Open3.popen3(environment.merge(values), File.join(root, "bin/rails"), "runner", runner_script)
    end
    File.write(starts.first, "start")
    wait_for(entered)
    File.write(starts.last, "start")
    wait_for(attempted)
    File.write(release, "release")
    processes.map do |stdin, stdout, stderr, wait|
      stdin.close
      output = stdout.read
      [ JSON.parse(output.lines.last), stderr.read, wait.value.exitstatus ]
    end
  end

  def persisted_state(environment)
    JSON.parse(run_script(environment, <<~'RUBY'))
      puts JSON.generate("numbers" => Task.order(:sequence).map(&:number),
        "next_sequence" => Repository.first.next_task_sequence,
        "idempotency_count" => IdempotencyRecord.where(command: "task.create").count)
    RUBY
  end

  def with_results(keys)
    Dir.mktmpdir("kos-task-creation") do |directory|
      env = environment(directory)
      repository_id = prepare(env).fetch("repository_id")
      yield run_pair(env, repository_id, keys), persisted_state(env)
    end
  end

  def activation_race(environment, prepared)
    directory = File.dirname(environment.fetch("KOS_DATABASE_PATH"))
    start = File.join(directory, "race-start")
    selected = File.join(directory, "version-selected")
    release = File.join(directory, "release-selection")
    values = { "REPOSITORY_ID" => prepared.fetch("repository_id"), "IDEMPOTENCY_KEY" => "race-task-key",
      "TITLE" => "Racing task", "START_FILE" => start, "SELECTED_FILE" => selected, "RELEASE_FILE" => release }
    process = Open3.popen3(environment.merge(values), File.join(root, "bin/rails"), "runner", runner_script)
    File.write(start, "start")
    wait_for(selected)
    blocked = blocked_activation(environment, prepared.fetch("second_version_id"))
    File.write(release, "release")
    creation = process_result(process)
    activate_second(environment, prepared.fetch("second_version_id"))
    [ creation, blocked ]
  end

  def blocked_activation(environment, version_id)
    JSON.parse(run_script(environment, <<~RUBY))
      ActiveRecord::Base.connection.execute("PRAGMA busy_timeout = 1")
      begin
        WorkflowCatalog::ActivateVersion.call(task_type_id: "quick-fix", workflow_version_id: #{version_id.dump},
          expected_lock_version: 1)
        puts JSON.generate("blocked" => false)
      rescue ActiveRecord::StatementInvalid => error
        puts JSON.generate("blocked" => error.cause.is_a?(SQLite3::BusyException))
      end
    RUBY
  end

  def activate_second(environment, version_id)
    run_script(environment, <<~RUBY)
      WorkflowCatalog::ActivateVersion.call(task_type_id: "quick-fix", workflow_version_id: #{version_id.dump},
        expected_lock_version: 1)
    RUBY
  end

  def process_result(process)
    stdin, stdout, stderr, wait = process
    stdin.close
    [ JSON.parse(stdout.read.lines.last), stderr.read, wait.value.exitstatus ]
  end

  def pinned_state(environment)
    JSON.parse(run_script(environment, <<~'RUBY'))
      task = Task.first
      puts JSON.generate("task_version" => task.workflow_version_id,
        "state_version" => task.workflow_state.workflow_version_id,
        "current_version" => TaskType.find("quick-fix").current_workflow_version_id)
    RUBY
  end

  def activation_race_result
    Dir.mktmpdir("kos-task-activation") do |directory|
      env = environment(directory)
      prepared = prepare(env)
      creation, blocked = activation_race(env, prepared)
      [ creation.last, blocked.fetch("blocked"), pinned_state(env), prepared ]
    end
  end

  it "executes concurrent repeats with one key only once" do
    with_results(%w[same-task-key same-task-key]) do |results, state|
      expect([ results.map(&:last), results.map(&:first).uniq, state ])
        .to eq([ [ 0, 0 ], [ { "number" => "KOS-000001" } ],
          { "numbers" => [ "KOS-000001" ], "next_sequence" => 2, "idempotency_count" => 1 } ])
    end
  end

  it "allocates unique monotonic numbers for concurrent distinct requests" do
    with_results(%w[first-task-key second-task-key]) do |results, state|
      expect([ results.map(&:last), results.map { |result| result.first.fetch("number") }.sort, state ])
        .to eq([ [ 0, 0 ], %w[KOS-000001 KOS-000002],
          { "numbers" => %w[KOS-000001 KOS-000002], "next_sequence" => 3, "idempotency_count" => 2 } ])
    end
  end

  it "retries safely when activation commits after workflow selection" do
    status, blocked, state, versions = activation_race_result

    expect([ status, blocked, state ]).to eq([ 0, true,
      { "task_version" => versions.fetch("first_version_id"),
        "state_version" => versions.fetch("first_version_id"),
        "current_version" => versions.fetch("second_version_id") } ])
  end
end
