require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe "API v1 repository effects", :aggregate_failures, type: :request do
  include WorkflowCatalogHelpers
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    previous = ENV["KOS_API_TOKEN"]
    ENV["KOS_API_TOKEN"] = "effect-test-token"
    example.run
  ensure
    ENV["KOS_API_TOKEN"] = previous
  end

  let(:digest) { "sha256:#{'a' * 64}" }
  let(:head_sha) { "b" * 40 }
  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:task) do
    type = quick_fix_task_type
    version = publish_workflow
    Task.create!(repository:, sequence: 1, title: "Persist repository effect", task_type: type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end

  def headers(key = nil)
    { "Authorization" => "Bearer effect-test-token", "Accept" => "application/json" }
      .tap { |value| value["Idempotency-Key"] = key if key }
  end

  def claim(now: Time.current, owner: "orchestrator")
    WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: owner, lease_seconds: 300,
      expected_lock_version: task.reload.lock_version, idempotency_key: "claim-#{SecureRandom.hex(5)}", now:)
  end

  def freeze_context(attempt, allowed: %w[commit fetch rebase])
    attempt.update!(input_context: {
      "allowed_repository_effects" => allowed,
      "worktree" => { "reservation_id" => SecureRandom.uuid, "head_sha" => head_sha }
    }, input_context_digest: digest)
  end

  def preconditions(attempt)
    { "expected_lock_version" => task.reload.lock_version, "attempt_id" => attempt.id,
      "fencing_token" => attempt.fencing_token }
  end

  def effect_request(attempt, operation)
    effect = case operation
    when "commit"
      { "operation" => operation, "reservation_id" => attempt.input_context.dig("worktree", "reservation_id"),
        "expected_head_sha" => head_sha, "expected_diff_digest" => digest,
        "expected_index_digest" => digest, "paths" => [ "app/model.rb" ], "message" => "Implement effect",
        "task_number" => task.number }
    when "fetch"
      { "operation" => operation, "remote" => "origin", "ref" => "refs/heads/main" }
    when "rebase"
      { "operation" => operation, "reservation_id" => attempt.input_context.dig("worktree", "reservation_id"),
        "expected_head_sha" => head_sha, "onto_sha" => "c" * 40 }
    end
    { "schema_version" => "1", "attempt_id" => attempt.id, "input_context_digest" => digest,
      "effect" => effect }
  end

  def prepare(attempt, operation, key: "prepare-#{SecureRandom.hex(5)}")
    body = { "task_number" => task.number, "effect_request" => effect_request(attempt, operation),
      "preconditions" => preconditions(attempt) }
    path = "/api/v1/repositories/#{repository.id}/tasks/#{task.number}/repository-effects"
    post path, params: logical("effect.prepare", body), headers: headers(key), as: :json
    JSON.parse(response.body)
  end

  def reconcile(attempt, effect, outcome: "succeeded", key: "reconcile-#{SecureRandom.hex(5)}")
    operation = effect.request.dig("effect", "operation")
    result = if outcome == "succeeded"
      success_result(operation)
    else
      { "outcome" => outcome, "operation" => operation,
        "error" => { "category" => "transient", "code" => "adapter_unavailable",
          "message" => "Adapter response is unavailable", "retryable" => true } }
    end
    effect_result = { "schema_version" => "1", "effect_intent_id" => effect.id,
      "request_attempt_id" => effect.prepared_attempt_id, "owner_attempt_id" => attempt.id,
      "input_context_digest" => digest, "effect_request_digest" => effect.request_digest, "result" => result }
    body = { "effect_id" => effect.id, "effect_result" => effect_result,
      "preconditions" => preconditions(attempt) }
    path = "/api/v1/repositories/#{repository.id}/repository-effects/#{effect.id}/reconcile"
    post path, params: logical("effect.reconcile", body), headers: headers(key), as: :json
    JSON.parse(response.body)
  end

  def success_result(operation)
    case operation
    when "commit"
      { "outcome" => "succeeded", "operation" => operation, "commit_sha" => "d" * 40,
        "evidence_digest" => digest }
    when "fetch"
      { "outcome" => "succeeded", "operation" => operation, "remote" => "origin",
        "ref" => "refs/heads/main", "observed_oid" => "d" * 40, "evidence_digest" => digest }
    when "rebase"
      { "outcome" => "succeeded", "operation" => operation, "head_sha" => "d" * 40,
        "evidence_digest" => digest }
    end
  end

  def effect_result(attempt, effect, outcome: "succeeded")
    operation = effect.request.dig("effect", "operation")
    result = outcome == "succeeded" ? success_result(operation) : {
      "outcome" => outcome, "operation" => operation,
      "error" => { "category" => "transient", "code" => "adapter_unavailable",
        "message" => "Adapter response is unavailable", "retryable" => true }
    }
    { "schema_version" => "1", "effect_intent_id" => effect.id,
      "request_attempt_id" => effect.prepared_attempt_id, "owner_attempt_id" => attempt.id,
      "input_context_digest" => digest, "effect_request_digest" => effect.request_digest, "result" => result }
  end

  def logical(command, body, repository_id: repository.id)
    { "schema_version" => "1", "command" => command, "repository_id" => repository_id, "body" => body }
  end

  def generic_round_trip_summary
    attempt = claim
    freeze_context(attempt)
    %w[commit fetch rebase].map do |operation|
      prepared = prepare(attempt, operation)
      prepared_status = response.status
      prepared_valid = Kos::Cli::SchemaRegistry.new.valid?("commands.json", "result", prepared)
      effect = RepositoryEffect.find(prepared.dig("data", "id"))
      get "/api/v1/repositories/#{repository.id}/repository-effects/#{effect.id}", headers: headers
      read = JSON.parse(response.body)
      read_status = response.status
      read_digest = read.dig("data", "request_digest")
      read_valid = Kos::Cli::SchemaRegistry.new.valid?("commands.json", "result", read)
      reconciled = reconcile(attempt, effect)
      reconciled_valid = Kos::Cli::SchemaRegistry.new.valid?("commands.json", "result", reconciled)
      [ prepared_status, prepared_valid, read_status, read_digest, read_valid, response.status,
        reconciled.dig("data", "state"), reconciled_valid, effect.request_digest ]
    end
  end

  def prepare_replay_summary
    attempt = claim
    freeze_context(attempt)
    key = "prepare-replay-key"
    first = prepare(attempt, "fetch", key:)
    second = travel_to(6.minutes.from_now) { prepare(attempt, "fetch", key:) }
    [ response.status, first.dig("data", "id"), second.dig("data", "id"), RepositoryEffect.count ]
  end

  def prepare_conflict_summary
    attempt = claim
    freeze_context(attempt)
    key = "prepare-conflict-key"
    prepare(attempt, "fetch", key:)
    changed = effect_request(attempt, "fetch")
    changed.fetch("effect")["ref"] = "refs/heads/other"
    body = { "task_number" => task.number, "effect_request" => changed,
      "preconditions" => preconditions(attempt) }
    path = "/api/v1/repositories/#{repository.id}/tasks/#{task.number}/repository-effects"
    post path, params: logical("effect.prepare", body), headers: headers(key), as: :json
    [ response.status, JSON.parse(response.body).dig("error", "code"), RepositoryEffect.count ]
  end

  def prepare_mismatch_summary
    attempt = claim
    freeze_context(attempt, allowed: [ "fetch" ])
    base = { repository:, task_number: task.number, effect_request: effect_request(attempt, "fetch"),
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version }
    changes = [
      { expected_lock_version: base.fetch(:expected_lock_version) + 1 },
      { fencing_token: attempt.fencing_token + 1 },
      { effect_request: base.fetch(:effect_request).merge("attempt_id" => SecureRandom.uuid) },
      { effect_request: base.fetch(:effect_request).merge("input_context_digest" => "sha256:#{'b' * 64}") },
      { effect_request: effect_request(attempt, "commit") }
    ]
    [ changes.map { |attributes| operation_error_code { RepositoryEffects::Prepare.call(**base.merge(attributes)) } },
      RepositoryEffect.count ]
  end

  def reconcile_mismatch_summary
    attempt = claim
    freeze_context(attempt)
    effect = RepositoryEffect.find(prepare(attempt, "fetch").dig("data", "id"))
    base = { repository:, effect_id: effect.id, effect_result: effect_result(attempt, effect),
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version }
    mutations = [
      ->(value) { value.merge("effect_intent_id" => SecureRandom.uuid) },
      ->(value) { value.merge("request_attempt_id" => SecureRandom.uuid) },
      ->(value) { value.merge("owner_attempt_id" => SecureRandom.uuid) },
      ->(value) { value.merge("input_context_digest" => "sha256:#{'b' * 64}") },
      ->(value) { value.merge("effect_request_digest" => "sha256:#{'b' * 64}") },
      ->(value) { value.merge("result" => success_result("commit")) }
    ]
    codes = mutations.map do |mutation|
      document = mutation.call(JSON.parse(JSON.generate(base.fetch(:effect_result))))
      operation_error_code { RepositoryEffects::Reconcile.call(**base.merge(effect_result: document)) }
    end
    precondition_codes = [
      operation_error_code { RepositoryEffects::Reconcile.call(**base.merge(expected_lock_version: 99)) },
      operation_error_code { RepositoryEffects::Reconcile.call(**base.merge(fencing_token: 99)) },
      operation_error_code { RepositoryEffects::Reconcile.call(**base.merge(now: 6.minutes.from_now)) }
    ]
    [ codes, precondition_codes, effect.reload.state ]
  end

  def commit_binding_summary
    attempt = claim
    freeze_context(attempt, allowed: [ "commit" ])
    base = { repository:, task_number: task.number, effect_request: effect_request(attempt, "commit"),
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version }
    reservation = JSON.parse(JSON.generate(base.fetch(:effect_request)))
    reservation.fetch("effect")["reservation_id"] = SecureRandom.uuid
    number = JSON.parse(JSON.generate(base.fetch(:effect_request)))
    number.fetch("effect")["task_number"] = "KOS-000002"
    [ reservation, number ].map do |request|
      operation_error_code { RepositoryEffects::Prepare.call(**base.merge(effect_request: request)) }
    end
  end

  def reconcile_lifecycle_summary
    attempt = claim
    freeze_context(attempt)
    effect = RepositoryEffect.find(prepare(attempt, "fetch").dig("data", "id"))
    first = reconcile(attempt, effect, outcome: "unknown", key: "first-unknown-key")
    second = reconcile(attempt, effect.reload, outcome: "unknown", key: "second-unknown-key")
    terminal = reconcile(attempt, effect.reload, key: "terminal-effect-key")
    replay = travel_to(6.minutes.from_now) do
      reconcile(attempt, effect.reload, key: "terminal-effect-key")
    end
    rejected = reconcile(attempt, effect.reload, key: "terminal-effect-other-key")
    [ first.dig("data", "state"), second.dig("data", "state"), terminal.dig("data", "state"),
      replay.dig("data", "state"), response.status, rejected.dig("error", "code") ]
  end

  def adoption_summary
    started_at = Time.current
    attempt = claim(now: started_at)
    freeze_context(attempt)
    effect = RepositoryEffect.find(prepare(attempt, "commit").dig("data", "id"))
    pending = RepositoryEffect.find(prepare(attempt, "fetch").dig("data", "id"))
    reconcile(attempt, effect, outcome: "unknown")
    mismatch = operation_error_code do
      WorkflowAttempts::Reconcile.call(repository:, attempt_id: attempt.id, observed_state: "no_effect",
        evidence_digest: digest, expected_lock_version: task.reload.lock_version, now: started_at + 301)
    end
    WorkflowAttempts::Reconcile.call(repository:, attempt_id: attempt.id,
      observed_state: "repository_effect_pending", evidence_digest: digest,
      expected_lock_version: task.reload.lock_version, now: started_at + 301)
    replacement = claim(now: started_at + 302, owner: "replacement")
    stale = reconcile(attempt, effect.reload)
    stale_summary = [ response.status, stale.dig("error", "code") ]
    resolved = reconcile(replacement, effect.reload)
    schema_valid = Kos::Cli::SchemaRegistry.new.valid?("resources.json", "repository_effect",
      Api::V1::Serializer.repository_effect(pending))
    [ mismatch, stale_summary, response.status, resolved.dig("data", "state"),
      effect.reload.current_owner_attempt_id, pending.reload.current_owner_attempt_id, replacement.id, schema_valid ]
  end

  def unresolved_completion_summary
    attempt = claim
    freeze_context(attempt)
    request = effect_request(attempt, "commit")
    request.fetch("effect")["expected_head_sha"] = "e" * 40
    body = { "task_number" => task.number, "effect_request" => request,
      "preconditions" => preconditions(attempt) }
    path = "/api/v1/repositories/#{repository.id}/tasks/#{task.number}/repository-effects"
    post path, params: logical("effect.prepare", body), headers: headers("binding-mismatch"), as: :json
    binding_code = JSON.parse(response.body).dig("error", "code")
    prepare(attempt, "fetch")
    manifest = { "schema_version" => "1", "attempt_id" => attempt.id, "input_context_digest" => digest,
      "outcome" => "failed", "artifacts" => [] }
    finish_codes = %w[failed needs_human].map do |state|
      state_manifest = manifest.merge("outcome" => state)
      operation_error_code do
        WorkflowAttempts::Finish.call(repository:, attempt_id: attempt.id, fencing_token: attempt.fencing_token,
          expected_lock_version: task.reload.lock_version, manifest: state_manifest, state:)
      end
    end
    complete_code = operation_error_code do
      WorkflowSteps::Complete.call(repository:, task_number: task.number, to_status: "development",
        attempt_id: attempt.id, fencing_token: attempt.fencing_token,
        expected_lock_version: task.reload.lock_version, manifest: manifest.merge("outcome" => "succeeded"))
    end
    [ binding_code, finish_codes, complete_code ]
  end

  def cross_repository_summary
    attempt = claim
    freeze_context(attempt)
    effect_id = prepare(attempt, "fetch").dig("data", "id")
    other = Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "ALT",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/other.git", base_ref: "refs/heads/main")
    get "/api/v1/repositories/#{other.id}/repository-effects/#{effect_id}", headers: headers
    [ response.status, JSON.parse(response.body).dig("error", "code") ]
  end

  def operation_error_code
    yield
    nil
  rescue OperationError => error
    error.code
  end

  it "prepares, reads, and reconciles every generic effect type with schema-valid resources" do
    expect(generic_round_trip_summary).to all(satisfy { |value|
      value == [ 201, true, 200, value.last, true, 200, "succeeded", true, value.last ]
    })
  end

  it "replays one prepared intent with its original 201 after lease expiry" do
    summary = prepare_replay_summary
    expect(summary).to eq([ 201, summary.fetch(1), summary.fetch(1), 1 ])
  end

  it "conflicts when a prepare key is reused with another request" do
    expect(prepare_conflict_summary).to eq([ 409, "idempotency_conflict", 1 ])
  end

  it "rejects every prepare ownership and frozen-context mismatch without creating an intent" do
    expect(prepare_mismatch_summary).to eq([
      %w[stale_lock_version fencing_token_stale context_unavailable context_unavailable invalid_transition], 0
    ])
  end

  it "rejects every stored-result binding mismatch without changing the prepared intent" do
    expect(reconcile_mismatch_summary).to eq([ Array.new(6, "invalid_transition"),
      %w[stale_lock_version fencing_token_stale lease_expired], "prepared" ])
  end

  it "rejects commit reservation and task-number mismatches" do
    expect(commit_binding_summary).to eq(%w[invalid_transition invalid_transition])
  end

  it "reconciles repeated unknown observations and replays one terminal result" do
    expect(reconcile_lifecycle_summary)
      .to eq(%w[unknown unknown succeeded succeeded] + [ 409, "invalid_transition" ])
  end

  it "adopts an unknown effect after lease recovery and fences out the old owner" do
    summary = adoption_summary
    expect(summary).to eq([ "invalid_transition", [ 409, "fencing_token_stale" ], 200, "succeeded",
      summary.fetch(6), summary.fetch(6), summary.fetch(6), true ])
  end

  it "rejects context bindings and attempt completion while an effect is unresolved" do
    expect(unresolved_completion_summary)
      .to eq([ "invalid_transition", %w[invalid_transition invalid_transition], "invalid_transition" ])
  end

  it "does not disclose an effect through another repository" do
    expect(cross_repository_summary).to eq([ 404, "effect_not_found" ])
  end
end
