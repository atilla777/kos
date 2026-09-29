require "test_helper"

class ReadyWorkflowsTest < ActionDispatch::IntegrationTest
  REPOSITORY = "github.com/workflows/ready"

  test "seeded brief creates blocked execution work and passes on high-level documents" do
    load Rails.root.join("db/seeds.rb")
    brief = Workflow.find_by!(name: "KOS Brief v1", project_id: nil)
    execution = Workflow.find_by!(name: "KOS Execution v1", project_id: nil)

    post "/api/v1/tasks", params: { project: REPOSITORY, workflow_id: brief.id,
      kind: "decomposition", title: "Plan feature", description: "Agree a feature with the human." }, as: :json
    assert_response :created
    brief_id = response.parsed_body.dig("data", "task", "id")

    post "/api/v1/tasks/#{brief_id}/claim", params: { project: REPOSITORY,
      session_id: "planner", context: "route" }, as: :json
    assert_response :ok
    claim = response.parsed_body.dig("data", "task", "claim_id")
    assert_equal "main", response.parsed_body.dig("data", "task", "step", "executor")
    assert_equal [], brief.step_at(0).fetch("outputs")

    post "/api/v1/tasks/#{brief_id}/advance", params: { project: REPOSITORY,
      claim_id: claim, expected_step: 0 }, as: :json
    assert_response :ok
    assert_equal %w[requirements specification implementation_plan planning_report], brief.step_at(1).fetch("outputs")

    put "/api/v1/tasks/#{brief_id}/artifacts/specification", params: {
      project: REPOSITORY, claim_id: claim, content: "# Approved high-level brief", lock_version: nil
    }, as: :json
    assert_response :ok

    post "/api/v1/tasks", params: { project: REPOSITORY, workflow_id: execution.id,
      kind: "feature", title: "Build feature", description: "Refine and implement.",
      blocked_by_ids: [ brief_id ] }, as: :json
    assert_response :created
    execution_id = response.parsed_body.dig("data", "task", "id")
    get "/api/v1/tasks/ready", params: { project: REPOSITORY }
    assert_empty response.parsed_body.dig("data", "tasks")

    post "/api/v1/tasks/#{brief_id}/complete", params: { project: REPOSITORY, claim_id: claim }, as: :json
    assert_response :ok
    get "/api/v1/tasks/#{execution_id}/step", params: { project: REPOSITORY }
    assert_response :ok
    input = response.parsed_body.dig("data", "step", "inputs").find do |candidate|
      candidate.dig("selector", "key") == "specification"
    end
    assert_equal "# Approved high-level brief", input.dig("artifacts", 0, "content")
    assert_equal brief_id, input.dig("artifacts", 0, "source", "task_id")
  end

  test "seeded fix begins with diagnosis without a brief" do
    load Rails.root.join("db/seeds.rb")
    fix = Workflow.find_by!(name: "KOS Fix v1", project_id: nil)
    post "/api/v1/tasks", params: { project: REPOSITORY, workflow_id: fix.id,
      kind: "fix", title: "Broken feature", description: "Reproduce these symptoms." }, as: :json
    assert_response :created
    task_id = response.parsed_body.dig("data", "task", "id")

    get "/api/v1/tasks/#{task_id}/step", params: { project: REPOSITORY }
    assert_response :ok
    assert_equal "advanced", response.parsed_body.dig("data", "step", "model_tier")
    assert_equal [ "root_cause_report" ], response.parsed_body.dig("data", "step", "outputs")
    assert_equal "standard", fix.step_at(5).fetch("model_tier")
    assert_equal [ "publication_report" ], fix.step_at(5).fetch("outputs")
  end
end
