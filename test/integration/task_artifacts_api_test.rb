require "test_helper"

class TaskArtifactsApiTest < ActionDispatch::IntegrationTest
  REPOSITORY = "github.com/atilla777/kos"

  setup do
    @project = Project.create!(name: "KOS", repository: REPOSITORY)
    @task = @project.tasks.create!(workflow: workflow_for(@project), kind: "feature", title: "Artifacts", description: "Store results.")
    @task, = Task.claim_for!(project: @project, task_id: @task.id, session_id: "agent-1")
  end

  test "creates, lists, gets, updates, and deletes an artifact" do
    put artifact_path("specification"), params: write_params(content: "# Specification", lock_version: nil), as: :json
    assert_response :ok
    created = response.parsed_body.dig("data", "artifact")
    assert_equal 0, created.fetch("lock_version")

    get "/api/v1/tasks/#{@task.id}/artifacts", params: { project: REPOSITORY }
    assert_response :ok
    assert_equal [ "specification" ], response.parsed_body.dig("data", "artifacts").map { |item| item.fetch("key") }

    get artifact_path("specification"), params: { project: REPOSITORY }
    assert_response :ok
    assert_equal "# Specification", response.parsed_body.dig("data", "artifact", "content")

    put artifact_path("specification"), params: write_params(content: "# Revised", lock_version: 0), as: :json
    assert_response :ok
    assert_equal 1, response.parsed_body.dig("data", "artifact", "lock_version")

    delete artifact_path("specification"), params: write_params(lock_version: 1), as: :json
    assert_response :ok
    assert_not TaskArtifact.exists?(created.fetch("id"))
  end

  test "returns version conflicts without overwriting fresher content" do
    artifact = @task.task_artifacts.create!(key: "report", content: "Fresh")

    put artifact_path(artifact.key), params: write_params(content: "Duplicate", lock_version: nil), as: :json
    assert_version_conflict

    put artifact_path(artifact.key), params: write_params(content: "Stale", lock_version: artifact.lock_version + 1), as: :json
    assert_version_conflict
    assert_equal "Fresh", artifact.reload.content

    delete artifact_path(artifact.key), params: write_params(lock_version: artifact.lock_version + 1), as: :json
    assert_version_conflict
    assert TaskArtifact.exists?(artifact.id)

    put artifact_path("missing"), params: write_params(content: "Missing", lock_version: 0), as: :json
    assert_version_conflict
  end

  test "requires an explicit valid version expectation" do
    put artifact_path("report"), params: write_params(content: "Report").except(:lock_version), as: :json
    assert_response :bad_request

    put artifact_path("report"), params: write_params(content: "Report", lock_version: "0"), as: :json
    assert_response :bad_request

    delete artifact_path("report"), params: write_params(lock_version: nil), as: :json
    assert_response :bad_request
  end

  test "rejects stale, expired, and completed claims while keeping reads available" do
    artifact = @task.task_artifacts.create!(key: "report", content: "Stable")
    old_claim = @task.claim_id

    put artifact_path(artifact.key), params: write_params(content: "Wrong", lock_version: 0).merge(claim_id: "wrong"), as: :json
    assert_claim_error("claim_mismatch")

    @task.update_columns(claimed_at: 1.hour.ago, lease_expires_at: 1.second.ago)
    put artifact_path(artifact.key), params: write_params(content: "Late", lock_version: 0), as: :json
    assert_claim_error("lease_expired")

    @task.update_columns(status: "done", claim_id: nil, session_id: nil, claimed_at: nil, lease_expires_at: nil)
    put artifact_path(artifact.key), params: write_params(content: "After completion", lock_version: 0).merge(claim_id: old_claim), as: :json
    assert_claim_error("invalid_transition")

    get artifact_path(artifact.key), params: { project: REPOSITORY }
    assert_response :ok
    assert_equal "Stable", response.parsed_body.dig("data", "artifact", "content")
  end

  test "expiry and a new claim preserve new owner data against every old artifact write" do
    artifact = @task.task_artifacts.create!(key: "report", content: "Stable")
    old_claim = @task.claim_id
    @task.update_columns(claimed_at: 1.hour.ago, lease_expires_at: 1.second.ago)
    reclaimed, = Task.claim_for!(project: @project, task_id: @task.id, session_id: "agent-2")

    put artifact_path(artifact.key), params: write_params(
      content: "New", lock_version: 0
    ).merge(claim_id: reclaimed.claim_id), as: :json
    assert_response :ok

    put artifact_path(artifact.key), params: write_params(content: "Old", lock_version: 0).merge(claim_id: old_claim), as: :json
    assert_claim_error("claim_mismatch")

    put artifact_path("old-create"), params: write_params(
      content: "Old", lock_version: nil
    ).merge(claim_id: old_claim), as: :json
    assert_claim_error("claim_mismatch")

    delete artifact_path(artifact.key), params: write_params(
      lock_version: 1
    ).merge(claim_id: old_claim), as: :json
    assert_claim_error("claim_mismatch")

    artifact.reload
    assert_equal "New", artifact.content
    assert_equal 1, artifact.lock_version
    assert_not TaskArtifact.exists?(task_id: @task.id, key: "old-create")
    assert_equal reclaimed.claim_id, @task.reload.claim_id
  end

  test "scopes artifacts through the task project" do
    artifact = @task.task_artifacts.create!(key: "report", content: "Private")
    other = Project.create!(name: "Other", repository: "github.com/atilla777/other")

    get artifact_path(artifact.key), params: { project: other.repository }

    assert_response :not_found
  end

  private

  def artifact_path(key)
    "/api/v1/tasks/#{@task.id}/artifacts/#{key}"
  end

  def write_params(**values)
    { project: REPOSITORY, claim_id: @task.claim_id, **values }
  end

  def assert_version_conflict
    assert_response :conflict
    assert_equal "artifact_version_conflict", response.parsed_body.dig("error", "code")
  end

  def assert_claim_error(code)
    assert_response :conflict
    assert_equal code, response.parsed_body.dig("error", "code")
  end
end
