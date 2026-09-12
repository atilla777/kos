require "json"
require "open3"
require "rails_helper"
require "tmpdir"

RSpec.describe Publications::Prepare, :aggregate_failures do
  def root = File.expand_path("../../..", __dir__)

  def environment(directory)
    { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3") }
  end

  def run_script(environment, script)
    output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "runner", script)
    expect(status).to be_success, output
    JSON.parse(output.lines.last)
  end

  def prepare_state(environment, with_publication:)
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
      repository = Repository.create!(git_common_dir: "/tmp/publication-concurrency.git", task_prefix: "KOS",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      task = Task.create!(repository: repository, sequence: 1, title: "Concurrent publication", task_type: type,
        workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
      now = Time.current.change(usec: 0)
      candidate_sha = "a" * 40
      development = version.workflow_states.find_by!(identifier: "development")
      review = version.workflow_states.find_by!(identifier: "review")
      publication_state = version.workflow_states.find_by!(identifier: "publication")
      task.update!(workflow_state: development)
      candidate_transition = version.workflow_transitions.find_by!(from_state: development, to_state: review)
      candidate_attempt = WorkflowAttempt.create!(repository: repository, task: task, workflow_state: development,
        owner_id: "developer", idempotency_key: "candidate-attempt", fencing_token: 1, started_at: now,
        heartbeat_at: now, lease_expires_at: now + 300, input_context: { "schema_version" => "1" },
        input_context_digest: "sha256:" + ("c" * 64))
      task.update!(active_attempt: candidate_attempt)
      task.update!(active_attempt: nil, workflow_state: review)
      candidate_attempt.update!(state: "succeeded", lease_expires_at: nil, completed_at: now,
        result_manifest: { "schema_version" => "1", "attempt_id" => candidate_attempt.id,
          "input_context_digest" => "sha256:" + ("c" * 64), "outcome" => "succeeded", "artifacts" => [] },
        completed_transition: candidate_transition)
      TaskArtifact.create!(repository: repository, task: task, workflow_attempt: candidate_attempt,
        artifact_type: "candidate", state: "produced", producer: "workflow-step",
        metadata: { "kind" => "candidate", "candidate_sha" => candidate_sha, "task_trailer" => task.number })
      review_transition = version.workflow_transitions.find_by!(from_state: review, to_state: publication_state)
      review_attempt = WorkflowAttempt.create!(repository: repository, task: task, workflow_state: review,
        owner_id: "reviewer", idempotency_key: "review-attempt", fencing_token: 2, started_at: now,
        heartbeat_at: now, lease_expires_at: now + 300, input_context: { "schema_version" => "1" },
        input_context_digest: "sha256:" + ("c" * 64))
      task.update!(active_attempt: review_attempt)
      task.update!(active_attempt: nil, workflow_state: publication_state)
      review_attempt.update!(state: "succeeded", lease_expires_at: nil, completed_at: now,
        result_manifest: { "schema_version" => "1", "attempt_id" => review_attempt.id,
          "input_context_digest" => "sha256:" + ("c" * 64), "outcome" => "succeeded", "artifacts" => [] },
        completed_transition: review_transition)
      TaskArtifact.create!(repository: repository, task: task, workflow_attempt: review_attempt,
        artifact_type: "review", state: "approved", producer: "workflow-step", metadata: {
          "kind" => "review", "candidate_sha" => candidate_sha, "verdict" => "approved",
          "review_attempt_id" => review_attempt.id })
      attempt = WorkflowAttempts::Claim.call(repository: repository, task_number: task.number,
        owner_id: "publisher", lease_seconds: 300, expected_lock_version: task.reload.lock_version,
        idempotency_key: "publication-claim", now: now + 2)
      publication = if #{with_publication}
        Publications::Prepare.call(repository: repository, task_number: task.number, candidate_sha: candidate_sha,
          remote: "origin", base_ref: "refs/heads/main", expected_remote_oid: "b" * 40,
          attempt_id: attempt.id, fencing_token: attempt.fencing_token,
          expected_lock_version: task.reload.lock_version, now: now + 2)
      end
      puts JSON.generate({ repository_id: repository.id, task_number: task.number,
        task_lock: task.reload.lock_version, attempt_id: attempt.id, fencing_token: attempt.fencing_token,
        publication_id: publication&.id, observed_origin: (now + 2).iso8601 })
    RUBY
  end

  def runner_script
    <<~'RUBY'
      begin
        sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
        sleep ENV.fetch("DELAY", "0").to_f
        repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
        preconditions = { "expected_lock_version" => ENV.fetch("TASK_LOCK").to_i,
          "attempt_id" => ENV.fetch("ATTEMPT_ID"), "fencing_token" => ENV.fetch("FENCING_TOKEN").to_i }
        if ENV.fetch("MODE") == "prepare"
          body = { "task_number" => ENV.fetch("TASK_NUMBER"), "candidate_sha" => "a" * 40,
            "remote" => "origin", "base_ref" => "refs/heads/main", "expected_remote_oid" => "b" * 40,
            "preconditions" => preconditions }
          operation = -> { Publications::Prepare.call(repository: repository,
            task_number: ENV.fetch("TASK_NUMBER"), candidate_sha: "a" * 40, remote: "origin",
            base_ref: "refs/heads/main", expected_remote_oid: "b" * 40,
            attempt_id: ENV.fetch("ATTEMPT_ID"), fencing_token: ENV.fetch("FENCING_TOKEN").to_i,
            expected_lock_version: ENV.fetch("TASK_LOCK").to_i) }
        else
          observed_at = Time.iso8601(ENV.fetch("OBSERVED_AT"))
          reachable = ENV.fetch("REACHABLE") == "true"
          tip = ENV.fetch("TIP").encode(Encoding::UTF_8)
          body = { "publication_id" => ENV.fetch("PUBLICATION_ID"), "candidate_sha" => "a" * 40,
            "observed_remote_tip" => tip, "candidate_reachable" => reachable,
            "observed_at" => observed_at.iso8601.encode(Encoding::UTF_8),
            "evidence_digest" => "sha256:" + ("c" * 64),
            "preconditions" => preconditions }
          operation = -> { Publications::Reconcile.call(repository: repository,
            publication_id: ENV.fetch("PUBLICATION_ID"), candidate_sha: "a" * 40,
            observed_remote_tip: tip, candidate_reachable: reachable, observed_at: observed_at,
            evidence_digest: "sha256:" + ("c" * 64), attempt_id: ENV.fetch("ATTEMPT_ID"),
            fencing_token: ENV.fetch("FENCING_TOKEN").to_i,
            expected_lock_version: ENV.fetch("TASK_LOCK").to_i) }
        end
        result = Idempotency::Execute.call(command: "publication." + ENV.fetch("MODE"),
          key: ENV.fetch("KEY"), body: body, status: ENV.fetch("MODE") == "prepare" ? 201 : 200,
          repository: repository, serialize: ->(record) { { "id" => record.id, "state" => record.state } }) {
          operation.call }
        puts JSON.generate(result.data)
      rescue OperationError => error
        puts JSON.generate("error" => error.code)
      end
    RUBY
  end

  def run_pair(environment, state, entrants)
    start_file = File.join(File.dirname(environment.fetch("KOS_DATABASE_PATH")), "start")
    common = state.transform_keys { _1.upcase }.transform_values(&:to_s).merge("START_FILE" => start_file)
    processes = entrants.map do |entrant|
      Open3.popen3(environment.merge(common, entrant), File.join(root, "bin/rails"), "runner", runner_script)
    end
    File.write(start_file, "start")
    processes.map do |stdin, stdout, stderr, wait|
      stdin.close
      output = stdout.read
      diagnostics = stderr.read
      expect(wait.value).to be_success, diagnostics
      JSON.parse(output.lines.last)
    end
  end

  def with_state(with_publication:)
    Dir.mktmpdir("kos-publication-concurrency") do |directory|
      env = environment(directory)
      output, status = Open3.capture2e(env, File.join(root, "bin/rails"), "db:prepare")
      expect(status).to be_success, output
      yield env, prepare_state(env, with_publication:)
    end
  end

  def concurrent_prepare_summary
    with_state(with_publication: false) do |env, state|
      entrants = 2.times.map { { "MODE" => "prepare", "KEY" => "same-prepare-key" } }
      results = run_pair(env, state, entrants)
      persisted = run_script(env, "puts JSON.generate([Publication.count, IdempotencyRecord.count])")
      [ results.map { _1.fetch("id") }.uniq.length, persisted ]
    end
  end

  def concurrent_distinct_prepare_summary
    with_state(with_publication: false) do |env, state|
      entrants = %w[first-prepare-key second-prepare-key].map { { "MODE" => "prepare", "KEY" => _1 } }
      results = run_pair(env, state, entrants)
      persisted = run_script(env, <<~'RUBY')
        task = Task.first
        puts JSON.generate([Publication.count, task.active_publication_id == Publication.first.id,
          IdempotencyRecord.where(command: "publication.prepare").count])
      RUBY
      [ results.filter_map { _1["id"] }.length, results.filter_map { _1["error"] }, persisted ]
    end
  end

  def stale_observation_summary
    with_state(with_publication: true) do |env, state|
      origin = Time.iso8601(state.fetch("observed_origin"))
      entrants = [
        { "MODE" => "reconcile", "KEY" => "newer-observation", "TIP" => "e" * 40, "REACHABLE" => "true",
          "OBSERVED_AT" => (origin + 2).iso8601 },
        { "MODE" => "reconcile", "KEY" => "stale-observation", "TIP" => "f" * 40, "REACHABLE" => "false",
          "OBSERVED_AT" => (origin + 1).iso8601, "DELAY" => "0.2" }
      ]
      results = run_pair(env, state, entrants)
      persisted = run_script(env, <<~'RUBY')
        publication = Publication.first
        puts JSON.generate([publication.state, publication.observed_remote_tip,
          publication.candidate_reachable, publication.task.active_publication_id])
      RUBY
      [ results, persisted, state.fetch("publication_id") ]
    end
  end

  def concurrent_base_moved_summary
    with_state(with_publication: true) do |env, state|
      origin = Time.iso8601(state.fetch("observed_origin"))
      entrants = 2.times.map do |index|
        { "MODE" => "reconcile", "KEY" => "moved-observation-#{index}", "TIP" => ("e".ord + index).chr * 40,
          "REACHABLE" => "false", "OBSERVED_AT" => (origin + index + 1).iso8601 }
      end
      results = run_pair(env, state, entrants)
      persisted = run_script(env, <<~'RUBY')
        publication = Publication.first
        puts JSON.generate([publication.state, publication.task.active_publication_id,
          IdempotencyRecord.where(command: "publication.reconcile").count])
      RUBY
      [ results.map { _1.fetch("error") }, persisted ]
    end
  end

  def valid_loser?(codes)
    losers = codes - [ "base_moved" ]
    losers.one? && losers.first.in?(%w[invalid_transition stale_lock_version])
  end

  it "creates one publication for concurrent idempotent prepare processes" do
    expect(concurrent_prepare_summary).to eq([ 1, [ 1, 1 ] ])
  end

  it "keeps one active publication for concurrent prepare processes with distinct keys" do
    successes, errors, persisted = concurrent_distinct_prepare_summary
    expect(successes).to eq(1)
    expect(errors.one? && errors.first.in?(%w[invalid_transition stale_lock_version])).to be(true)
    expect(persisted).to eq([ 1, true, 2 ])
  end

  it "does not let a delayed stale base_moved observation supersede a newer observation" do
    results, persisted, publication_id = stale_observation_summary
    expect(results).to contain_exactly({ "id" => publication_id, "state" => "reconciled" },
      { "error" => "invalid_transition" })
    expect(persisted).to eq([ "reconciled", "e" * 40, true, publication_id ])
  end

  it "atomically commits only one of two concurrent base_moved reconciliations" do
    codes, persisted = concurrent_base_moved_summary
    expect(codes).to include("base_moved")
    expect(valid_loser?(codes)).to be(true)
    expect(persisted).to eq([ "superseded", nil, 2 ])
  end
end
