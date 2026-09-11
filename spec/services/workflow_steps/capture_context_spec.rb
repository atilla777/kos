require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe WorkflowSteps::CaptureContext, :aggregate_failures do
  include WorkflowCatalogHelpers

  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:version) { publish_workflow }
  let(:task) do
    Task.create!(repository:, sequence: 1, title: "Freeze context", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end
  let(:now) { Time.utc(2026, 9, 11, 12) }

  def claim(key: "claim-context-key", at: now)
    WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "orchestrator-1",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: key, now: at)
  end

  def confirm_worktree(attempt)
    reservation = WorktreeReservation.create!(repository:, task:, workflow_attempt: attempt,
      branch: "kos/task-#{task.number}", path: "/tmp/worktrees/#{task.number}", state: "confirmed",
      fencing_token: attempt.fencing_token, git_common_dir_digest: "sha256:#{'a' * 64}",
      head_sha: "b" * 40, confirmed_at: now)
    task.reload.update!(worktree_reservation: reservation)
    reservation
  end

  def capture(attempt, **overrides)
    described_class.call(repository:, attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now: now + 1, **overrides)
  end

  def complete_step(attempt, to_status, artifacts)
    digest = "sha256:#{'d' * 64}"
    artifacts = JSON.parse(JSON.generate(artifacts))
    attempt.update!(input_context: { "schema_version" => "1" }, input_context_digest: digest)
    manifest = { "schema_version" => "1", "attempt_id" => attempt.id, "input_context_digest" => digest,
      "outcome" => "succeeded", "artifacts" => artifacts }
    canonical = WorkflowCatalog::CanonicalDefinition.canonical_json(artifacts)
    verification = RepositoryEvidence::VerifyArtifacts::Verification.new(repository.id, task.number,
      "sha256:#{Digest::SHA256.hexdigest(canonical)}")
    WorkflowSteps::Complete.call(repository:, task_number: task.number, to_status:, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, manifest:,
      verified_evidence: verification, now: now + 1)
  end

  def expect_exact_context
    attempt = claim
    reservation = confirm_worktree(attempt)
    status = workflow_definition.fetch("statuses").find { _1.fetch("id") == "implementation-planning" }
    context = capture(attempt)
    canonical = WorkflowCatalog::CanonicalDefinition.canonical_json(context.except("input_context_digest"))
    digest = "sha256:#{Digest::SHA256.hexdigest(canonical)}"
    expect(context).to include(
      "task_id" => task.id, "task_number" => task.number, "attempt_id" => attempt.id,
      "repository_id" => repository.id, "workflow_version_id" => version.id,
      "workflow_status" => "implementation-planning", "instruction" => status.fetch("instruction"),
      "artifact_templates" => status.fetch("artifact_templates").sort_by { _1.fetch("id") },
      "required_artifacts" => status.fetch("required_artifacts").sort_by { _1.fetch("type") },
      "allowed_repository_effects" => status.fetch("allowed_repository_effects").sort,
      "expected_lock_version" => task.lock_version, "fencing_token" => attempt.fencing_token,
      "base_ref" => repository.base_ref, "retrospective_enabled" => false,
      "worktree" => { "reservation_id" => reservation.id, "path" => reservation.path,
        "branch" => reservation.branch, "head_sha" => reservation.head_sha },
      "input_context_digest" => digest)
    expect([ attempt.reload.input_context_digest, attempt.input_context,
      Kos::Cli::SchemaRegistry.new.valid?("workflow.json", "context", context) ])
      .to eq([ digest, context, true ])
  end

  def frozen_setting_summary
    attempt = claim
    confirm_worktree(attempt)
    first = capture(attempt)
    RuntimeConfig.current.update!(retrospective_enabled: true)
    [ capture(attempt), first, first.fetch("retrospective_enabled") ]
  end

  def replacement_worktree_summary
    original = claim
    reservation = confirm_worktree(original)
    WorkflowAttempts::Reconcile.call(repository:, attempt_id: original.id,
      observed_state: "worktree_materialized", evidence_digest: "sha256:#{'c' * 64}",
      expected_lock_version: task.reload.lock_version, now: now + 301)
    replacement = claim(key: "replacement-context-claim", at: now + 302)
    context = capture(replacement, now: now + 303)
    [ context.dig("worktree", "reservation_id"), reservation.id, context.fetch("fencing_token"),
      replacement.fencing_token ]
  end

  def candidate_context_summary
    document = { "schema_version" => "1", "type" => "document", "state" => "produced",
      "producer" => "workflow-step", "metadata" => { "kind" => "document",
        "path" => "tasks/#{task.number}/implementation-plan.md", "commit_sha" => "a" * 40,
        "content_digest" => "sha256:#{'a' * 64}" } }
    complete_step(claim, "development", [ document ])
    old_candidate_sha = "b" * 40
    candidate = { "schema_version" => "1", "type" => "candidate", "state" => "produced",
      "producer" => "workflow-step", "metadata" => { "kind" => "candidate", "candidate_sha" => old_candidate_sha,
        "task_trailer" => task.number } }
    test = { "schema_version" => "1", "type" => "test", "state" => "passed",
      "producer" => "workflow-step", "metadata" => { "kind" => "test", "candidate_sha" => old_candidate_sha,
        "command" => "bundle exec rspec", "exit_code" => 0, "log_digest" => "sha256:#{'a' * 64}" } }
    complete_step(claim(key: "development-context-claim"), "review", [ candidate, test ])
    review = claim(key: "changes-requested-context-claim")
    review_artifact = { "schema_version" => "1", "type" => "review", "state" => "changes_requested",
      "producer" => "workflow-step", "metadata" => { "kind" => "review", "candidate_sha" => old_candidate_sha,
        "verdict" => "changes_requested", "review_attempt_id" => review.id } }
    complete_step(review, "development", [ review_artifact ])
    candidate_sha = "c" * 40
    candidate["metadata"]["candidate_sha"] = candidate_sha
    test["metadata"]["candidate_sha"] = candidate_sha
    complete_step(claim(key: "replacement-development-claim"), "review", [ candidate, test ])
    review = claim(key: "review-context-claim")
    confirm_worktree(review)
    [ capture(review).fetch("candidate_sha"), candidate_sha ]
  end

  def publication_error_code
    task.reload.update!(workflow_state: version.workflow_states.find_by!(identifier: "publication"))
    attempt = claim
    confirm_worktree(attempt)
    capture(attempt)
  rescue OperationError => error
    error.code
  end

  it "freezes the exact validated pinned step context and canonical digest" do
    expect_exact_context
  end

  it "returns the frozen context without rebuilding mutable installation input" do
    summary = frozen_setting_summary
    expect(summary).to eq([ summary.fetch(1), summary.fetch(1), false ])
  end

  it "accepts a confirmed task worktree created by a reconciled earlier attempt" do
    summary = replacement_worktree_summary
    expect(summary).to eq([ summary.fetch(1), summary.fetch(1), summary.fetch(3), summary.fetch(3) ])
  end

  it "includes the candidate from the latest succeeded producer attempt" do
    summary = candidate_context_summary
    expect(summary).to eq([ summary.last, summary.last ])
  end

  it "requires a confirmed worktree without partially storing context" do
    attempt = claim

    expect { capture(attempt) }.to raise_error(OperationError) { |error|
      expect(error.code).to eq("context_unavailable")
    }
    expect(attempt.reload.attributes.values_at("input_context", "input_context_digest")).to eq([ nil, nil ])
  end

  it "checks stale fencing before lease expiry" do
    attempt = claim
    confirm_worktree(attempt)

    expect {
      capture(attempt, fencing_token: attempt.fencing_token + 1, now: now + 301)
    }.to raise_error(OperationError) { |error| expect(error.code).to eq("fencing_token_stale") }
  end

  it "treats the exact lease expiry as lost" do
    attempt = claim
    confirm_worktree(attempt)

    expect {
      capture(attempt, now: now + 300)
    }.to raise_error(OperationError) { |error| expect(error.code).to eq("lease_expired") }
  end

  it "rejects a stale expected lock version" do
    attempt = claim
    confirm_worktree(attempt)

    expect {
      capture(attempt, expected_lock_version: task.lock_version - 1)
    }.to raise_error(OperationError) { |error| expect(error.code).to eq("stale_lock_version") }
  end

  it "does not freeze members when pinned workflow integrity fails" do
    attempt = claim
    confirm_worktree(attempt)
    allow(WorkflowCatalog::CanonicalDefinition).to receive(:digest).and_return("sha256:#{'f' * 64}")

    expect { capture(attempt) }.to raise_error(described_class::InvariantError)
    expect(attempt.reload.input_context).to be_nil
  end

  it "rejects an invalid context that was already frozen" do
    attempt = claim
    confirm_worktree(attempt)
    attempt.update!(input_context: { "schema_version" => "1" }, input_context_digest: "sha256:#{'e' * 64}")

    expect { capture(attempt) }.to raise_error(described_class::InvariantError)
  end

  it "rejects publication until its durable intent is available" do
    expect(publication_error_code).to eq("context_unavailable")
  end
end
