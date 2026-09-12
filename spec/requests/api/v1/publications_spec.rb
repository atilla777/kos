require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe "API v1 publications", :aggregate_failures, type: :request do
  include WorkflowCatalogHelpers
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    previous = ENV["KOS_API_TOKEN"]
    ENV["KOS_API_TOKEN"] = "publication-test-token"
    example.run
  ensure
    ENV["KOS_API_TOKEN"] = previous
  end

  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:version) { publish_workflow }
  let(:task) do
    Task.create!(repository:, sequence: 1, title: "Publish candidate", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end

  def now = (@now ||= Time.current.change(usec: 0))
  def candidate_sha = "a" * 40
  def expected_oid = "b" * 40
  def digest = "sha256:#{'c' * 64}"

  def headers(key = nil)
    { "Authorization" => "Bearer publication-test-token", "Accept" => "application/json" }
      .tap { _1["Idempotency-Key"] = key if key }
  end

  def logical(command, body, repository_id: repository.id)
    { "schema_version" => "1", "command" => command, "repository_id" => repository_id, "body" => body }
  end

  def successful_attempt(state, transition, token)
    attempt = WorkflowAttempt.create!(repository:, task:, workflow_state: state, owner_id: "history-owner",
      idempotency_key: "history-#{token}", fencing_token: token, started_at: now, heartbeat_at: now,
      lease_expires_at: now + 300, input_context: { "schema_version" => "1" }, input_context_digest: digest)
    task.update!(active_attempt: attempt)
    task.update!(active_attempt: nil, workflow_state: transition.to_state)
    attempt.update!(state: "succeeded", lease_expires_at: nil, completed_at: now,
      result_manifest: { "schema_version" => "1", "attempt_id" => attempt.id,
        "input_context_digest" => digest, "outcome" => "succeeded", "artifacts" => [] },
      completed_transition: transition)
    attempt
  end

  def advance_to_publication
    development = version.workflow_states.find_by!(identifier: "development")
    review = version.workflow_states.find_by!(identifier: "review")
    publication = version.workflow_states.find_by!(identifier: "publication")
    task.update!(workflow_state: development)
    candidate_attempt = successful_attempt(development,
      version.workflow_transitions.find_by!(from_state: development, to_state: review), 1)
    TaskArtifact.create!(repository:, task:, workflow_attempt: candidate_attempt, artifact_type: "candidate",
      state: "produced", producer: "workflow-step", metadata: { "kind" => "candidate",
        "candidate_sha" => candidate_sha, "task_trailer" => task.number }, created_at: now)
    review_attempt = successful_attempt(review,
      version.workflow_transitions.find_by!(from_state: review, to_state: publication), 2)
    TaskArtifact.create!(repository:, task:, workflow_attempt: review_attempt, artifact_type: "review",
      state: "approved", producer: "workflow-step", metadata: { "kind" => "review",
        "candidate_sha" => candidate_sha, "verdict" => "approved", "review_attempt_id" => review_attempt.id },
      created_at: now + 1)
  end

  def claim(at: now + 2, owner: "publisher")
    advance_to_publication unless task.reload.workflow_state.identifier == "publication"
    WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: owner, lease_seconds: 300,
      expected_lock_version: task.reload.lock_version, idempotency_key: "claim-#{SecureRandom.hex(5)}", now: at)
  end

  def preconditions(attempt)
    { "expected_lock_version" => task.reload.lock_version, "attempt_id" => attempt.id,
      "fencing_token" => attempt.fencing_token }
  end

  def prepare(attempt, key: "publication-prepare-key", **changes)
    body = { "task_number" => task.number, "candidate_sha" => candidate_sha,
      "remote" => repository.trusted_remote, "base_ref" => repository.base_ref,
      "expected_remote_oid" => expected_oid, "preconditions" => preconditions(attempt) }.merge(changes.stringify_keys)
    post "/api/v1/repositories/#{repository.id}/tasks/#{task.number}/publications",
      params: logical("publication.prepare", body), headers: headers(key), as: :json
    JSON.parse(response.body)
  end

  def reconcile(attempt, publication, tip:, reachable:, key: "publication-reconcile-key", conditions: nil,
    observed_at: now + 3)
    body = { "publication_id" => publication.id, "candidate_sha" => candidate_sha,
      "observed_remote_tip" => tip, "candidate_reachable" => reachable,
      "observed_at" => observed_at.iso8601, "evidence_digest" => digest,
      "preconditions" => conditions || preconditions(attempt) }
    post "/api/v1/repositories/#{repository.id}/publications/#{publication.id}/reconcile",
      params: logical("publication.reconcile", body), headers: headers(key), as: :json
    JSON.parse(response.body)
  end

  def confirm_worktree(attempt)
    reservation = WorktreeReservation.create!(repository:, task:, workflow_attempt: attempt,
      branch: "kos/task-#{task.number}", path: "/tmp/worktrees/#{task.number}", state: "confirmed",
      fencing_token: attempt.fencing_token, git_common_dir_digest: digest, head_sha: candidate_sha,
      confirmed_at: now + 2)
    task.reload.update!(worktree_reservation: reservation)
  end

  def prepare_read_summary
    attempt = claim
    conditions = preconditions(attempt)
    first = prepare(attempt, preconditions: conditions)
    publication = Publication.find(first.dig("data", "id"))
    replay = travel_to(now + 10.minutes) { prepare(attempt, preconditions: conditions) }
    get "/api/v1/repositories/#{repository.id}/publications/#{publication.id}", headers: headers
    read = JSON.parse(response.body)
    get "/api/v1/repositories/#{repository.id}/tasks/#{task.number}", headers: headers
    task_read = JSON.parse(response.body)
    guards = database_intent_guards(publication, attempt)

    [ first.dig("data", "candidate_sha"), replay.dig("data", "id"), Publication.count,
      task_read.dig("data", "active_publication_id"), response.status,
      Kos::Cli::SchemaRegistry.new.valid?("commands.json", "result", read),
      Kos::Cli::SchemaRegistry.new.valid?("commands.json", "result", task_read), guards, publication.id ]
  end

  def database_intent_guards(publication, attempt)
    duplicate = begin
      task.publications.create!(repository:, prepared_attempt: attempt, current_owner_attempt: attempt,
        candidate_sha:, remote: "origin", base_ref: "refs/heads/main", expected_remote_oid: expected_oid,
        prepared_at: now + 3)
      false
    rescue ActiveRecord::StatementInvalid
      true
    end
    immutable = begin
      publication.update_columns(candidate_sha: "d" * 40)
      false
    rescue ActiveRecord::StatementInvalid
      true
    end
    [ duplicate, immutable ]
  end

  def invalid_prepare_summary
    attempt = claim
    codes = [
      -> { prepare(attempt, key: "bad-candidate", candidate_sha: "d" * 40) },
      -> { prepare(attempt, key: "bad-remote", remote: "upstream") },
      -> { prepare(attempt, key: "bad-fence", preconditions: preconditions(attempt).merge(
        "fencing_token" => attempt.fencing_token + 1)) }
    ].map { |operation| operation.call.dig("error", "code") }
    [ codes, Publication.count, task.reload.active_publication_id ]
  end

  def unresolved_reconcile_summary
    attempt = claim
    publication = Publication.find(prepare(attempt).dig("data", "id"))
    unchanged = reconcile(attempt, publication, tip: expected_oid, reachable: false, key: "unchanged-tip")
    reachable = reconcile(attempt, publication.reload, tip: "e" * 40, reachable: true, key: "reachable-tip",
      observed_at: now + 4)

    [ unchanged.dig("data", "state"), reachable.dig("data", "state"),
      publication.reload.observed_remote_tip, publication.candidate_reachable, task.reload.active_publication_id ]
  end

  def stale_reconcile_summary
    attempt = claim
    publication = Publication.find(prepare(attempt).dig("data", "id"))
    reconcile(attempt, publication, tip: "e" * 40, reachable: true, key: "newest-observation",
      observed_at: now + 5)
    before = publication.reload.attributes.slice("state", "observed_remote_tip", "candidate_reachable",
      "observation_digest", "observed_at", "reconciled_at", "observation_owner_attempt_id")
    codes = [ now + 4, now + 5 ].map.with_index do |timestamp, index|
      reconcile(attempt, publication, tip: "f" * 40, reachable: false, key: "stale-observation-#{index}",
        observed_at: timestamp).dig("error", "code")
    end

    [ codes, publication.reload.attributes.slice(*before.keys) == before, task.reload.active_publication_id ]
  end

  def invalid_observation_time_summary
    attempt = claim
    publication = Publication.find(prepare(attempt).dig("data", "id"))
    before_preparation = reconcile(attempt, publication, tip: expected_oid, reachable: false,
      key: "before-preparation", observed_at: publication.prepared_at - 1)
    far_future = reconcile(attempt, publication, tip: expected_oid, reachable: false,
      key: "far-future-observation", observed_at: Time.current + 6.minutes)

    [ before_preparation.dig("error", "code"), far_future.dig("error", "code"), publication.reload.state ]
  end

  def invalid_service_observation_time_codes
    attempt = claim
    publication = Publication.find(prepare(attempt).dig("data", "id"))
    [ publication.prepared_at - 1, now + 6.minutes ].map do |observed_at|
      operation_error_code do
        Publications::Reconcile.call(repository:, publication_id: publication.id, candidate_sha:,
          observed_remote_tip: expected_oid, candidate_reachable: false, observed_at:,
          evidence_digest: digest, attempt_id: attempt.id, fencing_token: attempt.fencing_token,
          expected_lock_version: task.reload.lock_version, now:)
      end
    end
  end

  def base_moved_summary
    attempt = claim
    publication = Publication.find(prepare(attempt).dig("data", "id"))
    conditions = preconditions(attempt)
    first = reconcile(attempt, publication, tip: "f" * 40, reachable: false, key: "moved-base-key",
      conditions:)
    replay = travel_to(now + 10.minutes) do
      reconcile(attempt, publication.reload, tip: "f" * 40, reachable: false, key: "moved-base-key",
        conditions:)
    end
    record = IdempotencyRecord.find_by!(command: "publication.reconcile", idempotency_key: "moved-base-key")

    [ first.dig("error", "code"), replay.dig("error", "code"), response.status,
      publication.reload.state, task.reload.active_publication_id,
      record.response_data.dig("_operation_error", "code") ]
  end

  def superseded_candidate_reprepare_summary
    attempt = claim
    publication = Publication.find(prepare(attempt).dig("data", "id"))
    reconcile(attempt, publication, tip: "f" * 40, reachable: false, key: "supersede-candidate")
    repeated = prepare(attempt, key: "repeat-superseded-candidate")

    [ repeated.dig("error", "code"), Publication.count, task.reload.active_publication_id,
      publication.reload.state, task.active_attempt_id == attempt.id, attempt.reload.state ]
  end

  def recovery_summary
    attempt = claim
    publication = Publication.find(prepare(attempt).dig("data", "id"))
    reconcile(attempt, publication, tip: expected_oid, reachable: false, key: "pre-adoption-observation")
    WorkflowAttempts::Reconcile.call(repository:, attempt_id: attempt.id, observed_state: "publication_unknown",
      evidence_digest: digest, expected_lock_version: task.reload.lock_version, now: now + 303)
    replacement = claim(at: now + 304, owner: "replacement")
    confirm_worktree(replacement)
    context = WorkflowSteps::CaptureContext.call(repository:, attempt_id: replacement.id,
      fencing_token: replacement.fencing_token, expected_lock_version: task.reload.lock_version, now: now + 305)
    stale_code = begin
      Publications::Reconcile.call(repository:, publication_id: publication.id, candidate_sha:,
        observed_remote_tip: expected_oid, candidate_reachable: false, observed_at: now + 305,
        evidence_digest: digest, attempt_id: attempt.id, fencing_token: attempt.fencing_token,
        expected_lock_version: task.reload.lock_version, now: now + 305)
    rescue OperationError => error
      error.code
    end
    manifest = { "schema_version" => "1", "attempt_id" => replacement.id,
      "input_context_digest" => replacement.reload.input_context_digest, "artifacts" => [] }
    finish_codes = %w[failed needs_human].map do |state|
      begin
        WorkflowAttempts::Finish.call(repository:, attempt_id: replacement.id,
          fencing_token: replacement.fencing_token, expected_lock_version: task.reload.lock_version,
          manifest: manifest.merge("outcome" => state), state:, now: now + 306)
      rescue OperationError => error
        error.code
      end
    end
    complete_code = operation_error_code do
      WorkflowSteps::Complete.call(repository:, task_number: task.number, to_status: "completed",
        attempt_id: replacement.id, fencing_token: replacement.fencing_token,
        expected_lock_version: task.reload.lock_version, manifest: manifest.merge("outcome" => "succeeded"),
        now: now + 306)
    end
    database_guard = database_completion_guard(replacement, manifest)

    [ publication.reload.current_owner_attempt_id, publication.observation_owner_attempt_id,
      context.fetch("publication"), stale_code, finish_codes,
      complete_code, database_guard,
      Kos::Cli::SchemaRegistry.new.valid?("workflow.json", "context", context), attempt.id, replacement.id ]
  end

  def mismatched_reservation_head_code
    attempt = claim
    prepare(attempt)
    confirm_worktree(attempt)
    task.worktree_reservation.update!(head_sha: "d" * 40)

    operation_error_code do
      WorkflowSteps::CaptureContext.call(repository:, attempt_id: attempt.id,
        fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now: now + 3)
    end
  end

  def operation_error_code
    yield
    nil
  rescue OperationError => error
    error.code
  end

  def database_completion_guard(attempt, manifest)
    attempt.update_columns(state: "failed", lease_expires_at: nil, completed_at: now + 306,
      result_manifest: JSON.generate(manifest.merge("outcome" => "failed")))
    false
  rescue ActiveRecord::StatementInvalid
    true
  end

  def precedence_summary
    attempt = claim
    prepare(attempt)
    request = { "schema_version" => "1", "attempt_id" => attempt.id, "input_context_digest" => digest,
      "effect" => { "operation" => "fetch", "remote" => "origin", "ref" => "refs/heads/main" } }
    task.repository_effects.create!(repository:, prepared_attempt: attempt, current_owner_attempt: attempt,
      request_digest: digest, request:, prepared_at: now + 2)
    invalid = begin
      WorkflowAttempts::Reconcile.call(repository:, attempt_id: attempt.id, observed_state: "publication_unknown",
        evidence_digest: digest, expected_lock_version: task.reload.lock_version, now: now + 303)
    rescue OperationError => error
      error.code
    end
    result = WorkflowAttempts::Reconcile.call(repository:, attempt_id: attempt.id,
      observed_state: "repository_effect_pending", evidence_digest: digest,
      expected_lock_version: task.reload.lock_version, now: now + 303)

    [ invalid, result.reconciliation_state ]
  end

  def cross_repository_summary
    publication = Publication.find(prepare(claim).dig("data", "id"))
    other = Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "ALT",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/other.git", base_ref: "refs/heads/main")
    get "/api/v1/repositories/#{other.id}/publications/#{publication.id}", headers: headers

    [ response.status, JSON.parse(response.body).dig("error", "code") ]
  end

  it "prepares, reads, and replays one schema-valid immutable intent" do
    summary = prepare_read_summary
    expect(summary).to eq([ candidate_sha, summary.last, 1, summary.last, 200, true, true,
      [ true, true ], summary.last ])
  end

  it "rejects changed candidate, trust, and ownership inputs without another intent" do
    expect(invalid_prepare_summary)
      .to eq([ %w[invalid_transition invalid_transition fencing_token_stale], 0, nil ])
  end

  it "keeps reachable and unchanged-base observations unresolved and stores the latest observation" do
    summary = unresolved_reconcile_summary
    expect(summary).to eq([ "reconciled", "reconciled", "e" * 40, true, summary.last ])
  end

  it "rejects older and equal observations before changing publication state" do
    summary = stale_reconcile_summary
    expect(summary).to eq([ %w[invalid_transition invalid_transition], true, summary.last ])
  end


  it "rejects observations before preparation and beyond the bounded future skew through the API" do
    expect(invalid_observation_time_summary).to eq(%w[invalid_transition invalid_transition prepared])
  end

  it "rejects observations before preparation and beyond the bounded future skew at the service boundary" do
    expect(invalid_service_observation_time_codes).to eq(%w[invalid_transition invalid_transition])
  end

  it "commits, records, and replays base_moved while superseding and detaching the intent" do
    expect(base_moved_summary).to eq([ "base_moved", "base_moved", 409, "superseded", nil, "base_moved" ])
  end

  it "does not prepare the same candidate generation after base movement" do
    expect(superseded_candidate_reprepare_summary)
      .to eq([ "invalid_transition", 1, nil, "superseded", true, "started" ])
  end

  it "classifies, adopts, fences, guards completion, and freezes complete publication context" do
    summary = recovery_summary
    expected = { "publication_id" => summary.fetch(2).fetch("publication_id"), "candidate_sha" => candidate_sha,
      "remote" => "origin", "base_ref" => "refs/heads/main", "expected_remote_oid" => expected_oid }
    expect(summary).to eq([ summary.last, summary.fetch(-2), expected, "fencing_token_stale",
      %w[invalid_transition invalid_transition], "invalid_transition", true, true, summary.fetch(-2), summary.last ])
  end


  it "rejects publication context when the confirmed reservation HEAD differs from the candidate" do
    expect(mismatched_reservation_head_code).to eq("context_unavailable")
  end

  it "gives an unresolved generic effect precedence during attempt recovery" do
    expect(precedence_summary).to eq(%w[invalid_transition repository_effect_pending])
  end

  it "does not disclose publications through another repository" do
    expect(cross_repository_summary).to eq([ 404, "publication_not_found" ])
  end
end
