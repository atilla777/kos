require "rails_helper"
require Rails.root.join("lib/kos/publication_preflight_evidence")
require Rails.root.join("spec/support/publication_preflight_helpers")
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe "API v2 publication preflights", :aggregate_failures, type: :request do
  include PublicationPreflightHelpers
  include WorkflowCatalogHelpers

  around do |example|
    previous_token = ENV["KOS_API_TOKEN"]
    ENV["KOS_API_TOKEN"] = "preflight-test-token"
    example.run
  ensure
    ENV["KOS_API_TOKEN"] = previous_token
  end

  let(:now) { Time.current.change(usec: 0) }
  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:version) do
    publish_workflow(JSON.parse(File.read(Rails.root.join("workflows/quick-fix/1.0.2.json"))))
  end
  let(:task) do
    Task.create!(repository:, sequence: 1, title: "Observed publication", task_input_schema_version: "1",
      approved_brief: "Prepare publication from observed state.", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end

  def candidate_sha = "a" * 40
  def observed_oid = "b" * 40

  def headers(key = nil)
    { "Authorization" => "Bearer preflight-test-token", "Accept" => "application/json" }
      .tap { _1["Idempotency-Key"] = key if key }
  end

  def logical(command, body)
    { "schema_version" => "2", "command" => command, "repository_id" => repository.id, "body" => body }
  end

  def claim
    advance_to_publication(task:, version:, candidate_sha:, now:)
    WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "publisher", lease_seconds: 300,
      expected_lock_version: task.reload.lock_version, idempotency_key: "publication-v2-claim", now:)
  end

  def preconditions(attempt)
    { "expected_lock_version" => task.reload.lock_version, "attempt_id" => attempt.id,
      "fencing_token" => attempt.fencing_token }
  end

  def lifecycle_summary
    attempt = claim
    prepare_body = { "task_number" => task.number, "candidate_sha" => candidate_sha,
      "remote" => repository.trusted_remote, "base_ref" => repository.base_ref,
      "preconditions" => preconditions(attempt) }
    post "/api/v2/repositories/#{repository.id}/tasks/#{task.number}/publication-preflights",
      params: logical("publication_preflight.prepare", prepare_body), headers: headers("preflight-prepare"), as: :json
    prepared = JSON.parse(response.body)
    preflight = PublicationPreflight.find(prepared.dig("data", "id"))

    get "/api/v2/repositories/#{repository.id}/publication-preflights/#{preflight.id}", headers: headers
    read = JSON.parse(response.body)
    observed_at = (now + 3).iso8601(6)
    digest = publication_preflight_evidence(repository:, preflight:, attempt:, observed_remote_oid: observed_oid,
      observed_at:)
    reconcile_body = { "preflight_id" => preflight.id, "observed_remote_oid" => observed_oid,
      "observed_at" => observed_at, "evidence_digest" => digest, "preconditions" => preconditions(attempt) }
    post "/api/v2/repositories/#{repository.id}/publication-preflights/#{preflight.id}/reconcile",
      params: logical("publication_preflight.reconcile", reconcile_body), headers: headers("preflight-reconcile"),
      as: :json
    reconciled = JSON.parse(response.body)
    consume_body = { "preflight_id" => preflight.id, "preconditions" => preconditions(attempt) }
    post "/api/v2/repositories/#{repository.id}/publication-preflights/#{preflight.id}/publication",
      params: logical("publication.prepare_observed", consume_body), headers: headers("publication-observed"), as: :json
    consumed = JSON.parse(response.body)

    [ prepared.dig("data", "state"), read.dig("data", "id"), preflight.id,
      reconciled.dig("data", "state"), consumed.dig("data", "expected_remote_oid"),
      Kos::Cli::SchemaRegistry.new(version: "2").valid?("commands.json", "result", consumed) ]
  end

  it "prepares, reads, reconciles, and consumes without accepting a caller OID at preparation" do
    summary = lifecycle_summary
    expect(summary).to eq([ "prepared", summary.fetch(2), summary.fetch(2), "reconciled", observed_oid, true ])
  end

  def unknown_summary
    attempt = claim
    preflight = PublicationPreflights::Prepare.call(repository:, task_number: task.number, candidate_sha:,
      remote: repository.trusted_remote, base_ref: repository.base_ref, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now:)
    error = { "category" => "transient", "code" => "publication_preflight_state_uncertain",
      "message" => "Observation unavailable", "retryable" => true }
    body = { "preflight_id" => preflight.id, "unknown" => error, "preconditions" => preconditions(attempt) }

    post "/api/v2/repositories/#{repository.id}/publication-preflights/#{preflight.id}/reconcile",
      params: logical("publication_preflight.reconcile", body), headers: headers("preflight-unknown"), as: :json
    document = JSON.parse(response.body)

    [ response.status, document.dig("data", "state"), document.dig("data", "error"), error ]
  end

  it "persists and serializes a closed unknown observation" do
    summary = unknown_summary
    expect(summary.first(3)).to eq([ 200, "unknown", summary.last ])
  end

  def missing_attempt_summary
    attempt = claim
    body = { "task_number" => task.number, "candidate_sha" => candidate_sha, "remote" => "origin",
      "base_ref" => repository.base_ref, "preconditions" => preconditions(attempt).merge(
        "attempt_id" => SecureRandom.uuid) }
    post "/api/v2/repositories/#{repository.id}/tasks/#{task.number}/publication-preflights",
      params: logical("publication_preflight.prepare", body), headers: headers("missing-attempt"), as: :json
    [ response.status, JSON.parse(response.body).dig("error", "code") ]
  end

  it "returns the version 2 not-found contract for an absent attempt" do
    expect(missing_attempt_summary).to eq([ 404, "attempt_not_found" ])
  end

  def recovery_summary
    attempt = claim
    reservation = WorktreeReservation.create!(repository:, task:, workflow_attempt: attempt,
      branch: "kos/task-#{task.number}", path: "/tmp/worktrees/#{task.number}", state: "confirmed",
      fencing_token: attempt.fencing_token, head_sha: candidate_sha,
      git_common_dir_digest: "sha256:#{'d' * 64}", confirmed_at: now)
    task.reload.update!(worktree_reservation: reservation)
    publication = Publications::Prepare.call(repository:, task_number: task.number, candidate_sha:,
      remote: repository.trusted_remote, base_ref: repository.base_ref, expected_remote_oid: observed_oid,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now:)
    WorkflowSteps::CaptureContext.call(repository:, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now:)
    expect do
      Publications::Reconcile.call(repository:, publication_id: publication.id, candidate_sha:,
        observed_remote_tip: "c" * 40, candidate_reachable: false, observed_at: now + 1.second,
        evidence_digest: "sha256:#{'e' * 64}", attempt_id: attempt.id,
        fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now: now + 2.seconds)
    end.to raise_error(CommittedOperationError)
    body = { "publication_id" => publication.id, "preconditions" => preconditions(attempt) }
    path = "/api/v2/repositories/#{repository.id}/publications/#{publication.id}/recover-base-moved"
    post path, params: logical("publication.recover_base_moved", body),
      headers: headers("base-moved-recovery"), as: :json
    first = JSON.parse(response.body)
    first_status = response.status
    post path, params: logical("publication.recover_base_moved", body),
      headers: headers("base-moved-recovery"), as: :json
    replay = JSON.parse(response.body)

    [ first_status, first.dig("data", "to_status"), task.reload.workflow_state.identifier,
      attempt.reload.state, replay.fetch("data"), first.fetch("data"),
      Kos::Cli::SchemaRegistry.new(version: "2").valid?("commands.json", "result", replay) ]
  end

  it "recovers a moved base through the closed idempotent version 2 contract" do
    summary = recovery_summary
    expect(summary).to eq([ 200, "base-synchronization", "base-synchronization", "succeeded",
      summary.fetch(5), summary.fetch(5), true ])
  end

  it "routes atomic rebase reconciliation through its closed version 2 contract" do
    expect(missing_rebase_effect_summary).to eq([ 404, "effect_not_found" ])
  end

  def missing_rebase_effect_summary
    effect_id = SecureRandom.uuid
    body = { "effect_id" => effect_id, "head_sha" => "a" * 40,
      "rebase_evidence_digest" => "sha256:#{'a' * 64}",
      "worktree_evidence_digest" => "sha256:#{'b' * 64}", "preconditions" => {
        "expected_lock_version" => 0, "attempt_id" => SecureRandom.uuid, "fencing_token" => 1 } }
    post "/api/v2/repositories/#{repository.id}/repository-effects/#{effect_id}/reconcile-rebase",
      params: logical("effect.reconcile_rebase", body), headers: headers("rebase-reconcile"), as: :json

    [ response.status, JSON.parse(response.body).dig("error", "code") ]
  end
end
