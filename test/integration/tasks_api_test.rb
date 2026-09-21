require "test_helper"

class TasksApiTest < ActionDispatch::IntegrationTest
  setup do
    @headers = { "Authorization" => "Bearer test-api-token" }
    @project = create_project
    @workflow = create_workflow
    @task_type = create_task_type(name: "Feature", workflow: @workflow)
  end

  test "creates and shows a task with its workflow current step and dependencies" do
    parent = create_task(project: @project, workflow: @workflow, task_type: @task_type, title: "Parent")
    blocker = create_task(project: @project, workflow: @workflow, task_type: @task_type, title: "Blocker")

    post tasks_path, params: task_parameters.merge(parent_id: parent.id, blocker_ids: [ blocker.id ]),
      headers: @headers, as: :json

    assert_response :created
    task_id = response.parsed_body.dig("task", "id")
    assert_equal parent.id, response.parsed_body.dig("task", "parent_id")
    assert_equal [ blocker.id ], response.parsed_body.dig("task", "blocker_ids")
    assert_equal @workflow.id, response.parsed_body.dig("workflow", "id")
    assert_equal "develop", response.parsed_body.dig("step", "id")
    assert_equal "advanced", response.parsed_body.dig("step", "model_tier")
    assert_equal "Implement the task.", response.parsed_body.dig("step", "instruction")

    get task_path(task_id), headers: @headers, as: :json
    assert_response :success
    assert_equal task_id, response.parsed_body.dig("task", "id")
  end

  test "projects advanced tiers throughout a persisted legacy workflow" do
    definition = valid_workflow_definition.deep_dup
    definition["steps"].each { |step| step.delete("model_tier") }
    workflow = Workflow.new(name: "Legacy", definition_json: definition)
    workflow.save!(validate: false)
    task_type = create_task_type(name: "Legacy", workflow:)
    task = create_task(project: @project, workflow:, task_type:)

    get task_path(task), headers: @headers, as: :json

    assert_response :success
    assert_equal "advanced", response.parsed_body.dig("step", "model_tier")
    assert response.parsed_body.dig("workflow", "definition_json", "steps").all? do |step|
      step["model_tier"] == "advanced"
    end
  end

  test "updates an unclaimed definition and rolls back all changes when a blocker is invalid" do
    original_blocker = create_task(project: @project, workflow: @workflow, task_type: @task_type, title: "Original")
    replacement = create_task(project: @project, workflow: @workflow, task_type: @task_type, title: "Replacement")
    task = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    TaskDependency.create!(task:, blocker: original_blocker)

    patch task_path(task), params: {
      description_markdown: "Updated",
      parent_id: replacement.id,
      blocker_ids: [ replacement.id ]
    }, headers: @headers, as: :json
    assert_response :success
    assert_equal "Updated", task.reload.description_markdown
    assert_equal replacement, task.parent
    assert_equal [ replacement ], task.blockers

    other_project_blocker = create_task
    patch task_path(task), params: {
      description_markdown: "Must roll back",
      blocker_ids: [ other_project_blocker.id ]
    }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
    assert_equal "Updated", task.reload.description_markdown
    assert_equal [ replacement ], task.blockers.reload
  end

  test "claims reports pauses resumes completes and cancels through the API" do
    task = create_task(project: @project, workflow: @workflow, task_type: @task_type)

    post tasks_claim_next_path, params: { project_id: @project.id, owner_id: "session-1" },
      headers: @headers, as: :json
    assert_response :success
    assert_equal "active", response.parsed_body.dig("task", "status")
    assert_equal 1, response.parsed_body.dig("task", "claim_version")

    post report_attempt_task_path(task), params: {
      owner_id: "session-1", claim_version: 1, step: "develop", outcome: "question"
    }, headers: @headers, as: :json
    assert_response :success
    assert_equal "needs_human", response.parsed_body.dig("task", "status")
    assert_equal "develop", response.parsed_body.dig("task", "current_step")

    post resume_task_path(task), params: { owner_id: "session-2" }, headers: @headers, as: :json
    assert_response :success
    claim_version = response.parsed_body.dig("task", "claim_version")

    post report_attempt_task_path(task), params: {
      owner_id: "session-2", claim_version:, step: "develop", outcome: "ready"
    }, headers: @headers, as: :json
    assert_response :success
    assert_equal "check", response.parsed_body.dig("step", "id")
    claim_version = response.parsed_body.dig("task", "claim_version")

    post report_attempt_task_path(task), params: {
      owner_id: "session-2", claim_version:, step: "check", outcome: "passed"
    }, headers: @headers, as: :json
    assert_response :success
    assert_equal "completed", task.reload.status

    cancellable = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    post cancel_task_path(cancellable), headers: @headers, as: :json
    assert_response :success
    assert_equal "cancelled", cancellable.reload.status
  end

  test "returns no content when no task can be claimed" do
    post tasks_claim_next_path, params: { project_id: @project.id, owner_id: "session" },
      headers: @headers, as: :json

    assert_response :no_content
    assert_empty response.body
  end

  test "maps not found invalid transitions conflicts and bad types to stable errors" do
    get task_path(-1), headers: @headers, as: :json
    assert_response :not_found
    assert_equal "not_found", response.parsed_body["error"]

    task = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    post tasks_claim_next_path, params: { project_id: @project.id, owner_id: "session" },
      headers: @headers, as: :json
    assert_response :success

    post report_attempt_task_path(task), params: {
      owner_id: "session", claim_version: 1, step: "develop", outcome: "unknown"
    }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "invalid_transition", response.parsed_body["error"]

    post report_attempt_task_path(task), params: {
      owner_id: "stale", claim_version: 1, step: "develop", outcome: "ready"
    }, headers: @headers, as: :json
    assert_response :conflict
    assert_equal "conflict", response.parsed_body["error"]

    post resume_task_path(task), params: { owner_id: "other", takeover_confirmed: "true" },
      headers: @headers, as: :json
    assert_response :bad_request
    assert_equal "bad_request", response.parsed_body["error"]
  end

  test "returns not found when resuming or cancelling an unknown task" do
    post resume_task_path(-1), params: { owner_id: "session" }, headers: @headers, as: :json
    assert_response :not_found

    post cancel_task_path(-1), headers: @headers, as: :json
    assert_response :not_found
  end

  test "rejects definition edits after a claim" do
    task = create_task(project: @project, workflow: @workflow, task_type: @task_type)
    post tasks_claim_next_path, params: { project_id: @project.id, owner_id: "session" },
      headers: @headers, as: :json

    patch task_path(task), params: { description_markdown: "Too late" }, headers: @headers, as: :json

    assert_response :conflict
    assert_equal "Description", task.reload.description_markdown
  end

  test "requires typed required task parameters" do
    post tasks_path, params: task_parameters.merge(blocker_ids: "not-an-array"), headers: @headers, as: :json
    assert_response :bad_request
    assert_equal "bad_request", response.parsed_body["error"]

    post tasks_claim_next_path, params: { project_id: @project.id, owner_id: "" }, headers: @headers, as: :json
    assert_response :bad_request
  end

  test "requires authentication on every task route" do
    requests = [
      -> { post tasks_path, params: {}, as: :json },
      -> { get task_path(1), as: :json },
      -> { patch task_path(1), params: {}, as: :json },
      -> { post tasks_claim_next_path, params: {}, as: :json },
      -> { post resume_task_path(1), params: {}, as: :json },
      -> { post report_attempt_task_path(1), params: {}, as: :json },
      -> { post cancel_task_path(1), params: {}, as: :json }
    ]

    requests.each do |request|
      request.call
      assert_response :unauthorized
      assert_equal({ "error" => "unauthorized" }, response.parsed_body)
    end
  end

  test "does not expose PUT as an update alias" do
    put task_path(1), params: {}, headers: @headers, as: :json

    assert_response :not_found
  end

  private

  def task_parameters
    {
      project_id: @project.id,
      task_type_id: @task_type.id,
      title: "API task",
      description_markdown: "Created through the API"
    }
  end
end
