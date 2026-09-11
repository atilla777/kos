require "json"
require "open3"
require "rails_helper"
require "tmpdir"
require "timeout"

RSpec.describe Idempotency::Execute, :aggregate_failures do
  def root
    File.expand_path("../../..", __dir__)
  end

  def environment(directory)
    { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3"),
      "START_FILE" => File.join(directory, "start") }
  end

  def prepare(environment)
    _output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "db:prepare")
    expect(status).to be_success
  end

  def fixture
    File.join(root, "spec/fixtures/workflow_definitions/v1/valid/quick-fix.json")
  end

  def runner_script
    <<~RUBY
      begin
        sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
        if ENV["ATTEMPT_FILE"]
          idempotency_selects = 0
          ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
            next unless payload.fetch(:sql).match?(/SELECT .*idempotency_records/)

            idempotency_selects += 1
            File.write(ENV.fetch("ATTEMPT_FILE"), "attempt") if idempotency_selects == 2
          end
        end
        definition = JSON.parse(File.read(#{fixture.dump}))
        definition["version"] = ENV.fetch("DEFINITION_VERSION", definition.fetch("version"))
        operation = ENV.fetch("OPERATION", "import")
        expected_lock_version = operation == "import" ? 0 : 1
        body = case operation
               when "import", "replace"
                 { "workflow_id" => "quick-fix", "definition" => definition,
                   "expected_lock_version" => expected_lock_version }
               when "publish"
                 { "workflow_id" => "quick-fix", "expected_lock_version" => 1 }
               when "activate"
                 { "task_type_id" => "quick-fix", "workflow_version_id" => ENV.fetch("WORKFLOW_VERSION_ID"),
                   "expected_lock_version" => 0 }
               end
        command = "workflow_catalog." + operation
        result = Idempotency::Execute.call(command: command, key: ENV.fetch("IDEMPOTENCY_KEY"), body: body,
          status: 200, serialize: ->(record) { { "id" => record.id } }) do
          File.write(ENV.fetch("ENTERED_FILE"), "entered") if ENV["ENTERED_FILE"]
          sleep 0.01 until !ENV["RELEASE_FILE"] || File.exist?(ENV.fetch("RELEASE_FILE"))
          case operation
          when "import", "replace"
            WorkflowCatalog::ImportDraft.call(workflow_id: "quick-fix", definition: definition,
              expected_lock_version: expected_lock_version)
          when "publish"
            WorkflowCatalog::PublishDraft.call(workflow_id: "quick-fix", expected_lock_version: 1)
          when "activate"
            WorkflowCatalog::ActivateVersion.call(task_type_id: "quick-fix",
              workflow_version_id: ENV.fetch("WORKFLOW_VERSION_ID"), expected_lock_version: 0)
          end
        end
        puts JSON.generate(result.data)
      rescue WorkflowCatalog::Error => error
        puts JSON.generate("error" => error.code)
        exit 6
      end
    RUBY
  end

  def run_pair(environment, entrants)
    directory = File.dirname(environment.fetch("KOS_DATABASE_PATH"))
    entered = File.join(directory, "entered-first")
    attempted = File.join(directory, "attempted-second")
    starts = Array.new(2) { |index| File.join(directory, "start-#{index}") }
    release = File.join(directory, "release-first")
    processes = entrants.map.with_index do |entrant, index|
      synchronization = { "START_FILE" => starts.fetch(index) }
      synchronization.merge!("ENTERED_FILE" => entered, "RELEASE_FILE" => release) if index.zero?
      synchronization["ATTEMPT_FILE"] = attempted unless index.zero?
      Open3.popen3(environment.merge(entrant).merge(synchronization), File.join(root, "bin/rails"), "runner", runner_script)
    end
    File.write(starts.first, "start")
    wait_for(entered)
    File.write(starts.last, "start")
    wait_for(attempted)
    File.write(release, "release")
    processes.map do |stdin, stdout, stderr, wait|
      stdin.close
      output = stdout.read
      [ output.empty? ? {} : JSON.parse(output.lines.last), stderr.read, wait.value.exitstatus ]
    end
  end

  def wait_for(path)
    Timeout.timeout(10) { sleep 0.01 until File.exist?(path) }
  end

  def run_script(environment, script)
    output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "runner", script)
    expect(status).to be_success, output
    output.lines.last
  end

  def import_initial_draft(environment)
    run_script(environment, <<~RUBY)
      definition = JSON.parse(File.read(#{fixture.dump}))
      WorkflowCatalog::ImportDraft.call(workflow_id: "quick-fix", definition: definition, expected_lock_version: 0)
    RUBY
  end

  def prepare_versions(environment)
    JSON.parse(run_script(environment, <<~RUBY))
      definition = JSON.parse(File.read(#{fixture.dump}))
      WorkflowCatalog::ImportDraft.call(workflow_id: "quick-fix", definition: definition, expected_lock_version: 0)
      first = WorkflowCatalog::PublishDraft.call(workflow_id: "quick-fix", expected_lock_version: 1)
      definition["version"] = "2.0.0"
      WorkflowCatalog::ImportDraft.call(workflow_id: "quick-fix", definition: definition, expected_lock_version: 1)
      second = WorkflowCatalog::PublishDraft.call(workflow_id: "quick-fix", expected_lock_version: 2)
      puts JSON.generate([first.id, second.id])
    RUBY
  end

  def persisted_state(environment)
    JSON.parse(run_script(environment, <<~'RUBY'))
      draft = WorkflowDraft.first
      task_type = TaskType.find("quick-fix")
      puts JSON.generate([WorkflowDraft.count, WorkflowVersion.count, IdempotencyRecord.count,
        draft&.lock_version, task_type.lock_version, task_type.current_workflow_version_id])
    RUBY
  end

  def contenders(values, attributes = {})
    values.map { |value| { "IDEMPOTENCY_KEY" => value }.merge(attributes) }
  end

  def results_for(entrants, setup: nil)
    Dir.mktmpdir("kos-concurrency") do |directory|
      env = environment(directory)
      prepare(env)
      prepared = setup&.call(env)
      actual_entrants = entrants.respond_to?(:call) ? entrants.call(prepared) : entrants
      results = run_pair(env, actual_entrants)
      yield results, persisted_state(env), prepared
    end
  end

  def result_summary(results, state)
    [ results.map(&:last).sort, results.filter_map { |result| result.first["error"] },
      results.filter_map { |result| result.first["id"] }.uniq.length, state.first(5) ]
  end

  def replacement_contenders
    contenders(%w[first-replace-key second-replace-key], "OPERATION" => "replace").each_with_index do |entrant, index|
      entrant["DEFINITION_VERSION"] = "1.#{index + 1}.0"
    end
  end

  def activation_contenders(version_ids)
    contenders(%w[first-activate-key second-activate-key], "OPERATION" => "activate").each_with_index do |entrant, index|
      entrant["WORKFLOW_VERSION_ID"] = version_ids.fetch(index)
    end
  end

  it "executes concurrent repeats of one idempotency key only once" do
    results_for(contenders(%w[same-import-key same-import-key])) do |results, state|
      expect(result_summary(results, state)).to eq([ [ 0, 0 ], [], 1, [ 1, 0, 1, 1, 0 ] ])
    end
  end

  it "allows only one concurrent first import with different keys" do
    results_for(contenders(%w[first-import-key second-import-key])) do |results, state|
      expect(result_summary(results, state)).to eq([ [ 0, 6 ], [ "stale_lock_version" ], 1, [ 1, 0, 2, 1, 0 ] ])
    end
  end

  it "returns the same immutable version for concurrent publication with different keys" do
    entrants = contenders(%w[first-publish-key second-publish-key], "OPERATION" => "publish")
    results_for(entrants, setup: method(:import_initial_draft)) do |results, state|
      expect(result_summary(results, state)).to eq([ [ 0, 0 ], [], 1, [ 1, 1, 2, 1, 0 ] ])
    end
  end

  it "allows only one concurrent draft replacement from the same lock version" do
    results_for(replacement_contenders, setup: method(:import_initial_draft)) do |results, state|
      expect(result_summary(results, state)).to eq([ [ 0, 6 ], [ "stale_lock_version" ], 1, [ 1, 0, 2, 2, 0 ] ])
    end
  end

  it "allows only one concurrent activation from the same lock version" do
    results_for(method(:activation_contenders), setup: method(:prepare_versions)) do |results, state, version_ids|
      expect(result_summary(results, state)).to eq([ [ 0, 6 ], [ "stale_lock_version" ], 1, [ 1, 2, 2, 2, 1 ] ])
      expect(version_ids).to include(state.last)
    end
  end
end
