require "rails_helper"
require "rbconfig"
require "tmpdir"
require Rails.root.join("lib/kos/repository")
require Rails.root.join("spec/support/git_repository_helpers")
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe WorkflowSteps::Complete, :aggregate_failures do
  include GitRepositoryHelpers
  include WorkflowCatalogHelpers

  let(:directory) { File.realpath(Dir.mktmpdir("kos-planning-development")) }
  let(:repository_path) { File.join(directory, "repository") }
  let(:worktree_path) { File.join(directory, "worktrees", "task") }
  let(:repository) do
    Repository.create!(git_common_dir: File.join(repository_path, ".git"), task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:task) do
    workflow_version = publish_workflow
    Task.create!(repository:, sequence: 1, title: "Apply the quick fix", task_input_schema_version: "1",
      approved_brief: "Apply the confirmed quick fix.", task_type: quick_fix_task_type,
      workflow_version:, workflow_state: workflow_version.workflow_states.find_by!(initial: true))
  end

  before do
    FileUtils.mkdir_p(File.dirname(worktree_path))
    initialize_git_repository(repository_path, task_number: "KOS-000000", files: { "README.md" => "initial\n" })
  end

  after { FileUtils.remove_entry(directory) if File.exist?(directory) }

  it "reaches review with synchronized planning and candidate evidence" do
    expect(exercise_flow).to be(true)
  end

  it "rejects clean planning evidence without its successful commit effect" do
    expect(completion_without_successful_effect).to eq(%w[invalid_artifact invalid_artifact])
  end

  def exercise_flow
    planning_attempt = claim("planning")
    reservation = confirmed_worktree(planning_attempt)
    planning_context = capture(planning_attempt)
    plan_content = "# Implementation Plan\n\nApply and verify the quick fix.\n"
    FileUtils.mkdir_p(File.join(worktree_path, "tasks", task.number))
    File.binwrite(File.join(worktree_path, "tasks", task.number, "implementation-plan.md"), plan_content)
    File.binwrite(File.join(worktree_path, "README.md"), "planned\n")

    planning_commit = commit_effect(planning_attempt, planning_context,
      [ "README.md", "tasks/#{task.number}/implementation-plan.md" ], "Record implementation plan")
    expect(reservation.reload.head_sha).not_to eq(planning_commit)
    expect(completion_code(planning_attempt, "development", [ document_artifact(planning_commit, plan_content) ]))
      .to eq("invalid_artifact")
    reconcile_worktree(planning_attempt, reservation, planning_commit)
    complete(planning_attempt, "development", [ document_artifact(planning_commit, plan_content) ])

    development_attempt = claim("development")
    development_context = capture(development_attempt)
    expect(development_context.dig("worktree", "head_sha")).to eq(planning_commit)
    File.binwrite(File.join(worktree_path, "README.md"), "fixed\n")

    candidate = commit_effect(development_attempt, development_context, [ "README.md" ], "Apply quick fix")
    expect(task.reload.workflow_state.identifier).not_to eq("review")
    expect(reservation.reload.head_sha).not_to eq(candidate)
    expect(completion_code(development_attempt, "review", [ candidate_artifact(candidate), test_artifact(
      candidate, "ruby -e 'exit 0'", ""
    ) ])).to eq("invalid_artifact")
    reconcile_worktree(development_attempt, reservation, candidate)
    check_command, check_output = run_check
    complete(development_attempt, "review",
      [ candidate_artifact(candidate), test_artifact(candidate, check_command, check_output) ])

    artifacts = task.task_artifacts.reload
    expect(task.reload.workflow_state.identifier).to eq("review")
    expect(artifacts.count { _1.artifact_type == "document" }).to eq(1)
    expect(artifacts.count { _1.artifact_type == "candidate" }).to eq(1)
    expect(artifacts.count { _1.artifact_type == "test" && _1.state == "passed" }).to be >= 1
    expect(reservation.reload.head_sha).to eq(candidate)
    expect(task.active_attempt_id).to be_nil
    expect(task.workflow_attempts.order(:started_at).pluck(:state)).to eq(%w[succeeded succeeded])
    expect(task.repository_effects.pluck(:state)).to eq(%w[succeeded succeeded])
    expect(task.repository_effects.unresolved).to be_empty
    true
  end

  def claim(stage)
    WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "orchestrator",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: "claim-#{stage}-#{SecureRandom.hex(4)}")
  end

  def completion_without_successful_effect
    plan_content = "# Existing Plan\n"
    path = "tasks/#{task.number}/implementation-plan.md"
    FileUtils.mkdir_p(File.join(repository_path, "tasks", task.number))
    File.binwrite(File.join(repository_path, path), plan_content)
    git(repository_path, "add", "--", path)
    git(repository_path, "commit", "-m", "Existing plan", "-m", "KOS-Task: #{task.number}")
    commit = git(repository_path, "rev-parse", "HEAD").strip
    attempt = claim("missing-effect")
    reservation = confirmed_worktree(attempt)
    context = capture(attempt)
    reconcile_worktree(attempt, reservation, commit)
    artifact = document_artifact(commit, plan_content)
    without_effect = completion_code(attempt, "development", [ artifact ])
    reconcile_failed_effect(attempt, context)
    [ without_effect, completion_code(attempt, "development", [ artifact ]) ]
  end

  def reconcile_failed_effect(attempt, context)
    request = { "schema_version" => "1", "attempt_id" => attempt.id,
      "input_context_digest" => context.fetch("input_context_digest"),
      "effect" => { "operation" => "commit", "reservation_id" => context.dig("worktree", "reservation_id"),
        "expected_head_sha" => context.dig("worktree", "head_sha"), "expected_diff_digest" => digest("diff"),
        "expected_index_digest" => digest("index"), "paths" => [ "README.md" ], "message" => "Fail",
        "task_number" => task.number } }
    effect = RepositoryEffects::Prepare.call(repository:, task_number: task.number, effect_request: request,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version)
    failure = { "schema_version" => "1", "effect_intent_id" => effect.id,
      "request_attempt_id" => attempt.id, "owner_attempt_id" => attempt.id,
      "input_context_digest" => context.fetch("input_context_digest"),
      "effect_request_digest" => effect.request_digest,
      "result" => { "outcome" => "failed", "operation" => "commit",
        "error" => { "category" => "conflict", "code" => "commit_rejected", "message" => "Commit failed",
          "retryable" => false } } }
    RepositoryEffects::Reconcile.call(repository:, effect_id: effect.id, effect_result: failure,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version)
  end

  def confirmed_worktree(attempt)
    reservation = WorktreeReservations::Reserve.call(repository:, task_number: task.number,
      branch: "kos/task-#{task.number}", path: worktree_path, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version)
    observation = Kos::Repository::Worktree.new(adapter_request("materialize", attempt, reservation,
      git(repository_path, "rev-parse", "HEAD").strip)).call
    WorktreeReservations::Confirm.call(repository:, reservation_id: reservation.id,
      git_common_dir_digest: observation.fetch("git_common_dir_digest"), head_sha: observation.fetch("head_sha"),
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version)
  end

  def capture(attempt)
    WorkflowSteps::CaptureContext.call(repository:, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version)
  end

  def commit_effect(attempt, context, paths, message)
    effect_request = { "schema_version" => "1", "attempt_id" => attempt.id,
      "input_context_digest" => context.fetch("input_context_digest"),
      "effect" => commit_attributes(context, paths, message) }
    effect = RepositoryEffects::Prepare.call(repository:, task_number: task.number, effect_request:,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version)
    result = Kos::Repository::Commit.new(adapter_request("commit", attempt, task.worktree_reservation,
      context.dig("worktree", "head_sha")).merge(commit_attributes(context, paths, message))).call
    result = result.merge("outcome" => "succeeded", "operation" => "commit")
    effect_result = { "schema_version" => "1", "effect_intent_id" => effect.id,
      "request_attempt_id" => effect.prepared_attempt_id, "owner_attempt_id" => attempt.id,
      "input_context_digest" => context.fetch("input_context_digest"),
      "effect_request_digest" => effect.request_digest, "result" => result }
    RepositoryEffects::Reconcile.call(repository:, effect_id: effect.id, effect_result:,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version)
    result.fetch("commit_sha")
  end

  def commit_attributes(context, paths, message)
    sorted = paths.sort_by(&:b)
    head = context.dig("worktree", "head_sha")
    diff = Kos::Repository::Git.new.call("--literal-pathspecs", "-C", worktree_path, "diff", "--binary",
      "--full-index", "--no-ext-diff", "--no-textconv", head, "--", *sorted).stdout
    entries = sorted.map do |path|
      content = File.binread(File.join(worktree_path, path))
      oid = Digest::SHA1.hexdigest("blob #{content.bytesize}\0#{content}")
      "100644 #{oid}\t#{path}"
    end.join("\0") + "\0"
    { "operation" => "commit", "reservation_id" => context.dig("worktree", "reservation_id"),
      "expected_head_sha" => head,
      "expected_diff_digest" => digest(diff), "expected_index_digest" => digest(entries), "paths" => paths,
      "message" => message, "task_number" => task.number }
  end

  def adapter_request(operation, attempt, reservation, expected_head)
    { "schema_version" => "1", "operation" => operation,
      "repository" => { "id" => repository.id, "git_common_dir" => repository.git_common_dir,
        "base_ref" => repository.base_ref },
      "reservation" => { "id" => reservation.id, "repository_id" => repository.id,
        "state" => reservation.state, "path" => reservation.path, "branch" => reservation.branch,
        "fencing_token" => attempt.fencing_token }, "expected_head_sha" => expected_head }
  end

  def reconcile_worktree(attempt, reservation, head)
    observation = Kos::Repository::Worktree.new(adapter_request("observe", attempt, reservation, head)).call
    expect(observation.fetch("state")).to eq("clean")
    WorktreeReservations::Reconcile.call(repository:, reservation_id: reservation.id,
      observed_state: observation.fetch("state"), head_sha: observation.fetch("head_sha"),
      evidence_digest: observation.fetch("evidence_digest"), attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version)
  end

  def complete(attempt, status, artifacts)
    manifest = { "schema_version" => "1", "attempt_id" => attempt.id,
      "input_context_digest" => attempt.reload.input_context_digest, "outcome" => "succeeded", "artifacts" => artifacts }
    WorkflowSteps::Complete.call(repository:, task_number: task.number, to_status: status,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, manifest:)
  end

  def completion_code(attempt, status, artifacts)
    complete(attempt, status, artifacts)
  rescue OperationError => error
    error.code
  end

  def document_artifact(commit, content)
    artifact("document", "produced", { "kind" => "document",
      "path" => "tasks/#{task.number}/implementation-plan.md", "commit_sha" => commit,
      "content_digest" => digest(content) })
  end

  def candidate_artifact(candidate)
    artifact("candidate", "produced", { "kind" => "candidate", "candidate_sha" => candidate,
      "task_trailer" => task.number })
  end

  def run_check
    script = 'abort "unexpected content" unless File.binread("README.md") == "fixed\\n"'
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", script, chdir: worktree_path)
    expect(status).to be_success
    [ "ruby -e '#{script}'", stdout + stderr ]
  end

  def test_artifact(candidate, command, output)
    artifact("test", "passed", { "kind" => "test", "candidate_sha" => candidate,
      "command" => command, "exit_code" => 0, "log_digest" => digest(output) })
  end

  def artifact(type, state, metadata)
    { "schema_version" => "1", "type" => type, "state" => state,
      "producer" => "workflow-step", "metadata" => metadata }
  end

  def digest(value)
    "sha256:#{Digest::SHA256.hexdigest(value)}"
  end
end
