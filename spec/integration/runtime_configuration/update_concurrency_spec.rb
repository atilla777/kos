require "json"
require "open3"
require "rails_helper"
require "tmpdir"
require "timeout"

RSpec.describe RuntimeConfiguration::Update, :aggregate_failures do
  def root
    File.expand_path("../../..", __dir__)
  end

  def environment(directory)
    { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3") }
  end

  def prepare(environment)
    output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "db:prepare")
    expect(status).to be_success, output
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
        body = { "retrospective_enabled" => true, "expected_lock_version" => 0 }
        result = Idempotency::Execute.call(command: "runtime_config.update", key: ENV.fetch("IDEMPOTENCY_KEY"),
          body: body, status: 200,
          serialize: ->(record) { record.attributes.slice("retrospective_enabled", "lock_version") }) do
          File.write(ENV.fetch("ENTERED_FILE"), "entered") if ENV["ENTERED_FILE"]
          sleep 0.01 until !ENV["RELEASE_FILE"] || File.exist?(ENV.fetch("RELEASE_FILE"))
          RuntimeConfiguration::Update.call(retrospective_enabled: true, expected_lock_version: 0)
        end
        puts JSON.generate(result.data)
      rescue OperationError => error
        puts JSON.generate("error" => error.code)
        exit 6
      end
    RUBY
  end

  def run_pair(environment, keys)
    directory = File.dirname(environment.fetch("KOS_DATABASE_PATH"))
    entered = File.join(directory, "entered-first")
    attempted = File.join(directory, "attempted-second")
    starts = Array.new(2) { |index| File.join(directory, "start-#{index}") }
    release = File.join(directory, "release-first")
    processes = keys.map.with_index do |key, index|
      synchronization = { "IDEMPOTENCY_KEY" => key, "START_FILE" => starts.fetch(index) }
      synchronization.merge!("ENTERED_FILE" => entered, "RELEASE_FILE" => release) if index.zero?
      synchronization["ATTEMPT_FILE"] = attempted unless index.zero?
      Open3.popen3(environment.merge(synchronization), File.join(root, "bin/rails"), "runner", runner_script)
    end
    File.write(starts.first, "start")
    wait_for(entered)
    File.write(starts.last, "start")
    wait_for(attempted)
    File.write(release, "release")
    processes.map do |stdin, stdout, stderr, wait|
      stdin.close
      [ JSON.parse(stdout.read.lines.last), stderr.read, wait.value.exitstatus ]
    end
  end

  def wait_for(path)
    Timeout.timeout(10) { sleep 0.01 until File.exist?(path) }
  end

  def persisted_state(environment)
    script = <<~'RUBY'
      config = RuntimeConfig.current
      puts JSON.generate([config.retrospective_enabled, config.lock_version, IdempotencyRecord.count])
    RUBY
    output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "runner", script)
    expect(status).to be_success, output
    JSON.parse(output.lines.last)
  end

  def concurrent_summary(keys)
    Dir.mktmpdir("kos-runtime-config-concurrency") do |directory|
      env = environment(directory)
      prepare(env)
      results = run_pair(env, keys)
      [ results.map(&:last).sort, results.filter_map { |result| result.first["error"] }, persisted_state(env) ]
    end
  end

  it "executes concurrent same-key updates once" do
    expect(concurrent_summary(%w[same-runtime-key same-runtime-key])).to eq([ [ 0, 0 ], [], [ true, 1, 1 ] ])
  end

  it "allows only one concurrent update from the same lock version" do
    expect(concurrent_summary(%w[first-runtime-key second-runtime-key]))
      .to eq([ [ 0, 6 ], [ "stale_lock_version" ], [ true, 1, 2 ] ])
  end
end
