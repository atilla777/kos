require "json"
require "open3"
require "rails_helper"
require "tmpdir"

RSpec.describe Publications::PrepareObserved, :aggregate_failures do
  def root = File.expand_path("../../..", __dir__)

  def run_script(environment, script)
    output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "runner", script)
    expect(status).to be_success, output
    JSON.parse(output.lines.last)
  end

  def prepare_state(environment)
    helper = File.join(root, "spec/support/publication_preflight_helpers.rb")
    catalog = File.join(root, "spec/support/workflow_catalog_helpers.rb")
    run_script(environment, <<~RUBY)
      require #{helper.dump}
      require #{catalog.dump}
      support = Object.new.extend(PublicationPreflightHelpers).extend(WorkflowCatalogHelpers)
      repository = Repository.create!(git_common_dir: "/tmp/preflight-process.git", task_prefix: "KOS",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      version = support.publish_workflow
      task = Task.create!(repository: repository, sequence: 1, title: "Concurrent consumption",
        task_input_schema_version: "1", approved_brief: "Consume the observation once.",
        task_type: support.quick_fix_task_type, workflow_version: version,
        workflow_state: version.workflow_states.find_by!(initial: true))
      now = Time.current.change(usec: 0) - 5
      support.advance_to_publication(task: task, version: version, candidate_sha: "a" * 40, now: now)
      attempt = WorkflowAttempts::Claim.call(repository: repository, task_number: task.number,
        owner_id: "publisher", lease_seconds: 300, expected_lock_version: task.reload.lock_version,
        idempotency_key: "process-preflight-claim", now:)
      preflight = PublicationPreflights::Prepare.call(repository: repository, task_number: task.number,
        candidate_sha: "a" * 40, remote: "origin", base_ref: "refs/heads/main", attempt_id: attempt.id,
        fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now:)
      observed_at = (now + 1).iso8601(6)
      digest = support.publication_preflight_evidence(repository: repository, preflight: preflight,
        attempt: attempt, observed_remote_oid: "b" * 40, observed_at: observed_at)
      PublicationPreflights::Reconcile.call(repository: repository, preflight_id: preflight.id,
        observed_remote_oid: "b" * 40, observed_at: observed_at, evidence_digest: digest,
        attempt_id: attempt.id, fencing_token: attempt.fencing_token,
        expected_lock_version: task.reload.lock_version, now: now + 1)
      puts JSON.generate({ repository_id: repository.id, preflight_id: preflight.id,
        attempt_id: attempt.id, fencing_token: attempt.fencing_token, task_lock: task.reload.lock_version })
    RUBY
  end

  def consumer_script
    <<~'RUBY'
      begin
        sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
        repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
        body = { "preflight_id" => ENV.fetch("PREFLIGHT_ID"), "preconditions" => {
          "expected_lock_version" => ENV.fetch("TASK_LOCK").to_i,
          "attempt_id" => ENV.fetch("ATTEMPT_ID"), "fencing_token" => ENV.fetch("FENCING_TOKEN").to_i } }
        result = Idempotency::Execute.call(command: "publication.prepare_observed", key: ENV.fetch("KEY"),
          body: body, status: 201, repository: repository,
          serialize: ->(record) { { "id" => record.id } }) do
          Publications::PrepareObserved.call(repository: repository, preflight_id: ENV.fetch("PREFLIGHT_ID"),
            attempt_id: ENV.fetch("ATTEMPT_ID"), fencing_token: ENV.fetch("FENCING_TOKEN").to_i,
            expected_lock_version: ENV.fetch("TASK_LOCK").to_i)
        end
        puts JSON.generate(result.data)
      rescue OperationError => error
        puts JSON.generate("error" => error.code)
      end
    RUBY
  end

  def concurrency_summary
    Dir.mktmpdir("kos-preflight-concurrency") do |directory|
      environment = { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3") }
      output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "db:prepare")
      expect(status).to be_success, output
      state = prepare_state(environment)
      start = File.join(directory, "start")
      common = state.transform_keys { _1.upcase }.transform_values(&:to_s).merge("START_FILE" => start)
      processes = %w[first-consume second-consume].map do |key|
        Open3.popen3(environment.merge(common, "KEY" => key), File.join(root, "bin/rails"), "runner",
          consumer_script)
      end
      File.write(start, "start")
      results = processes.map do |stdin, stdout, stderr, wait|
        stdin.close
        output = stdout.read
        diagnostics = stderr.read
        expect(wait.value).to be_success, diagnostics
        result = JSON.parse(output.lines.last)
        result
      end
      persisted = run_script(environment, <<~'RUBY')
        preflight = PublicationPreflight.first
        puts JSON.generate([Publication.count, preflight.state, preflight.publication_id,
          Task.first.active_publication_id])
      RUBY

      [ results, persisted ]
    end
  end

  it "creates and binds at most one publication under concurrent consumption" do
    results, persisted = concurrency_summary
    expect(results.count { _1["id"] }).to eq(1)
    expect(results.filter_map { _1["error"] }.first).to be_in(%w[invalid_transition stale_lock_version])
    expect(persisted).to eq([ 1, "consumed", persisted.fetch(2), persisted.fetch(2) ])
  end
end
