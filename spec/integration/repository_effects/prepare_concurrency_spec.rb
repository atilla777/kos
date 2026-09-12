require "json"
require "open3"
require "rails_helper"
require "tmpdir"

RSpec.describe RepositoryEffects::Prepare, :aggregate_failures do
  def root
    File.expand_path("../../..", __dir__)
  end

  def environment(directory)
    { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3") }
  end

  def run_script(environment, script)
    output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "runner", script)
    expect(status).to be_success, output
    JSON.parse(output.lines.last)
  end

  def prepare_state(environment, with_effect:)
    fixture = File.join(root, "spec/fixtures/workflow_definitions/v1/valid/quick-fix.json")
    run_script(environment, <<~RUBY)
      type = TaskType.find_or_create_by!(id: "quick-fix") do |record|
        record.name = "quick-fix"
        record.workflow_id = "quick-fix"
      end
      definition = JSON.parse(File.read(#{fixture.dump}))
      draft = WorkflowCatalog::ImportDraft.call(workflow_id: "quick-fix", definition: definition,
        expected_lock_version: 0)
      version = WorkflowCatalog::PublishDraft.call(workflow_id: "quick-fix",
        expected_lock_version: draft.lock_version)
      repository = Repository.create!(git_common_dir: "/tmp/effect-concurrency.git", task_prefix: "KOS",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      task = Task.create!(repository: repository, sequence: 1, title: "Concurrent effect", task_type: type,
        workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
      attempt = WorkflowAttempts::Claim.call(repository: repository, task_number: task.number,
        owner_id: "owner", lease_seconds: 300, expected_lock_version: 0, idempotency_key: "claim-effect")
      digest = "sha256:" + ("a" * 64)
      attempt.update!(input_context: { "allowed_repository_effects" => ["fetch"] }, input_context_digest: digest)
      request = { "schema_version" => "1", "attempt_id" => attempt.id, "input_context_digest" => digest,
        "effect" => { "operation" => "fetch", "remote" => "origin", "ref" => "refs/heads/main" } }
      effect = if #{with_effect}
        RepositoryEffects::Prepare.call(repository: repository, task_number: task.number, effect_request: request,
          attempt_id: attempt.id, fencing_token: attempt.fencing_token,
          expected_lock_version: task.reload.lock_version)
      end
      if #{with_effect}
        publication = task.publications.create!(repository: repository, prepared_attempt: attempt,
          current_owner_attempt: attempt, candidate_sha: "c" * 40, remote: "origin",
          base_ref: "refs/heads/main", expected_remote_oid: "d" * 40, prepared_at: Time.current)
        task.update!(active_publication: publication)
      end
      puts JSON.generate({ "repository_id" => repository.id, "task_number" => task.number,
        "task_lock" => task.reload.lock_version, "attempt_id" => attempt.id,
        "fencing_token" => attempt.fencing_token, "digest" => digest, "effect_id" => effect&.id,
        "request_digest" => effect&.request_digest })
    RUBY
  end

  def runner_script
    <<~'RUBY'
      begin
        sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
        repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
        preconditions = { "expected_lock_version" => ENV.fetch("TASK_LOCK").to_i,
          "attempt_id" => ENV.fetch("ATTEMPT_ID"), "fencing_token" => ENV.fetch("FENCING_TOKEN").to_i }
        if ENV.fetch("MODE") == "claim"
          body = { "task_number" => ENV.fetch("TASK_NUMBER"), "owner_id" => ENV.fetch("IDEMPOTENCY_KEY"),
            "lease_seconds" => 300, "preconditions" => {
              "expected_lock_version" => ENV.fetch("TASK_LOCK").to_i } }
          operation = ->(_prepared) { WorkflowAttempts::Claim.call(repository: repository,
            task_number: ENV.fetch("TASK_NUMBER"), owner_id: ENV.fetch("IDEMPOTENCY_KEY"),
            lease_seconds: 300, expected_lock_version: ENV.fetch("TASK_LOCK").to_i,
            idempotency_key: ENV.fetch("IDEMPOTENCY_KEY")) }
        elsif ENV.fetch("MODE") == "prepare"
          request = { "schema_version" => "1", "attempt_id" => ENV.fetch("ATTEMPT_ID"),
            "input_context_digest" => ENV.fetch("DIGEST"),
            "effect" => { "operation" => "fetch", "remote" => "origin", "ref" => "refs/heads/main" } }
          body = { "task_number" => ENV.fetch("TASK_NUMBER"), "effect_request" => request,
            "preconditions" => preconditions }
          operation = ->(_prepared) { RepositoryEffects::Prepare.call(repository: repository,
            task_number: ENV.fetch("TASK_NUMBER"), effect_request: request,
            attempt_id: ENV.fetch("ATTEMPT_ID"), fencing_token: ENV.fetch("FENCING_TOKEN").to_i,
            expected_lock_version: ENV.fetch("TASK_LOCK").to_i) }
        else
          outcome = ENV.fetch("OUTCOME")
          result_body = if outcome == "succeeded"
            { "outcome" => outcome, "operation" => "fetch", "remote" => "origin",
              "ref" => "refs/heads/main", "observed_oid" => "b" * 40,
              "evidence_digest" => ENV.fetch("DIGEST") }
          else
            { "outcome" => outcome, "operation" => "fetch", "error" => { "category" => "conflict",
              "code" => "fetch_rejected", "message" => "Fetch rejected", "retryable" => false } }
          end
          effect_result = { "schema_version" => "1", "effect_intent_id" => ENV.fetch("EFFECT_ID"),
            "request_attempt_id" => ENV.fetch("ATTEMPT_ID"), "owner_attempt_id" => ENV.fetch("ATTEMPT_ID"),
            "input_context_digest" => ENV.fetch("DIGEST"),
            "effect_request_digest" => ENV.fetch("REQUEST_DIGEST"), "result" => result_body }
          body = { "effect_id" => ENV.fetch("EFFECT_ID"), "effect_result" => effect_result,
            "preconditions" => preconditions }
          operation = ->(_prepared) { RepositoryEffects::Reconcile.call(repository: repository,
            effect_id: ENV.fetch("EFFECT_ID"), effect_result: effect_result,
            attempt_id: ENV.fetch("ATTEMPT_ID"), fencing_token: ENV.fetch("FENCING_TOKEN").to_i,
            expected_lock_version: ENV.fetch("TASK_LOCK").to_i) }
        end
        command = ENV.fetch("MODE") == "claim" ? "attempt.claim" : "effect." + ENV.fetch("MODE")
        result = Idempotency::Execute.call(command: command, key: ENV.fetch("IDEMPOTENCY_KEY"), body: body,
          status: %w[prepare claim].include?(ENV.fetch("MODE")) ? 201 : 200, repository: repository,
          serialize: ->(effect) { { "id" => effect.id, "state" => effect.state } }, &operation)
        puts JSON.generate(result.data)
      rescue OperationError => error
        puts JSON.generate("error" => error.code)
      end
    RUBY
  end

  def run_pair(environment, state, mode:, keys:, outcomes: [])
    start = File.join(File.dirname(environment.fetch("KOS_DATABASE_PATH")), "start")
    processes = 2.times.map do |index|
      values = state.transform_keys { _1.upcase }.transform_values(&:to_s).merge(
        "START_FILE" => start, "MODE" => mode, "IDEMPOTENCY_KEY" => keys.fetch(index))
      values["OUTCOME"] = outcomes.fetch(index) if outcomes.any?
      Open3.popen3(environment.merge(values), File.join(root, "bin/rails"), "runner", runner_script)
    end
    File.write(start, "start")
    processes.map do |stdin, stdout, stderr, wait|
      stdin.close
      output = stdout.read
      diagnostics = stderr.read
      status = wait.value.exitstatus
      expect(output).not_to be_empty, diagnostics
      [ JSON.parse(output.lines.last), diagnostics, status ]
    end
  end

  def with_state(with_effect:)
    Dir.mktmpdir("kos-effect-concurrency") do |directory|
      env = environment(directory)
      output, status = Open3.capture2e(env, File.join(root, "bin/rails"), "db:prepare")
      expect(status).to be_success, output
      yield env, prepare_state(env, with_effect:)
    end
  end

  def reconcile_expired_attempt(environment, state)
    run_script(environment.merge(state.transform_keys { _1.upcase }.transform_values(&:to_s)), <<~'RUBY')
      repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
      attempt = WorkflowAttempt.find(ENV.fetch("ATTEMPT_ID"))
      WorkflowAttempts::Reconcile.call(repository: repository, attempt_id: attempt.id,
        observed_state: "repository_effect_pending", evidence_digest: ENV.fetch("DIGEST"),
        expected_lock_version: ENV.fetch("TASK_LOCK").to_i, now: attempt.lease_expires_at + 1)
      puts JSON.generate({ "repository_id" => repository.id, "task_number" => attempt.task.number,
        "task_lock" => attempt.task.reload.lock_version, "attempt_id" => attempt.id,
        "fencing_token" => attempt.fencing_token, "digest" => ENV.fetch("DIGEST"),
        "effect_id" => RepositoryEffect.first.id,
        "request_digest" => RepositoryEffect.first.request_digest })
    RUBY
  end

  def concurrent_prepare_summary
    with_state(with_effect: false) do |env, state|
      results = run_pair(env, state, mode: "prepare", keys: %w[same-effect-key same-effect-key])
      persisted = run_script(env, "puts JSON.generate([RepositoryEffect.count, IdempotencyRecord.count])")
      [ results.map { _1.first.fetch("id") }.uniq.length, results.map { _1.fetch(1) }, persisted ]
    end
  end

  def concurrent_reconcile_summary
    with_state(with_effect: true) do |env, state|
      results = run_pair(env, state, mode: "reconcile", keys: %w[success-key failure-key],
        outcomes: %w[succeeded failed])
      persisted = run_script(env,
        "effect = RepositoryEffect.first; puts JSON.generate([effect.state, IdempotencyRecord.count])")
      [ results.map { _1.first["error"] }.compact, results.map { _1.fetch(1) }, persisted ]
    end
  end

  def concurrent_claim_summary
    with_state(with_effect: true) do |env, state|
      recovered = reconcile_expired_attempt(env, state)
      results = run_pair(env, recovered, mode: "claim", keys: %w[first-claim-key second-claim-key])
      persisted = run_script(env, <<~'RUBY')
        task = Task.first
        puts JSON.generate([WorkflowAttempt.count, task.active_attempt_id,
          RepositoryEffect.first.current_owner_attempt_id, task.active_publication_id,
          Publication.first.current_owner_attempt_id])
      RUBY
      winner = results.filter_map { _1.first["id"] }.first
      [ results.map { _1.first["error"] }.compact, persisted, winner ]
    end
  end

  it "creates one intent for concurrent repeats of the same prepare key" do
    expect(concurrent_prepare_summary).to eq([ 1, [ "", "" ], [ 1, 1 ] ])
  end

  it "allows only one terminal reconciliation of a prepared effect" do
    summary = concurrent_reconcile_summary
    expect(summary.first(2)).to eq([ [ "invalid_transition" ], [ "", "" ] ])
    expect(summary.last).to satisfy { |state, count| %w[succeeded failed].include?(state) && count == 2 }
  end

  it "atomically gives every unresolved effect to the winning replacement claim" do
    summary = concurrent_claim_summary
    expect(summary.first).to eq([ "stale_lock_version" ])
    expect(summary.fetch(1).values_at(0, 1, 2, 4)).to eq([ 2, summary.last, summary.last, summary.last ])
    expect(summary.fetch(1).fetch(3)).to be_present
  end
end
