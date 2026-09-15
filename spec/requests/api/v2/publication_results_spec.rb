require "rails_helper"
require Rails.root.join("lib/kos/push_evidence")
require Rails.root.join("spec/support/publication_preflight_helpers")
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe "API v2 publication results", :aggregate_failures, type: :request do
  include PublicationPreflightHelpers
  include WorkflowCatalogHelpers

  around do |example|
    previous_token = ENV["KOS_API_TOKEN"]
    ENV["KOS_API_TOKEN"] = "publication-result-test-token"
    example.run
  ensure
    ENV["KOS_API_TOKEN"] = previous_token
  end

  let(:now) { Time.current.change(usec: 123_456) }
  let(:candidate_sha) { "a" * 40 }
  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:version) { publish_workflow }
  let(:task) do
    Task.create!(repository:, sequence: 1, title: "Record publication result", task_input_schema_version: "1",
      approved_brief: "Persist the verified result.", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end

  def headers(key = nil)
    { "Authorization" => "Bearer publication-result-test-token", "Accept" => "application/json" }
      .tap { _1["Idempotency-Key"] = key if key }
  end

  def logical(command, body)
    { "schema_version" => "2", "command" => command, "repository_id" => repository.id, "body" => body }
  end

  def prepared_state
    advance_to_publication(task:, version:, candidate_sha:, now:)
    attempt = WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "publisher",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: "publication-result-api-claim", now:)
    reservation = WorktreeReservation.create!(repository:, task:, workflow_attempt: attempt,
      branch: "kos/task-#{task.number}", path: "/tmp/worktrees/#{task.number}", state: "confirmed",
      fencing_token: attempt.fencing_token, head_sha: candidate_sha,
      git_common_dir_digest: "sha256:#{'b' * 64}", confirmed_at: now)
    task.reload.update!(worktree_reservation: reservation)
    publication = Publications::Prepare.call(repository:, task_number: task.number, candidate_sha:,
      remote: repository.trusted_remote, base_ref: repository.base_ref, expected_remote_oid: "c" * 40,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now:)
    WorkflowSteps::CaptureContext.call(repository:, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now:)
    attempt.reload
    observed_at = (now + 1.second).utc.iso8601(6)
    Publications::Reconcile.call(repository:, publication_id: publication.id, candidate_sha:,
      observed_remote_tip: "d" * 40, candidate_reachable: true, observed_at:,
      evidence_digest: push_digest(publication, attempt, observed_at), attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now: now + 2.seconds)
    [ publication.reload, attempt ]
  end

  def push_digest(publication, attempt, observed_at)
    repository_snapshot = { "id" => repository.id, "git_common_dir" => repository.git_common_dir,
      "trusted_remote" => repository.trusted_remote, "trusted_remote_url" => repository.trusted_remote_url,
      "base_ref" => repository.base_ref }
    publication_snapshot = { "id" => publication.id, "repository_id" => repository.id,
      "current_owner_attempt_id" => attempt.id, "fencing_token" => attempt.fencing_token,
      "input_context_digest" => attempt.input_context_digest, "candidate_sha" => publication.candidate_sha,
      "remote" => publication.remote, "base_ref" => publication.base_ref,
      "expected_remote_oid" => publication.expected_remote_oid }
    Kos::PushEvidence.digest(repository: repository_snapshot, publication: publication_snapshot,
      candidate_sha:, remote: publication.remote, base_ref: publication.base_ref,
      observed_remote_tip: "d" * 40, candidate_reachable: true, observed_at:)
  end

  def manifest(publication, attempt)
    { "schema_version" => "1", "attempt_id" => attempt.id,
      "input_context_digest" => attempt.input_context_digest, "outcome" => "succeeded", "artifacts" => [
        { "schema_version" => "1", "type" => "publication", "state" => "published",
          "producer" => "workflow-step", "metadata" => { "kind" => "publication",
            "publication_id" => publication.id, "candidate_sha" => candidate_sha,
            "remote" => publication.remote, "base_ref" => publication.base_ref,
            "observed_remote_tip" => publication.observed_remote_tip, "reachable" => true,
            "observed_at" => publication.observed_at.utc.iso8601(6) } }
      ], "summary" => "Published the reviewed candidate." }
  end

  def record_and_read_summary
    publication, attempt = prepared_state
    body = { "publication_id" => publication.id,
      "result_manifest" => manifest(publication, attempt), "preconditions" => {
      "expected_lock_version" => task.reload.lock_version, "attempt_id" => attempt.id,
      "fencing_token" => attempt.fencing_token } }
    path = "/api/v2/repositories/#{repository.id}/publications/#{publication.id}/result"

    post path, params: logical("publication_result.record", body),
      headers: headers("publication-result-record"), as: :json
    recorded_status = response.status
    recorded = JSON.parse(response.body)
    post path, params: logical("publication_result.record", body),
      headers: headers("publication-result-record"), as: :json
    replay = JSON.parse(response.body)
    replay_status = response.status
    get path, headers: headers
    read = JSON.parse(response.body)

    [ recorded_status, replay_status, response.status, replay.fetch("data"), read.fetch("data"),
      read.dig("data", "observation_digest"),
      Kos::Cli::SchemaRegistry.new(version: "2").valid?("commands.json", "result", read),
      recorded.fetch("data"), publication.observation_digest, read.dig("data", "observed_at"),
      publication.observed_at.utc.iso8601(6) ]
  end

  it "records idempotently and discovers the exact result by repository-scoped publication id" do
    summary = record_and_read_summary
    expect(summary.first(7)).to eq([ 201, 201, 200, summary.fetch(7), summary.fetch(7), summary.fetch(8), true ])
    expect(summary.last(2)).to eq([ summary.fetch(9), summary.fetch(10) ])
  end

  def foreign_repository_summary
    publication, attempt = prepared_state
    PublicationResults::Record.call(repository:, publication_id: publication.id,
      result_manifest: manifest(publication, attempt), attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version)
    other = Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "ALT",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/other.git", base_ref: "refs/heads/main")

    get "/api/v2/repositories/#{other.id}/publications/#{publication.id}/result", headers: headers

    [ response.status, JSON.parse(response.body).dig("error", "code") ]
  end

  it "does not discover a result through another repository" do
    expect(foreign_repository_summary).to eq([ 404, "publication_result_not_found" ])
  end

  it "rejects a publication identifier that does not match the path" do
    expect(mismatched_publication_summary).to eq([ 400, "malformed_input" ])
  end

  def mismatched_publication_summary
    publication, attempt = prepared_state
    body = { "publication_id" => SecureRandom.uuid,
      "result_manifest" => manifest(publication, attempt), "preconditions" => {
        "expected_lock_version" => task.reload.lock_version, "attempt_id" => attempt.id,
        "fencing_token" => attempt.fencing_token } }
    post "/api/v2/repositories/#{repository.id}/publications/#{publication.id}/result",
      params: logical("publication_result.record", body), headers: headers("publication-result-mismatch"), as: :json
    [ response.status, JSON.parse(response.body).dig("error", "code") ]
  end
end
