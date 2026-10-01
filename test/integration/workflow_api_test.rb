require "test_helper"

class WorkflowApiTest < ActionDispatch::IntegrationTest
  REPOSITORY = "github.com/workflow/example"

  test "routes a claimed task without loading documents and provides a step packet" do
    workflow = create_workflow
    post "/api/v1/tasks", params: {
      project: REPOSITORY, workflow_id: workflow.id, kind: "feature", title: "Implement",
      description: "Deliver the change."
    }, as: :json
    assert_response :created
    task_id = response.parsed_body.dig("data", "task", "id")

    post "/api/v1/tasks/#{task_id}/claim", params: {
      project: REPOSITORY, session_id: "orchestrator", context: "route"
    }, as: :json
    assert_response :ok
    route = response.parsed_body.dig("data", "task")
    assert_equal "subagent", route.dig("step", "executor")
    assert_equal "advanced", route.dig("step", "model_tier")
    assert_not route.key?("artifacts")
    assert_not route.key?("description")
    claim = route.fetch("claim_id")

    get "/api/v1/tasks/#{task_id}/step", params: { project: REPOSITORY }
    assert_response :ok
    packet = response.parsed_body.dig("data", "step")
    assert_equal "Plan the work.", packet.fetch("instructions")
    assert_equal true, packet.fetch("inputs").first.fetch("missing")
    assert_equal [ "plan" ], packet.fetch("outputs")
    assert_equal({}, packet.fetch("templates"))

    put "/api/v1/tasks/#{task_id}/artifacts/plan", params: {
      project: REPOSITORY, claim_id: claim, content: "# Plan", lock_version: nil
    }, as: :json
    assert_response :ok
    post "/api/v1/tasks/#{task_id}/complete", params: { project: REPOSITORY, claim_id: claim }, as: :json
    assert_response :conflict

    post "/api/v1/tasks/#{task_id}/advance", params: {
      project: REPOSITORY, claim_id: claim, expected_step: 0
    }, as: :json
    assert_response :ok
    assert_equal 1, response.parsed_body.dig("data", "task", "current_step")

    post "/api/v1/tasks/#{task_id}/advance", params: {
      project: REPOSITORY, claim_id: claim, expected_step: 0
    }, as: :json
    assert_response :conflict
    assert_equal "step_conflict", response.parsed_body.dig("error", "code")

    get "/api/v1/tasks/#{task_id}/step", params: { project: REPOSITORY }
    assert_response :ok
    assert_equal "# Plan", response.parsed_body.dig("data", "step", "inputs", 0, "artifacts", 0, "content")

    post "/api/v1/tasks/#{task_id}/complete", params: { project: REPOSITORY, claim_id: claim }, as: :json
    assert_response :ok
    assert_equal "done", response.parsed_body.dig("data", "task", "status")
  end

  test "requires a workflow of the same project and preserves step after reclaim" do
    workflow = create_workflow
    post "/api/v1/tasks", params: {
      project: "github.com/other/project", workflow_id: workflow.id,
      kind: "feature", title: "Wrong project", description: "Wrong."
    }, as: :json
    assert_response :unprocessable_entity
    assert_not Project.exists?(repository: "github.com/other/project")

    task = workflow.project.tasks.create!(workflow: workflow, kind: "feature", title: "Work", description: "Work.")
    claimed, = Task.claim_for!(project: workflow.project, task_id: task.id, session_id: "owner")
    claimed.advance_step!(claim_id: claimed.claim_id, expected_step: 0)
    old_claim = claimed.claim_id
    claimed.update_columns(claimed_at: 1.hour.ago, lease_expires_at: 1.second.ago)

    post "/api/v1/tasks/#{task.id}/advance", params: {
      project: REPOSITORY, claim_id: old_claim, expected_step: 1
    }, as: :json
    assert_response :conflict
    assert_equal "lease_expired", response.parsed_body.dig("error", "code")

    new_owner, = Task.claim_for!(project: workflow.project, task_id: task.id, session_id: "new-owner")
    assert_equal 1, new_owner.current_step
    assert_not_equal old_claim, new_owner.claim_id
  end

  test "global workflow is visible and usable in multiple projects without creating a project" do
    steps = [ { name: "Do", instructions: "Do the work.", executor: "main", inputs: [], outputs: [] } ]
    post "/api/v1/workflows", params: { global: true, name: "Common", steps: steps }, as: :json
    assert_response :created
    workflow = response.parsed_body.dig("data", "workflow")
    assert_nil workflow.fetch("project_id")
    assert_empty Project.all

    %w[one two].each do |name|
      repository = "github.com/example/#{name}"
      get "/api/v1/workflows", params: { project: repository }
      assert_response :ok
      assert_equal [ workflow.fetch("id") ], response.parsed_body.dig("data", "workflows").pluck("id")
      assert_empty Project.where(repository: repository)

      post "/api/v1/tasks", params: { project: repository, workflow_id: workflow.fetch("id"),
        kind: "feature", title: "Work", description: "Do work." }, as: :json
      assert_response :created
      assert_equal workflow.fetch("id"), response.parsed_body.dig("data", "task", "workflow_id")
      assert Project.exists?(repository: repository)
    end

    delete "/api/v1/workflows/#{workflow.fetch('id')}", params: { project: "github.com/example/one" }
    assert_response :conflict
    assert_equal "workflow_in_use", response.parsed_body.dig("error", "code")
  end

  test "project workflow stays private and global creation cannot specify project" do
    workflow = create_workflow
    get "/api/v1/workflows/#{workflow.id}", params: { project: "github.com/example/other" }
    assert_response :not_found

    post "/api/v1/workflows", params: { global: true, project: REPOSITORY, name: "Wrong",
      steps: [ { name: "Do", instructions: "Do it.", executor: "main", inputs: [], outputs: [] } ] }, as: :json
    assert_response :bad_request
    assert_equal 1, Workflow.count
  end

  test "SQLite rejects cross-project workflow reassignment even without model validation" do
    workflow = create_workflow
    other_project = Project.create!(repository: "github.com/example/other", name: "Other")
    task = workflow.project.tasks.create!(workflow: workflow, kind: "task", title: "Work", description: "Work.")

    assert_raises(ActiveRecord::StatementInvalid) do
      Task.connection.execute("UPDATE tasks SET project_id = #{other_project.id} WHERE id = #{task.id}")
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      Workflow.connection.execute("UPDATE workflows SET project_id = #{other_project.id} WHERE id = #{workflow.id}")
    end
    assert_equal workflow.project_id, task.reload.project_id
  end

  test "workflow definitions reject invalid routes, changes, and deletion while used" do
    post "/api/v1/workflows", params: {
      project: REPOSITORY, name: "Invalid", steps: [
        { name: "Run", instructions: "Run it.", executor: "subagent", model_tier: "unknown",
          inputs: [], outputs: [] }
      ]
    }, as: :json
    assert_response :unprocessable_entity
    assert_not Project.exists?(repository: REPOSITORY)

    workflow = create_workflow
    assert_raises(ActiveRecord::ReadOnlyError) { workflow.update!(name: "Changed") }
    task = workflow.project.tasks.create!(workflow: workflow, kind: "feature", title: "Work", description: "Work.")
    delete "/api/v1/workflows/#{workflow.id}", params: { project: REPOSITORY }, as: :json
    assert_response :conflict
    assert_equal "workflow_in_use", response.parsed_body.dig("error", "code")
    assert Task.exists?(task.id)

    post "/api/v1/tasks/#{task.id}/advance", params: {
      project: REPOSITORY, claim_id: "wrong", expected_step: 0
    }, as: :json
    assert_response :conflict
  end

  test "output templates are returned in the step packet and remain part of the assigned workflow" do
    post "/api/v1/workflows", params: { project: REPOSITORY, name: "With templates", steps: [
      { name: "Plan", instructions: "Plan it.", executor: "main", inputs: [], outputs: [ "plan" ],
        templates: { plan: "# Plan\n\n<Actual approach>" } }
    ] }, as: :json
    assert_response :created
    workflow_id = response.parsed_body.dig("data", "workflow", "id")
    assert_equal "# Plan\n\n<Actual approach>", Workflow.find(workflow_id).step_at(0).dig("templates", "plan")

    post "/api/v1/tasks", params: { project: REPOSITORY, workflow_id: workflow_id,
      kind: "feature", title: "Plan", description: "Work." }, as: :json
    task_id = response.parsed_body.dig("data", "task", "id")
    get "/api/v1/tasks/#{task_id}/step", params: { project: REPOSITORY }
    assert_response :ok
    assert_equal({ "plan" => "# Plan\n\n<Actual approach>" }, response.parsed_body.dig("data", "step", "templates"))
    assert_equal [ "plan" ], response.parsed_body.dig("data", "step", "outputs")
  end

  test "rejects blank templates and templates not tied to step outputs" do
    [ { plan: "  " }, { other: "# Wrong output" }, [ "# Plan" ] ].each do |templates|
      post "/api/v1/workflows", params: { project: REPOSITORY, name: "Invalid", steps: [
        { name: "Plan", instructions: "Plan it.", executor: "main", inputs: [], outputs: [ "plan" ],
          templates: templates }
      ] }, as: :json
      assert_response :unprocessable_entity
    end
    assert_not Project.exists?(repository: REPOSITORY)
  end

  test "invalid compact response option cannot claim a task" do
    workflow = create_workflow
    task = workflow.project.tasks.create!(workflow: workflow, kind: "feature", title: "Work", description: "Work.")

    post "/api/v1/tasks/#{task.id}/claim", params: {
      project: REPOSITORY, session_id: "agent", context: "invalid"
    }, as: :json

    assert_response :bad_request
    assert_equal "planned", task.reload.status
    assert_nil task.claim_id
  end

  test "lists workflow definitions with a cursor and deletes unused definitions" do
    first = create_workflow
    second = first.project.workflows.create!(name: "Another", steps: [
      { "name" => "Do", "instructions" => "Do it.", "executor" => "main", "inputs" => [], "outputs" => [] }
    ])

    get "/api/v1/workflows", params: { project: REPOSITORY, limit: 1 }
    assert_response :ok
    assert_equal [ first.id ], response.parsed_body.dig("data", "workflows").map { |item| item.fetch("id") }
    assert_equal first.id, response.parsed_body.dig("data", "pagination", "next_after_id")

    get "/api/v1/workflows", params: { project: REPOSITORY, limit: 1, after_id: first.id }
    assert_response :ok
    assert_equal [ second.id ], response.parsed_body.dig("data", "workflows").map { |item| item.fetch("id") }

    get "/api/v1/workflows/#{second.id}", params: { project: REPOSITORY }
    assert_response :ok
    assert_equal "Another", response.parsed_body.dig("data", "workflow", "name")

    delete "/api/v1/workflows/#{second.id}", params: { project: REPOSITORY }, as: :json
    assert_response :ok
    assert_not Workflow.exists?(second.id)
  end

  test "brief workflow list omits steps and retains scope and cursor" do
    first = create_workflow
    second = first.project.workflows.create!(name: "Second", steps: first.steps)
    get "/api/v1/workflows", params: { project: REPOSITORY, view: "brief", limit: 1 }
    assert_response :ok
    assert_equal [ { "id" => first.id, "project_id" => first.project_id, "name" => first.name } ],
      response.parsed_body.dig("data", "workflows")
    assert_equal first.id, response.parsed_body.dig("data", "pagination", "next_after_id")

    get "/api/v1/workflows", params: { project: REPOSITORY, after_id: first.id, view: "brief" }
    assert_equal [ second.id ], response.parsed_body.dig("data", "workflows").pluck("id")
    get "/api/v1/workflows", params: { project: REPOSITORY }
    assert_equal "Plan the work.", response.parsed_body.dig("data", "workflows", 0, "steps", 0, "instructions")
    get "/api/v1/workflows", params: { project: REPOSITORY, view: "other" }
    assert_response :bad_request
    assert_equal "invalid_request", response.parsed_body.dig("error", "code")
  end

  test "brief step includes every source and missing input without document contents or templates" do
    project = Project.create!(name: "Example", repository: REPOSITORY)
    workflow = project.workflows.create!(name: "Reading", steps: [
      { "name" => "Review", "instructions" => "Review sources", "executor" => "main",
        "inputs" => [ { "source" => "blockers", "key" => "report" }, { "source" => "task", "key" => "missing" } ],
        "outputs" => [ "review" ], "templates" => { "review" => "# Private template" } }
    ])
    blockers = 2.times.map do |n|
      source = project.tasks.create!(workflow: workflow, kind: "task", title: "Source #{n}", description: "Source")
      source.task_artifacts.create!(key: "report", content: "Long secret #{n}")
      source
    end
    task = project.tasks.create!(workflow: workflow, kind: "task", title: "Review", description: "Review")
    blockers.each { |source| task.task_dependencies.create!(blocking_task: source, project: project) }
    get "/api/v1/tasks/#{task.id}/step", params: { project: REPOSITORY, view: "brief" }
    assert_response :ok
    step = response.parsed_body.dig("data", "step")
    assert_equal "Review sources", step.fetch("instructions")
    assert_equal [ "review" ], step.fetch("outputs")
    assert_not step.key?("templates")
    assert_equal blockers.map(&:id), step.dig("inputs", 0, "artifacts").pluck("task_id")
    assert_equal blockers.map(&:id), step.dig("inputs", 0, "artifacts").map { |item| item.dig("source", "task_id") }
    assert_equal [ 0, 0 ], step.dig("inputs", 0, "artifacts").pluck("lock_version")
    assert_not step.dig("inputs", 0, "artifacts", 0).key?("content")
    assert_equal true, step.dig("inputs", 1, "missing")
    assert_equal [], step.dig("inputs", 1, "artifacts")
    get "/api/v1/tasks/#{task.id}/step", params: { project: REPOSITORY }
    assert_equal "Long secret 0", response.parsed_body.dig("data", "step", "inputs", 0, "artifacts", 0, "content")
    assert_equal "# Private template", response.parsed_body.dig("data", "step", "templates", "review")
  end

  private

  def create_workflow
    project = Project.create!(name: "Example", repository: REPOSITORY)
    project.workflows.create!(name: "Feature", steps: [
      { "name" => "Plan", "instructions" => "Plan the work.", "executor" => "subagent",
        "model_tier" => "advanced", "inputs" => [ { "source" => "task", "key" => "brief" } ],
        "outputs" => [ "plan" ] },
      { "name" => "Deliver", "instructions" => "Deliver the work.", "executor" => "main",
        "inputs" => [ { "source" => "task", "key" => "plan" } ], "outputs" => [] }
    ])
  end
end
