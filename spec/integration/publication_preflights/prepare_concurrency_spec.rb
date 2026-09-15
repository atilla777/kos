require "json"
require "open3"
require "rails_helper"
require "timeout"
require "tmpdir"

RSpec.describe PublicationPreflights::Prepare, :aggregate_failures do
  def root = File.expand_path("../../..", __dir__)

  def environment(directory)
    { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3") }
  end

  def run_script(environment, script)
    output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "runner", script)
    expect(status).to be_success, output
    JSON.parse(output.lines.last)
  end

  def prepare_state(environment, with_preflight:)
    helper = File.join(root, "spec/support/publication_preflight_helpers.rb")
    catalog = File.join(root, "spec/support/workflow_catalog_helpers.rb")
    run_script(environment, <<~RUBY)
      require #{helper.dump}
      require #{catalog.dump}
      support = Object.new.extend(PublicationPreflightHelpers).extend(WorkflowCatalogHelpers)
      repository = Repository.create!(git_common_dir: "/tmp/preflight-concurrency.git", task_prefix: "KOS",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      version = support.publish_workflow
      task = Task.create!(repository: repository, sequence: 1, title: "Concurrent preflight",
        task_input_schema_version: "1", approved_brief: "Observe the trusted base concurrently.",
        task_type: support.quick_fix_task_type, workflow_version: version,
        workflow_state: version.workflow_states.find_by!(initial: true))
      now = Time.current.change(usec: 0) - 5
      support.advance_to_publication(task: task, version: version, candidate_sha: "a" * 40, now: now)
      attempt = WorkflowAttempts::Claim.call(repository: repository, task_number: task.number,
        owner_id: "publisher", lease_seconds: 300, expected_lock_version: task.reload.lock_version,
        idempotency_key: "preflight-concurrency-claim", now: now + 1)
      preflight = if #{with_preflight}
        PublicationPreflights::Prepare.call(repository: repository, task_number: task.number,
          candidate_sha: "a" * 40, remote: "origin", base_ref: "refs/heads/main", attempt_id: attempt.id,
          fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now: now + 1)
      end
      observed_at = (now + 2).iso8601(6)
      digest = if preflight
        support.publication_preflight_evidence(repository: repository, preflight: preflight, attempt: attempt,
          observed_remote_oid: "b" * 40, observed_at: observed_at)
      end
      puts JSON.generate({ repository_id: repository.id, task_number: task.number,
        task_lock: task.reload.lock_version, attempt_id: attempt.id, fencing_token: attempt.fencing_token,
        preflight_id: preflight&.id, observed_at: observed_at, evidence_digest: digest })
    RUBY
  end

  def runner_script
    <<~'RUBY'
      begin
        File.write(ENV.fetch("READY_FILE"), "ready")
        sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
        sleep ENV.fetch("DELAY", "0").to_f
        repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
        preconditions = { "expected_lock_version" => ENV.fetch("TASK_LOCK").to_i,
          "attempt_id" => ENV.fetch("ATTEMPT_ID"), "fencing_token" => ENV.fetch("FENCING_TOKEN").to_i }
        if ENV.fetch("MODE") == "prepare"
          body = { "task_number" => ENV.fetch("TASK_NUMBER"), "candidate_sha" => "a" * 40,
            "remote" => "origin", "base_ref" => "refs/heads/main", "preconditions" => preconditions }
          operation = -> { PublicationPreflights::Prepare.call(repository: repository,
            task_number: ENV.fetch("TASK_NUMBER"), candidate_sha: "a" * 40, remote: "origin",
            base_ref: "refs/heads/main", attempt_id: ENV.fetch("ATTEMPT_ID"),
            fencing_token: ENV.fetch("FENCING_TOKEN").to_i,
            expected_lock_version: ENV.fetch("TASK_LOCK").to_i) }
        else
          unknown = ENV.fetch("OBSERVATION") == "unknown"
          error = { "category" => "transient", "code" => "publication_preflight_state_uncertain",
            "message" => "Observation result was lost", "retryable" => true }
          body = { "preflight_id" => ENV.fetch("PREFLIGHT_ID"),
            "observed_remote_oid" => unknown ? nil : "b" * 40,
            "observed_at" => unknown ? nil : ENV.fetch("OBSERVED_AT"),
            "evidence_digest" => unknown ? nil : ENV.fetch("EVIDENCE_DIGEST"),
            "unknown" => unknown ? error : nil, "preconditions" => preconditions }.compact
          operation = -> { PublicationPreflights::Reconcile.call(repository: repository,
            preflight_id: ENV.fetch("PREFLIGHT_ID"), observed_remote_oid: body["observed_remote_oid"],
            observed_at: body["observed_at"], evidence_digest: body["evidence_digest"], unknown: body["unknown"],
            attempt_id: ENV.fetch("ATTEMPT_ID"), fencing_token: ENV.fetch("FENCING_TOKEN").to_i,
            expected_lock_version: ENV.fetch("TASK_LOCK").to_i) }
        end
        command = "publication_preflight.#{ENV.fetch('MODE')}"
        result = Idempotency::Execute.call(command: command, key: ENV.fetch("KEY"), body: body,
          status: ENV.fetch("MODE") == "prepare" ? 201 : 200, repository: repository,
          serialize: ->(record) { { "id" => record.id, "state" => record.state } }) { operation.call }
        puts JSON.generate(result.data)
      rescue OperationError => error
        puts JSON.generate("error" => error.code)
      end
    RUBY
  end

  def run_pair(environment, state, entrants)
    directory = File.dirname(environment.fetch("KOS_DATABASE_PATH"))
    start = File.join(directory, "start")
    ready = Array.new(entrants.length) { |index| File.join(directory, "ready-#{index}") }
    common = state.transform_keys { _1.upcase }.transform_values(&:to_s)
    processes = entrants.map.with_index do |entrant, index|
      Open3.popen3(environment.merge(common, entrant, "START_FILE" => start, "READY_FILE" => ready.fetch(index)),
        File.join(root, "bin/rails"), "runner", runner_script)
    end
    ready.each { wait_for(_1) }
    File.write(start, "start")
    processes.map { collect(_1) }
  end

  def collect(process)
    stdin, stdout, stderr, wait = process
    stdin.close
    output = stdout.read
    diagnostics = stderr.read
    expect(wait.value).to be_success, diagnostics
    JSON.parse(output.lines.last)
  end

  def wait_for(path)
    Timeout.timeout(10) { sleep 0.01 until File.exist?(path) }
  end

  def with_state(with_preflight:)
    Dir.mktmpdir("kos-preflight-concurrency") do |directory|
      env = environment(directory)
      output, status = Open3.capture2e(env, File.join(root, "bin/rails"), "db:prepare")
      expect(status).to be_success, output
      yield env, prepare_state(env, with_preflight:)
    end
  end

  def concurrent_prepare_summary
    with_state(with_preflight: false) do |env, state|
      entrants = %w[first-prepare second-prepare].map { { "MODE" => "prepare", "KEY" => _1 } }
      results = run_pair(env, state, entrants)
      persisted = run_script(env, <<~'RUBY')
        puts JSON.generate([PublicationPreflight.count, PublicationPreflight.active.count,
          PublicationPreflight.first.state,
          IdempotencyRecord.where(command: "publication_preflight.prepare").count])
      RUBY
      [ results, persisted ]
    end
  end

  def concurrent_reconcile_summary
    with_state(with_preflight: true) do |env, state|
      entrants = [
        { "MODE" => "reconcile", "KEY" => "unknown-reconcile", "OBSERVATION" => "unknown", "DELAY" => "0.2" },
        { "MODE" => "reconcile", "KEY" => "concrete-reconcile", "OBSERVATION" => "concrete" }
      ]
      results = run_pair(env, state, entrants)
      persisted = run_script(env, <<~'RUBY')
        preflight = PublicationPreflight.first
        puts JSON.generate([preflight.state, preflight.observed_remote_oid, preflight.observed_at&.iso8601(6),
          preflight.observation_digest, preflight.observation_owner_attempt_id, preflight.error,
          preflight.reconciled_at.present?, IdempotencyRecord.where(command: "publication_preflight.reconcile").count])
      RUBY
      [ results, persisted, state ]
    end
  end

  it "creates one active preflight when distinct prepare keys race" do
    results, persisted = concurrent_prepare_summary
    expect(results.filter_map { _1["id"] }.length).to eq(1)
    expect(results.filter_map { _1["error"] }).to eq([ "invalid_transition" ])
    expect(persisted).to eq([ 1, 1, "prepared", 2 ])
  end

  it "keeps one canonical observation when concrete and unknown reconciliation race" do
    results, persisted, state = concurrent_reconcile_summary
    expect(results).to contain_exactly({ "error" => "invalid_transition" },
      { "id" => state.fetch("preflight_id"), "state" => "reconciled" })
    expect(persisted).to eq([ "reconciled", "b" * 40, state.fetch("observed_at"),
      state.fetch("evidence_digest"), state.fetch("attempt_id"), nil, true, 2 ])
  end
end
