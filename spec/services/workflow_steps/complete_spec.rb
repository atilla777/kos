require "rails_helper"
require "tmpdir"
require Rails.root.join("spec/support/git_repository_helpers")
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe WorkflowSteps::Complete, :aggregate_failures do
  include GitRepositoryHelpers
  include WorkflowCatalogHelpers

  let(:git_path) { Dir.mktmpdir("kos-step-complete") }
  let(:digest) { "sha256:#{'a' * 64}" }
  let(:repository) do
    Repository.create!(git_common_dir: File.join(git_path, ".git"), task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:task) do
    type = quick_fix_task_type
    version = publish_workflow
    Task.create!(repository:, sequence: 1, title: "Complete workflow step", task_type: type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end

  after { FileUtils.remove_entry(git_path) if File.exist?(git_path) }

  def claim
    WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "orchestrator-1",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: "claim-key-#{SecureRandom.hex(4)}", now: Time.utc(2026, 9, 11, 12))
  end

  def freeze_context(attempt)
    attempt.update!(input_context: { "schema_version" => "1" }, input_context_digest: digest)
  end

  def artifact(type, state, metadata)
    JSON.parse(JSON.generate({ "schema_version" => "1", "type" => type, "state" => state,
      "producer" => "workflow-step", "metadata" => metadata }))
  end

  def manifest(attempt, artifacts)
    { "schema_version" => "1", "attempt_id" => attempt.id, "input_context_digest" => digest,
      "outcome" => "succeeded", "artifacts" => artifacts }
  end

  def complete(attempt, to_status, artifacts, **overrides)
    described_class.call(repository:, task_number: task.number, to_status:, attempt_id: attempt.id,
      fencing_token: overrides.fetch(:fencing_token, attempt.fencing_token),
      expected_lock_version: overrides.fetch(:expected_lock_version, task.reload.lock_version),
      manifest: manifest(attempt, artifacts), now: Time.utc(2026, 9, 11, 12, 1))
  end

  def commit_evidence
    content = "Implementation plan\n"
    sha = initialize_git_repository(git_path, task_number: task.number,
      files: { "tasks/#{task.number}/implementation-plan.md" => content })
    document = artifact("document", "produced", { "kind" => "document",
      "path" => "tasks/#{task.number}/implementation-plan.md", "commit_sha" => sha,
      "content_digest" => "sha256:#{Digest::SHA256.hexdigest(content)}" })
    candidate = artifact("candidate", "produced", { "kind" => "candidate", "candidate_sha" => sha,
      "task_trailer" => task.number })
    [ sha, document, candidate ]
  end

  def advance_to_development
    _sha, document, = commit_evidence
    attempt = claim
    freeze_context(attempt)
    complete(attempt, "development", [ document ])
  end

  def advance_to_review
    advance_to_development
    sha = git(git_path, "rev-parse", "HEAD").strip
    attempt = claim
    freeze_context(attempt)
    candidate = artifact("candidate", "produced", { "kind" => "candidate", "candidate_sha" => sha,
      "task_trailer" => task.number })
    test = artifact("test", "passed", { "kind" => "test", "candidate_sha" => sha,
      "command" => "bundle exec rspec", "exit_code" => 0, "log_digest" => digest })
    complete(attempt, "review", [ candidate, test ])
    sha
  end

  def planning_summary
    _sha, document, = commit_evidence
    attempt = claim
    freeze_context(attempt)
    result = complete(attempt, "development", [ document ])
    [ result.task.workflow_state.identifier, result.task.active_attempt_id, result.artifacts.map(&:artifact_type),
      attempt.reload.state, attempt.lease_expires_at, attempt.completed_transition.to_state.identifier,
      TaskArtifact.count ]
  end

  def development_artifact_count
    advance_to_development
    sha = git(git_path, "rev-parse", "HEAD").strip
    attempt = claim
    freeze_context(attempt)
    candidate = artifact("candidate", "produced", { "kind" => "candidate", "candidate_sha" => sha,
      "task_trailer" => task.number })
    tests = 2.times.map do |index|
      artifact("test", "passed", { "kind" => "test", "candidate_sha" => sha,
        "command" => "check #{index}", "exit_code" => 0, "log_digest" => digest })
    end
    complete(attempt, "review", [ candidate, *tests ]).artifacts.size
  end

  def review_target(verdict, target)
    sha = advance_to_review
    attempt = claim
    freeze_context(attempt)
    review = artifact("review", verdict, { "kind" => "review", "candidate_sha" => sha,
      "verdict" => verdict, "review_attempt_id" => attempt.id })
    complete(attempt, target, [ review ]).task.workflow_state.identifier
  end

  def complete_review(verdict, target)
    review_target(verdict, target)
  end

  def old_candidate_review_summary
    old_sha = advance_to_review
    review_attempt = claim
    freeze_context(review_attempt)
    review = artifact("review", "changes_requested", { "kind" => "review", "candidate_sha" => old_sha,
      "verdict" => "changes_requested", "review_attempt_id" => review_attempt.id })
    complete(review_attempt, "development", [ review ])
    new_sha = create_next_candidate
    development_attempt = claim
    freeze_context(development_attempt)
    candidate = artifact("candidate", "produced", { "kind" => "candidate", "candidate_sha" => new_sha,
      "task_trailer" => task.number })
    test = artifact("test", "passed", { "kind" => "test", "candidate_sha" => new_sha,
      "command" => "check", "exit_code" => 0, "log_digest" => digest })
    complete(development_attempt, "review", [ candidate, test ])
    current_review = claim
    freeze_context(current_review)
    stale = artifact("review", "approved", { "kind" => "review", "candidate_sha" => old_sha,
      "verdict" => "approved", "review_attempt_id" => current_review.id })
    [ operation_error_code { complete(current_review, "publication", [ stale ]) },
      current_review.reload.state, task.reload.workflow_state.identifier ]
  end

  def create_next_candidate
    File.binwrite(File.join(git_path, "change.txt"), "next candidate\n")
    git(git_path, "add", "change.txt")
    git(git_path, "commit", "-m", "Next candidate", "-m", "KOS-Task: #{task.number}")
    git(git_path, "rev-parse", "HEAD").strip
  end

  def inconsistent_candidate_summary
    advance_to_development
    attempt = claim
    freeze_context(attempt)
    sha = git(git_path, "rev-parse", "HEAD").strip
    candidate = artifact("candidate", "produced", { "kind" => "candidate", "candidate_sha" => sha,
      "task_trailer" => task.number })
    test = artifact("test", "passed", { "kind" => "test", "candidate_sha" => "b" * 40,
      "command" => "check", "exit_code" => 0, "log_digest" => digest })
    before = TaskArtifact.count
    code = operation_error_code { complete(attempt, "review", [ candidate, test ]) }
    [ code, TaskArtifact.count, before, attempt.reload.state, task.reload.workflow_state.identifier ]
  end

  def invalid_git_summary
    _sha, document, = commit_evidence
    document.fetch("metadata")["content_digest"] = "sha256:#{'b' * 64}"
    attempt = claim
    freeze_context(attempt)
    code = operation_error_code { complete(attempt, "development", [ document ]) }
    [ code, TaskArtifact.count, attempt.reload.state, task.reload.workflow_state.identifier ]
  end

  def non_success_manifest_code
    attempt = claim
    freeze_context(attempt)
    failed = manifest(attempt, []).merge("outcome" => "failed")
    operation_error_code do
      described_class.call(repository:, task_number: task.number, to_status: "development", attempt_id: attempt.id,
        fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, manifest: failed)
    end
  end

  def wrong_document_path_code
    _sha, document, = commit_evidence
    document.fetch("metadata")["path"] = "tasks/KOS-999999/implementation-plan.md"
    attempt = claim
    freeze_context(attempt)
    operation_error_code { complete(attempt, "development", [ document ]) }
  end

  def contradictory_review_summary
    sha = advance_to_review
    attempt = claim
    freeze_context(attempt)
    reviews = %w[approved changes_requested].map do |verdict|
      artifact("review", verdict, { "kind" => "review", "candidate_sha" => sha,
        "verdict" => verdict, "review_attempt_id" => attempt.id })
    end
    before = TaskArtifact.count
    [ operation_error_code { complete(attempt, "publication", reviews) }, TaskArtifact.count, before,
      attempt.reload.state, task.reload.workflow_state.identifier ]
  end

  def replacement_candidate_code
    advance_to_development
    git(git_path, "commit", "--allow-empty", "-m", "Missing trailer")
    untrusted = git(git_path, "rev-parse", "HEAD").strip
    git(git_path, "commit", "--allow-empty", "-m", "Replacement", "-m", "KOS-Task: #{task.number}")
    trusted = git(git_path, "rev-parse", "HEAD").strip
    git(git_path, "replace", untrusted, trusted)
    attempt = claim
    freeze_context(attempt)
    candidate = artifact("candidate", "produced", { "kind" => "candidate", "candidate_sha" => untrusted,
      "task_trailer" => task.number })
    operation_error_code { complete(attempt, "review", [ candidate ]) }
  end

  def decision_transition_summary
    definition = workflow_definition(version: "2.0.0")
    definition.fetch("statuses").first["required_artifacts"] = []
    definition.fetch("transitions").first["conditions"] = [
      { "type" => "decision", "decision" => "delivery", "value" => "direct" }
    ]
    version = publish_workflow(definition)
    decision_task = Task.create!(repository:, sequence: 2, title: "Choose branch", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
    attempt = WorkflowAttempts::Claim.call(repository:, task_number: decision_task.number, owner_id: "orchestrator-1",
      lease_seconds: 300, expected_lock_version: 0, idempotency_key: "decision-claim")
    attempt.update!(input_context: { "schema_version" => "1" }, input_context_digest: digest)
    empty_manifest = manifest(attempt, [])
    described_class.call(repository:, task_number: decision_task.number, to_status: "development",
      attempt_id: attempt.id, fencing_token: 1, expected_lock_version: 1, manifest: empty_manifest)
    condition = attempt.reload.completed_transition.workflow_transition_conditions.first
    [ condition.condition_type, condition.decision, condition.value ]
  end

  def partial_registration_summary
    advance_to_development
    sha = git(git_path, "rev-parse", "HEAD").strip
    attempt = claim
    freeze_context(attempt)
    candidate = artifact("candidate", "produced", { "kind" => "candidate", "candidate_sha" => sha,
      "task_trailer" => task.number })
    tests = %w[valid invalid].map do |producer|
      artifact("test", "passed", { "kind" => "test", "candidate_sha" => sha, "command" => producer,
        "exit_code" => 0, "log_digest" => digest }).merge("producer" => producer)
    end
    tests.last["producer"] = "INVALID"
    before = TaskArtifact.count
    [ operation_error_code { complete(attempt, "review", [ candidate, *tests ]) },
      TaskArtifact.count, before, attempt.reload.state, task.reload.workflow_state.identifier ]
  end

  def ownership_error_codes
    _sha, document, = commit_evidence
    attempt = claim
    freeze_context(attempt)
    stale_lock = operation_error_code { complete(attempt, "development", [ document ], expected_lock_version: 0) }
    stale_fence = operation_error_code { complete(attempt, "development", [ document ], fencing_token: 2) }
    bad_manifest = manifest(attempt, [ document ]).merge("input_context_digest" => "sha256:#{'b' * 64}")
    bad_context = operation_error_code do
      described_class.call(repository:, task_number: task.number, to_status: "development", attempt_id: attempt.id,
        fencing_token: 1, expected_lock_version: 1, manifest: bad_manifest)
    end
    expired = operation_error_code do
      described_class.call(repository:, task_number: task.number, to_status: "development", attempt_id: attempt.id,
        fencing_token: 1, expected_lock_version: 1, manifest: manifest(attempt, [ document ]),
        now: Time.utc(2026, 9, 11, 12, 5))
    end
    [ stale_lock, stale_fence, bad_context, expired ]
  end

  def null_path_code
    _sha, document, = commit_evidence
    document.fetch("metadata")["path"] = "tasks/#{task.number}/bad\0path"
    attempt = claim
    freeze_context(attempt)
    operation_error_code { complete(attempt, "development", [ document ]) }
  end

  def generic_terminal_status
    type = quick_fix_task_type
    version = WorkflowVersion.create!(task_type: type, workflow_id: "quick-fix", version: "9.0.0",
      content_digest: digest)
    source = WorkflowState.create!(workflow_version: version, identifier: "coordinating", initial: true,
      execution_mode: "subagent", instruction: "Coordinate.", worktree_policy: "none",
      repository_changes_policy: "forbidden")
    terminal = WorkflowState.create!(workflow_version: version, identifier: "completed", terminal: true)
    transition = WorkflowTransition.create!(workflow_version: version, from_state: source, to_state: terminal)
    WorkflowTransitionCondition.create!(workflow_transition: transition, position: 0, condition_type: "always")
    version.update!(published_at: Time.current)
    generic_task = Task.create!(repository:, sequence: 3, title: "Coordinate", task_type: type,
      workflow_version: version, workflow_state: source)
    attempt = WorkflowAttempts::Claim.call(repository:, task_number: generic_task.number, owner_id: "orchestrator-1",
      lease_seconds: 300, expected_lock_version: 0, idempotency_key: "terminal-claim")
    attempt.update!(input_context: { "schema_version" => "1" }, input_context_digest: digest)
    result = described_class.call(repository:, task_number: generic_task.number, to_status: "completed",
      attempt_id: attempt.id, fencing_token: 1, expected_lock_version: 1, manifest: manifest(attempt, []))
    [ result.task.status, attempt.reload.completed_transition_id ]
  end

  def publication_status_without_artifacts_code
    type = quick_fix_task_type
    version = WorkflowVersion.create!(task_type: type, workflow_id: "quick-fix", version: "8.0.0",
      content_digest: digest)
    source = WorkflowState.create!(workflow_version: version, identifier: "publication", initial: true,
      execution_mode: "subagent", instruction: "Publish.", worktree_policy: "none",
      repository_changes_policy: "forbidden")
    terminal = WorkflowState.create!(workflow_version: version, identifier: "completed", terminal: true)
    transition = WorkflowTransition.create!(workflow_version: version, from_state: source, to_state: terminal)
    WorkflowTransitionCondition.create!(workflow_transition: transition, position: 0, condition_type: "always")
    version.update!(published_at: Time.current)
    publication_task = Task.create!(repository:, sequence: 4, title: "Publish", task_type: type,
      workflow_version: version, workflow_state: source)
    attempt = WorkflowAttempts::Claim.call(repository:, task_number: publication_task.number,
      owner_id: "orchestrator-1", lease_seconds: 300, expected_lock_version: 0,
      idempotency_key: "publication-claim")
    attempt.update!(input_context: { "schema_version" => "1" }, input_context_digest: digest)
    operation_error_code do
      described_class.call(repository:, task_number: publication_task.number, to_status: "completed",
        attempt_id: attempt.id, fencing_token: 1, expected_lock_version: 1, manifest: manifest(attempt, []))
    end
  end

  def invalid_transition_codes
    _sha, document, = commit_evidence
    attempt = claim
    freeze_context(attempt)
    undeclared = operation_error_code { complete(attempt, "review", [ document ]) }
    terminal = terminal_completion_code(attempt)
    [ undeclared, terminal ]
  end

  def terminal_completion_code(attempt)
    task.update!(active_attempt: nil)
    failed_manifest = manifest(attempt, []).merge("outcome" => "failed")
    attempt.update!(state: "failed", heartbeat_at: Time.utc(2026, 9, 11, 12, 1), lease_expires_at: nil,
      completed_at: Time.utc(2026, 9, 11, 12, 1), result_manifest: failed_manifest)
    task.update!(workflow_state: task.workflow_version.workflow_states.find_by!(identifier: "publication"))
    publication_attempt = claim
    freeze_context(publication_attempt)
    publication = artifact("publication", "published", { "kind" => "publication",
      "publication_id" => SecureRandom.uuid, "candidate_sha" => "a" * 40, "remote" => "origin",
      "base_ref" => "refs/heads/main", "observed_remote_tip" => "a" * 40, "reachable" => true,
      "observed_at" => "2026-09-11T12:00:00Z" })
    operation_error_code { complete(publication_attempt, "completed", [ publication ]) }
  end

  def operation_error_code
    yield
  rescue OperationError => error
    error.code
  end

  it "atomically succeeds planning, registers its document, and advances the task" do
    expect(planning_summary)
      .to eq([ "development", nil, [ "document" ], "succeeded", nil, "development", 1 ])
  end

  it "registers one candidate and multiple tests for one generation" do
    expect(development_artifact_count).to eq(3)
  end

  { "changes_requested" => "development", "approved" => "publication" }.each do |verdict, target|
    it "routes a #{verdict} review from a distinct attempt" do
      expect(complete_review(verdict, target)).to eq(target)
    end
  end

  it "rejects review evidence for an older candidate generation" do
    expect(old_candidate_review_summary).to eq([ "invalid_artifact", "started", "review" ])
  end

  it "rolls back when required artifacts are absent or have inconsistent candidates" do
    summary = inconsistent_candidate_summary
    expect(summary).to eq([ "invalid_artifact", summary.fetch(2), summary.fetch(2), "started", "development" ])
  end

  it "rejects invalid Git evidence without changing workflow state" do
    expect(invalid_git_summary).to eq([ "invalid_artifact", 0, "started", "implementation-planning" ])
  end

  it "requires a succeeded manifest at the application boundary" do
    expect(non_success_manifest_code).to eq("invalid_transition")
  end

  it "requires document evidence to belong to the owning task path" do
    expect(wrong_document_path_code).to eq("invalid_artifact")
  end

  it "applies exact-one cardinality before selecting a review state" do
    summary = contradictory_review_summary
    expect(summary).to eq([ "invalid_artifact", summary.fetch(2), summary.fetch(2), "started", "review" ])
  end

  it "ignores Git replacement refs when validating candidate trailers" do
    expect(replacement_candidate_code).to eq("invalid_artifact")
  end

  it "durably retains the selected decision transition" do
    expect(decision_transition_summary).to eq([ "decision", "delivery", "direct" ])
  end

  it "rolls back artifacts already inserted when a later registration fails" do
    summary = partial_registration_summary
    expect(summary).to eq([ "invalid_artifact", summary.fetch(2), summary.fetch(2), "started", "development" ])
  end

  it "preserves stable lock, fencing, context, and lease failures" do
    expect(ownership_error_codes)
      .to eq([ "stale_lock_version", "fencing_token_stale", "context_unavailable", "lease_expired" ])
  end

  it "rejects null bytes before invoking Git" do
    expect(null_path_code).to eq("invalid_artifact")
  end

  it "allows a generic non-publication terminal transition" do
    status, transition_id = generic_terminal_status
    expect([ status, transition_id.nil? ]).to eq([ "completed", false ])
  end

  it "reserves the publication status for specialized completion" do
    expect(publication_status_without_artifacts_code).to eq("invalid_transition")
  end

  it "disables lazy fetch for every Git evidence lookup" do
    allow(Open3).to receive(:capture3).and_call_original
    planning_summary
    expect(Open3).to have_received(:capture3)
      .with(hash_including("GIT_NO_LAZY_FETCH" => "1"), any_args).at_least(:once)
  end

  it "rejects an undeclared transition and generic completion into the terminal state" do
    expect(invalid_transition_codes).to eq([ "invalid_transition", "invalid_transition" ])
  end
end
