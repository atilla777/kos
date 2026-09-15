require "json"
require "rails_helper"
require "stringio"
require "tmpdir"
require Rails.root.join("lib/kos/repository")
require Rails.root.join("spec/support/git_repository_helpers")
require Rails.root.join("spec/support/publication_preflight_helpers")
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe PublicationPreflights::Prepare, :aggregate_failures do
  include GitRepositoryHelpers
  include PublicationPreflightHelpers
  include WorkflowCatalogHelpers

  let(:directory) { File.realpath(Dir.mktmpdir("kos-publication-context")) }
  let(:repository_path) { File.join(directory, "repository") }
  let(:remote_path) { File.join(directory, "trusted.git") }
  let(:worktree_path) { File.join(directory, "worktrees", "task") }

  before do
    FileUtils.mkdir_p(remote_path)
    git(remote_path, "init", "--bare", "--initial-branch=main")
    initialize_git_repository(repository_path, task_number: "KOS-000000", files: { "README.md" => "initial\n" })
    git(repository_path, "remote", "add", "origin", remote_url)
    git(repository_path, "push", "origin", "refs/heads/main:refs/heads/main")
  end

  after { FileUtils.remove_entry(directory) if File.exist?(directory) }

  it "freezes publication context from an authoritative durable trusted-base observation" do
    expect(publication_context_is_frozen).to be(true)
  end

  def publication_context_is_frozen
    repository = register_repository
    task = create_task(repository)
    candidate_sha = create_candidate(task)
    now = Time.current.change(usec: 0)
    advance_to_publication(task:, version:, candidate_sha:, now:)
    attempt = claim(repository, task, now)
    confirm_worktree(repository, task, attempt, candidate_sha, now)

    preflight = PublicationPreflights::Prepare.call(repository:, task_number: task.number, candidate_sha:,
      remote: repository.trusted_remote, base_ref: repository.base_ref, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now:)
    result = invoke_repository(authoritative_request(repository.reload, preflight.reload, attempt))

    reconciled = PublicationPreflights::Reconcile.call(repository:, preflight_id: preflight.id,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, observed_remote_oid: result.fetch("observed_remote_oid"),
      observed_at: result.fetch("observed_at"), evidence_digest: result.fetch("evidence_digest"))
    publication = Publications::PrepareObserved.call(repository:, preflight_id: reconciled.id,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version)
    context = WorkflowSteps::CaptureContext.call(repository:, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version)

    expect(reconciled.attributes.values_at("observed_remote_oid", "observed_at", "observation_digest"))
      .to eq([ result.fetch("observed_remote_oid"), Time.iso8601(result.fetch("observed_at")),
        result.fetch("evidence_digest") ])
    expect(context.slice("schema_version", "candidate_sha", "base_ref", "publication")).to eq(
      "schema_version" => "1", "candidate_sha" => candidate_sha, "base_ref" => repository.base_ref,
      "publication" => { "publication_id" => publication.id, "candidate_sha" => candidate_sha,
        "remote" => repository.trusted_remote, "base_ref" => repository.base_ref,
        "expected_remote_oid" => result.fetch("observed_remote_oid") }
    )
    expect(WorkflowSteps::CaptureContext.call(repository:, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version)).to eq(context)
    true
  end

  def remote_url = "file://#{remote_path}"
  def version = @version ||= publish_workflow

  def register_repository
    attributes = { "git_common_dir" => File.realpath(File.join(repository_path, ".git")), "task_prefix" => "KOS",
      "trusted_remote" => "origin", "trusted_remote_url" => remote_url, "base_ref" => "refs/heads/main" }
    RepositoryRegistration::Register.call(RepositoryRegistration::Inspect.call(attributes))
  end

  def create_task(repository)
    Task.create!(repository:, sequence: 1, title: "Publish observed candidate", task_input_schema_version: "1",
      approved_brief: "Publish the independently reviewed candidate.", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end

  def create_candidate(task)
    File.binwrite(File.join(repository_path, "README.md"), "candidate\n")
    git(repository_path, "add", "--", "README.md")
    git(repository_path, "commit", "-m", "Apply candidate", "-m", "KOS-Task: #{task.number}")
    git(repository_path, "rev-parse", "HEAD").strip
  end

  def claim(repository, task, now)
    WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "publisher", lease_seconds: 300,
      expected_lock_version: task.reload.lock_version, idempotency_key: "claim-publication", now:)
  end

  def confirm_worktree(repository, task, attempt, candidate_sha, now)
    FileUtils.mkdir_p(File.dirname(worktree_path))
    reservation = WorktreeReservations::Reserve.call(repository:, task_number: task.number,
      branch: "kos/task-#{task.number}", path: worktree_path, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now:)
    request = { "schema_version" => "1", "operation" => "materialize",
      "repository" => { "id" => repository.id, "git_common_dir" => repository.git_common_dir,
        "base_ref" => repository.base_ref },
      "reservation" => { "id" => reservation.id, "repository_id" => repository.id, "state" => reservation.state,
        "path" => reservation.path, "branch" => reservation.branch, "fencing_token" => attempt.fencing_token },
      "expected_head_sha" => candidate_sha }
    observation = Kos::Repository::Worktree.new(request).call
    WorktreeReservations::Confirm.call(repository:, reservation_id: reservation.id,
      git_common_dir_digest: observation.fetch("git_common_dir_digest"), head_sha: observation.fetch("head_sha"),
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now:)
  end

  def authoritative_request(repository, preflight, attempt)
    request = { "schema_version" => "2", "operation" => "publication_preflight",
      "repository" => repository.attributes.slice("id", "git_common_dir", "trusted_remote", "trusted_remote_url",
        "base_ref"),
      "publication_preflight" => preflight.attributes.slice("id", "repository_id", "task_id", "candidate_sha",
        "current_owner_attempt_id", "remote", "base_ref", "state").merge(
          "fencing_token" => attempt.fencing_token) }
    expect(Kos::Repository::Schema.new.valid?("request", request)).to be(true)
    request
  end

  def invoke_repository(request)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Kos::Repository::Application.new(
      [ "publication_preflight", "--input", "-", "--json" ],
      input: StringIO.new(JSON.generate(request)), stdout:, stderr:
    ).run
    expect([ status, stderr.string ]).to eq([ 0, "" ])
    JSON.parse(stdout.string)
  end
end
