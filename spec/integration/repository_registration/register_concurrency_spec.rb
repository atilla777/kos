require "json"
require "open3"
require "rails_helper"
require "timeout"
require "tmpdir"

RSpec.describe RepositoryRegistration::Register, :aggregate_failures do
  def runner_script
    <<~'RUBY'
      begin
        File.write(ENV.fetch("READY_FILE"), "ready")
        sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
        attributes = JSON.parse(ENV.fetch("ATTRIBUTES"))
        result = Idempotency::Execute.call(command: "repository.register", key: ENV.fetch("KEY"), body: attributes,
          status: 200, serialize: ->(repository) { { "id" => repository.id } }) do
          RepositoryRegistration::Register.call(attributes)
        end
        puts JSON.generate(result.data)
      rescue OperationError => error
        puts JSON.generate("error" => error.code)
      end
    RUBY
  end

  def run_case(first, second, keys: %w[registration-key-1 registration-key-2])
    Dir.mktmpdir("kos-registration-concurrency") do |directory|
      environment = { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3") }
      output, status = Open3.capture2e(environment, Rails.root.join("bin/rails").to_s, "db:prepare")
      expect(status).to be_success, output
      start = File.join(directory, "start")
      ready = keys.each_index.map { |index| File.join(directory, "ready-#{index}") }
      processes = [ first, second ].zip(keys, ready).map do |attributes, key, ready_file|
        values = environment.merge("START_FILE" => start, "READY_FILE" => ready_file,
          "ATTRIBUTES" => JSON.generate(attributes), "KEY" => key)
        Open3.popen3(values, Rails.root.join("bin/rails").to_s, "runner", runner_script)
      end
      Timeout.timeout(30) { sleep 0.01 until ready.all? { |path| File.exist?(path) } }
      File.write(start, "start")
      results = processes.map do |stdin, stdout, stderr, wait|
        stdin.close
        output = stdout.read
        errors = stderr.read
        status = wait.value.exitstatus
        raise "registration runner failed: #{errors}" if output.lines.empty?
        raise "registration runner exited #{status}: #{errors}" unless status.zero?

        [ JSON.parse(output.lines.last), errors, status ]
      end
      state = JSON.parse(run_rails(environment, <<~'RUBY'))
        puts JSON.generate("repositories" => Repository.order(:git_common_dir).pluck(:git_common_dir, :task_prefix),
          "idempotency_count" => IdempotencyRecord.where(command: "repository.register").count)
      RUBY
      [ results, state ]
    end
  end

  def run_rails(environment, script)
    output, status = Open3.capture2e(environment, Rails.root.join("bin/rails").to_s, "runner", script)
    expect(status).to be_success, output
    output.lines.last
  end

  def attributes(common: "/tmp/concurrent-project.git", prefix: "KOS")
    { "git_common_dir" => common, "task_prefix" => prefix, "trusted_remote" => "origin",
      "trusted_remote_url" => "ssh://git@example.test/team/project.git", "base_ref" => "refs/heads/main" }
  end

  it "returns one registration for concurrent same-key repeats" do
    results, state = run_case(attributes, attributes, keys: %w[same-registration-key same-registration-key])

    expect([ results.map(&:first).uniq.length, state ])
      .to eq([ 1, { "repositories" => [ [ "/tmp/concurrent-project.git", "KOS" ] ], "idempotency_count" => 1 } ])
  end

  it "returns one registration for different keys and the same identity" do
    results, state = run_case(attributes, attributes)

    expect([ results.map { |result| result.first.fetch("id") }.uniq.length, state["idempotency_count"] ])
      .to eq([ 1, 2 ])
  end

  it "conflicts concurrent repositories competing for one prefix" do
    results, state = run_case(attributes, attributes(common: "/tmp/other-project.git"))

    expect([ results.map(&:first).count { |result| result["error"] == "repository_registration_conflict" },
      state["repositories"].length ]).to eq([ 1, 1 ])
  end

  it "conflicts concurrent prefixes competing for one common directory" do
    results, state = run_case(attributes, attributes(prefix: "APP"))

    expect([ results.map(&:first).count { |result| result["error"] == "repository_registration_conflict" },
      state["repositories"].length ]).to eq([ 1, 1 ])
  end
end
