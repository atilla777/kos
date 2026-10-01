require "test_helper"

class BriefPlansApiTest < ActionDispatch::IntegrationTest
  REPOSITORY = "github.com/example/brief-plans"

  setup do
    @project = Project.create!(name: "Plans", repository: REPOSITORY)
    @brief_workflow = @project.workflows.create!(name: "KOS Brief v3", steps: [
      { name: "Plan", instructions: "Plan tasks.", executor: "main", inputs: [], outputs: [] },
      { name: "Publish", instructions: "Publish.", executor: "main", inputs: [], outputs: [] }
    ])
    @execution = workflow_for(@project)
    @brief = @project.tasks.create!(workflow: @brief_workflow, kind: "decomposition", title: "Brief", description: "Plan.")
    @claim, = Task.claim_for!(project: @project, task_id: @brief.id, session_id: "agent")
    @entries = [
      { name: "first", kind: "feature", title: "First", description: "Build first.", workflow_id: @execution.id },
      { name: "second", kind: "feature", title: "Second", description: "Build second.", workflow_id: @execution.id, blocked_by: [ "first" ] }
    ]
  end

  test "creates one atomic plan, restores lost response and never exposes a claim" do
    create_plan
    assert_response :created
    result = response.parsed_body.dig("data", "plan")
    assert_equal %w[first second], result.fetch("tasks").keys
    first = result.dig("tasks", "first", "id")
    second = result.dig("tasks", "second", "id")
    assert_equal [ @brief.id ], Task.find(first).blocking_task_ids
    assert_equal [ @brief.id, first ].sort, Task.find(second).blocking_task_ids.sort
    assert_equal false, Task.find(first).availability_at.fetch(:available)
    assert_not_includes response.body, @claim.claim_id

    create_plan
    assert_response :ok
    assert_equal result, response.parsed_body.dig("data", "plan")
    assert_equal 3, Task.count

    @brief.update_columns(claimed_at: 1.hour.ago, lease_expires_at: 1.second.ago)
    get "/api/v1/tasks/#{@brief.id}/brief-plan/run-1", params: { project: REPOSITORY }
    assert_response :ok
    assert_equal result, response.parsed_body.dig("data", "plan")
    create_plan
    assert_response :conflict
    assert_equal "lease_expired", response.parsed_body.dig("error", "code")

    reclaimed, = Task.claim_for!(project: @project, task_id: @brief.id, session_id: "new-owner")
    create_plan(claim_id: reclaimed.claim_id)
    assert_response :ok
    assert_equal result, response.parsed_body.dig("data", "plan")
  end

  test "different content or another key cannot replace a plan" do
    create_plan
    create_plan(key: "run-1", tasks: [ @entries.first ])
    assert_response :conflict
    assert_equal "plan_conflict", response.parsed_body.dig("error", "code")
    create_plan(key: "run-2")
    assert_response :conflict
    assert_equal "plan_conflict", response.parsed_body.dig("error", "code")
    assert_equal 3, Task.count
  end

  test "a planned child cannot drop its Brief blocker before completion" do
    create_plan
    child_id = response.parsed_body.dig("data", "plan", "tasks", "first", "id")

    patch "/api/v1/tasks/#{child_id}", params: { project: REPOSITORY, blocked_by_ids: [] }, as: :json
    assert_response :unprocessable_entity
    assert_equal [ @brief.id ], Task.find(child_id).blocking_task_ids

    assert_raises(ActiveRecord::StatementInvalid) do
      TaskDependency.where(task_id: child_id, blocking_task_id: @brief.id).delete_all
    end
    delete "/api/v1/tasks/#{child_id}", params: { project: REPOSITORY }, as: :json
    assert_response :conflict
    assert Task.exists?(child_id)
  end

  test "invalid graph, workflow, group and child task roll back every record" do
    other = Project.create!(name: "Other", repository: "github.com/example/other")
    group = other.task_groups.create!(kind: "epic", title: "Other", description: "Other.")
    [
      [ @entries.first.merge(workflow_id: 999999) ],
      [ @entries.first.merge(task_group_id: group.id) ],
      [ @entries.first.merge(title: " ") ],
      [ @entries.first.merge(blocked_by: [ "missing" ]) ],
      [ @entries.first.merge(blocked_by: [ "first" ]) ],
      [ @entries.first.merge(blocked_by: [ "second" ]), @entries.last.merge(blocked_by: [ "first" ]) ]
    ].each do |entries|
      create_plan(tasks: entries)
      assert_includes [ 400, 422 ], response.status
      assert_equal 1, @project.tasks.count
      assert_equal 0, BriefPlan.count
    end
  end

  test "stale step, foreign claim and wrong project cannot create a plan" do
    create_plan(claim_id: "other")
    assert_response :conflict
    assert_equal "claim_mismatch", response.parsed_body.dig("error", "code")
    create_plan(expected_step: 1)
    assert_response :conflict
    assert_equal "step_conflict", response.parsed_body.dig("error", "code")
    create_plan(project: "github.com/example/other")
    assert_response :not_found
    assert_equal 1, Task.count
  end

  test "an existing v2 brief still creates its own plan" do
    old_workflow = @project.workflows.create!(name: "KOS Brief v2", steps: @brief_workflow.steps)
    old_brief = @project.tasks.create!(workflow: old_workflow, kind: "decomposition", title: "Older Brief", description: "Continue old work.")
    old_claim, = Task.claim_for!(project: @project, task_id: old_brief.id, session_id: "older-agent")

    post "/api/v1/tasks/#{old_brief.id}/brief-plan", params: {
      project: REPOSITORY, claim_id: old_claim.claim_id, expected_step: 0, key: "old-run", tasks: [ @entries.first ]
    }, as: :json

    assert_response :created
    assert_equal [ old_brief.id ], Task.find(response.parsed_body.dig("data", "plan", "tasks", "first", "id")).blocking_task_ids
  end

  private

  def create_plan(key: "run-1", tasks: @entries, expected_step: 0, claim_id: @claim.claim_id, project: REPOSITORY)
    post "/api/v1/tasks/#{@brief.id}/brief-plan", params: {
      project: project, claim_id: claim_id, expected_step: expected_step, key: key, tasks: tasks
    }, as: :json
  end
end
