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
    assert_equal brief.step_at(1).fetch("outputs").sort, brief.step_at(1).fetch("templates").keys.sort

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

    post "/api/v1/tasks/#{brief_id}/advance", params: { project: REPOSITORY,
      claim_id: claim, expected_step: 1 }, as: :json
    assert_response :ok
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

  test "brief has a publication gate and exposes its results to execution" do
    load Rails.root.join("db/seeds.rb")
    brief = Workflow.find_by!(name: "KOS Brief v1", project_id: nil)
    execution = Workflow.find_by!(name: "KOS Execution v1", project_id: nil)
    fix = Workflow.find_by!(name: "KOS Fix v1", project_id: nil)

    assert_equal "main", brief.step_at(0).fetch("executor")
    assert_empty brief.step_at(0).fetch("outputs")
    assert_includes brief.step_at(0).fetch("instructions"), "real Git origin"
    assert_includes brief.step_at(0).fetch("instructions"), "one digit"
    assert_includes brief.step_at(1).fetch("instructions"), "kos-project-docs"
    assert_equal %w[requirements specification implementation_plan planning_report], brief.step_at(1).fetch("outputs")
    assert_equal [ "publication_report" ], brief.step_at(2).fetch("outputs")
    assert_includes brief.step_at(2).fetch("instructions"), "before retrying"
    assert_includes execution.step_at(0).fetch("inputs"), { "source" => "blockers", "key" => "publication_report" }
    assert_includes execution.step_at(0).fetch("inputs"), { "source" => "blockers", "key" => "planning_report" }
    assert_includes fix.step_at(0).fetch("instructions"), "no Brief is required"
    assert_includes execution.step_at(0).fetch("instructions"), "consecutively"
    assert_includes execution.step_at(2).fetch("instructions"), "High and medium findings must be fixed"
    assert_includes fix.step_at(3).fetch("instructions"), "high and medium findings must be fixed"
    assert_includes execution.step_at(3).fetch("instructions"), "docs/ by default"
    assert_includes fix.step_at(4).fetch("instructions"), "docs/ by default"
    assert_includes execution.step_at(4).fetch("instructions"), "Only the orchestrator may complete"
    assert_includes fix.step_at(5).fetch("instructions"), "Only the orchestrator may complete"

    post "/api/v1/tasks", params: { project: REPOSITORY, workflow_id: brief.id,
      kind: "decomposition", title: "Approve specification", description: "Agree with human." }, as: :json
    assert_response :created
    brief_id = response.parsed_body.dig("data", "task", "id")
    post "/api/v1/tasks/#{brief_id}/claim", params: { project: REPOSITORY,
      session_id: "planner", context: "route" }, as: :json
    assert_response :ok
    claim = response.parsed_body.dig("data", "task", "claim_id")

    post "/api/v1/tasks/#{brief_id}/advance", params: { project: REPOSITORY,
      claim_id: claim, expected_step: 0 }, as: :json
    assert_response :ok
    post "/api/v1/tasks/#{brief_id}/complete", params: { project: REPOSITORY, claim_id: claim }, as: :json
    assert_response :conflict
    post "/api/v1/tasks/#{brief_id}/advance", params: { project: REPOSITORY,
      claim_id: claim, expected_step: 1 }, as: :json
    assert_response :ok
    get "/api/v1/tasks/#{brief_id}/step", params: { project: REPOSITORY }
    assert_response :ok
    assert_equal [ "publication_report" ], response.parsed_body.dig("data", "step", "outputs")
    assert_includes response.parsed_body.dig("data", "step", "templates", "publication_report"), "verifiable revision"
  end

  test "each ready workflow provides a usable template for each declared output" do
    load Rails.root.join("db/seeds.rb")
    Workflow.where(project_id: nil).find_each do |workflow|
      workflow.steps.each do |step|
        assert_equal step.fetch("outputs").sort, step.fetch("templates", {}).keys.sort
        step.fetch("templates", {}).each_value do |template|
          assert_match(/\A# /, template)
          assert_includes template, "\n\n## "
        end
      end
    end
    assert_includes Workflow.find_by!(name: "KOS Fix v1").step_at(0).dig("templates", "root_cause_report"), "confirmed cause"
  end
end
