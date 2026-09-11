require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe "API v1 worktree reservations", :aggregate_failures, type: :request do
  include WorkflowCatalogHelpers
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    previous = ENV["KOS_API_TOKEN"]
    ENV["KOS_API_TOKEN"] = "worktree-test-token"
    example.run
  ensure
    ENV["KOS_API_TOKEN"] = previous
  end

  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:task) do
    type = quick_fix_task_type
    version = publish_workflow
    Task.create!(repository:, sequence: 1, title: "Reserve through API", task_type: type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end
  let(:head_sha) { "b" * 40 }
  let(:evidence_digest) { "sha256:#{'a' * 64}" }

  def headers(key)
    { "Authorization" => "Bearer worktree-test-token", "Accept" => "application/json",
      "Idempotency-Key" => key }
  end

  def request_document(command, body, repository_id: repository.id)
    { "schema_version" => "1", "command" => command, "repository_id" => repository_id, "body" => body }
  end

  def claim
    WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "orchestrator",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version, idempotency_key: "direct-claim")
  end

  def preconditions(attempt)
    { "expected_lock_version" => task.reload.lock_version, "attempt_id" => attempt.id,
      "fencing_token" => attempt.fencing_token }
  end

  def post_command(command, path, body, key, repository_id: repository.id)
    post path, params: request_document(command, body, repository_id:), headers: headers(key), as: :json
    JSON.parse(response.body)
  end

  def reserve_body(attempt)
    { "task_number" => task.number, "branch" => "kos/task-#{task.number}",
      "path" => "/tmp/worktrees/#{task.number}", "preconditions" => preconditions(attempt) }
  end

  def replay_summary
    attempt = claim
    body = reserve_body(attempt)
    path = "/api/v1/repositories/#{repository.id}/tasks/#{task.number}/worktree-reservations"
    first = post_command("worktree.reserve", path, body, "worktree-reserve-key")
    second = travel_to(6.minutes.from_now) do
      post_command("worktree.reserve", path, body, "worktree-reserve-key")
    end
    [ response.status, first.dig("data", "id"), second.dig("data", "id"), WorktreeReservation.count,
      Kos::Cli::SchemaRegistry.new.valid?("commands.json", "result", second) ]
  end

  def api_release_summary
    attempt = claim
    reserve_path = "/api/v1/repositories/#{repository.id}/tasks/#{task.number}/worktree-reservations"
    reserved = post_command("worktree.reserve", reserve_path, reserve_body(attempt), "reserve-for-release")
    reservation_id = reserved.dig("data", "id")
    base = "/api/v1/repositories/#{repository.id}/worktree-reservations/#{reservation_id}"
    confirmed = post_command("worktree.confirm", "#{base}/confirm", confirmation_body(attempt, reservation_id),
      "confirm-worktree")
    pending = post_command("worktree.release", "#{base}/release",
      observation_body(attempt, reservation_id, "clean", head_sha), "release-worktree-clean")
    released = post_command("worktree.release", "#{base}/release",
      observation_body(attempt, reservation_id, "absent"), "release-worktree-absent")
    [ confirmed.dig("data", "state"), pending.dig("data", "state"), released.dig("data", "state"),
      response.status, task.reload.worktree_reservation_id ]
  end

  def confirmation_body(attempt, reservation_id)
    digest = "sha256:#{Digest::SHA256.hexdigest(repository.git_common_dir)}"
    { "reservation_id" => reservation_id, "git_common_dir_digest" => digest, "head_sha" => head_sha,
      "preconditions" => preconditions(attempt) }
  end

  def cross_repository_summary
    attempt = claim
    reservation = WorktreeReservations::Reserve.call(repository:, task_number: task.number,
      branch: "kos/task-#{task.number}", path: "/tmp/worktrees/#{task.number}", attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version)
    other = Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "ALT",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/other.git", base_ref: "refs/heads/main")
    result = post_command("worktree.reconcile",
      "/api/v1/repositories/#{other.id}/worktree-reservations/#{reservation.id}/reconcile",
      observation_body(attempt, reservation.id, "dirty"), "cross-repository-reconcile", repository_id: other.id)
    [ response.status, result.dig("error", "code") ]
  end

  def idempotency_conflict_summary
    attempt = claim
    path = "/api/v1/repositories/#{repository.id}/tasks/#{task.number}/worktree-reservations"
    body = reserve_body(attempt)
    post_command("worktree.reserve", path, body, "conflicting-reserve-key")
    changed = body.merge("path" => "/tmp/worktrees/other")
    result = post_command("worktree.reserve", path, changed, "conflicting-reserve-key")
    [ response.status, result.dig("error", "code"), WorktreeReservation.count ]
  end

  def identity_mismatch_summary
    attempt = claim
    path = "/api/v1/repositories/#{repository.id}/tasks/#{task.number}/worktree-reservations"
    body = reserve_body(attempt).merge("task_number" => "KOS-000002", "branch" => "kos/task-KOS-000002")
    result = post_command("worktree.reserve", path, body, "mismatched-reserve-key")
    [ response.status, result.dig("error", "code"), WorktreeReservation.count ]
  end

  it "reserves once and replays the original HTTP 201 result after lease expiry" do
    summary = replay_summary
    expect(summary).to eq([ 201, summary.fetch(1), summary.fetch(1), 1, true ])
  end

  it "confirms, prepares release, and completes release through schema-valid endpoints" do
    expect(api_release_summary)
      .to eq([ "confirmed", "release_pending", "released", 200, nil ])
  end

  it "does not disclose a reservation from another repository" do
    expect(cross_repository_summary).to eq([ 404, "reservation_not_found" ])
  end

  it "rejects reuse of an idempotency key with another allocation" do
    expect(idempotency_conflict_summary).to eq([ 409, "idempotency_conflict", 1 ])
  end

  it "rejects task path and body identity mismatch before mutation" do
    expect(identity_mismatch_summary).to eq([ 400, "malformed_input", 0 ])
  end

  def observation_body(attempt, reservation_id, observed_state, observed_head = nil)
    { "reservation_id" => reservation_id, "observed_state" => observed_state,
      "evidence_digest" => evidence_digest, "preconditions" => preconditions(attempt) }
      .tap { |body| body["head_sha"] = observed_head if observed_head }
  end
end
