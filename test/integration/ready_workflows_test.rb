require "test_helper"

class ReadyWorkflowsTest < ActionDispatch::IntegrationTest
  REPOSITORY = "github.com/workflows/ready"

  test "seeded brief creates blocked execution work and passes on high-level documents" do
    load Rails.root.join("db/seeds.rb")
    brief = Workflow.find_by!(name: "KOS Brief v4", project_id: nil)
    execution = Workflow.find_by!(name: "KOS Execution v4", project_id: nil)

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

    post "/api/v1/tasks/#{brief_id}/brief-plan", params: { project: REPOSITORY,
      claim_id: claim, expected_step: 1, key: "approved-set", tasks: [ {
        name: "feature", kind: "feature", title: "Build feature", description: "Refine and implement.",
        workflow_id: execution.id
      } ] }, as: :json
    assert_response :created
    execution_id = response.parsed_body.dig("data", "plan", "tasks", "feature", "id")
    assert_equal [ brief_id ], Task.find(execution_id).blocking_task_ids
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
    fix = Workflow.find_by!(name: "KOS Fix v4", project_id: nil)
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
    brief = Workflow.find_by!(name: "KOS Brief v4", project_id: nil)
    execution = Workflow.find_by!(name: "KOS Execution v4", project_id: nil)
    fix = Workflow.find_by!(name: "KOS Fix v4", project_id: nil)

    assert_equal "main", brief.step_at(0).fetch("executor")
    assert_empty brief.step_at(0).fetch("outputs")
    assert_includes brief.step_at(0).fetch("instructions"), "real Git origin"
    assert_includes brief.step_at(0).fetch("instructions"), "one question at a time"
    assert_includes brief.step_at(0).fetch("instructions"), "only sequentially"
    assert_includes brief.step_at(0).fetch("instructions"), "reasoned recommendation in parentheses"
    assert_includes brief.step_at(0).fetch("instructions"), "plain words"
    assert_includes brief.step_at(1).fetch("instructions"), "kos-project-docs"
    assert_equal %w[requirements specification implementation_plan planning_report], brief.step_at(1).fetch("outputs")
    assert_equal [ "publication_report" ], brief.step_at(2).fetch("outputs")
    assert_includes brief.step_at(2).fetch("instructions"), "before retrying"
    assert_includes execution.step_at(0).fetch("inputs"), { "source" => "blockers", "key" => "publication_report" }
    assert_includes execution.step_at(0).fetch("inputs"), { "source" => "blockers", "key" => "planning_report" }
    assert_includes fix.step_at(0).fetch("instructions"), "no Brief is required"
    assert_includes execution.step_at(0).fetch("instructions"), "Q-01 onward"
    assert_includes execution.step_at(0).fetch("instructions"), "one at a time"
    assert_includes execution.step_at(0).fetch("instructions"), "reasoned recommendation in parentheses"
    assert_includes fix.step_at(0).fetch("instructions"), "one at a time"
    assert_includes fix.step_at(1).fetch("instructions"), "reasoned recommendation in parentheses"
    assert_includes execution.step_at(2).fetch("instructions"), "High and medium findings must be corrected"
    assert_includes fix.step_at(3).fetch("instructions"), "High and medium require correction"
    assert_includes brief.step_at(1).fetch("instructions"), "OKF v0.2"
    assert_includes brief.step_at(1).fetch("instructions"), "domain-organized"
    assert_includes execution.step_at(0).fetch("instructions"), "human agreement"
    assert_includes fix.step_at(1).fetch("instructions"), "human agreement"
    [ execution.step_at(0), fix.step_at(1) ].each do |step|
      assert_includes step.fetch("instructions"), "orchestrator, who obtains separate explicit human agreement"
      assert_includes step.fetch("instructions"), "saving it does not approve or resolve the question"
      assert_includes step.fetch("instructions"), "Then update the affected concept before implementation"
    end
    [ execution.step_at(1), fix.step_at(2) ].each do |step|
      assert_includes step.fetch("instructions"), "rerun affected checks"
      assert_includes step.fetch("instructions"), "project rules require it"
    end
    assert_includes brief.step_at(1).fetch("instructions"), "Execution v4 tasks"
    [ execution.step_at(3), fix.step_at(4) ].each do |step|
      assert_includes step.fetch("instructions"), "OKF v0.2"
      assert_includes step.fetch("instructions"), "no normative edit is needed" if step == fix.step_at(4)
      assert_includes step.dig("templates", "documentation_report"), "findings"
    end
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
    assert_includes response.parsed_body.dig("data", "step", "templates", "publication_report"), "independently verified revision"
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
    assert_includes Workflow.find_by!(name: "KOS Fix v4").step_at(0).dig("templates", "root_cause_report"), "confirmed cause"
  end

  test "new brief separates approval from proposals and preserves a compact self-contained snapshot" do
    load Rails.root.join("db/seeds.rb")
    brief = Workflow.find_by!(name: "KOS Brief v4")
    agreement = brief.step_at(0).fetch("instructions")
    assert_includes agreement, "proposals not yet approved"
    assert_includes agreement, "questions awaiting answers"
    assert_includes agreement, "technical choices left to execution"
    assert_includes agreement, "whether access is local/trusted or external"
    assert_includes agreement, "first to approve required behavior, then separately to approve the high-level plan"

    snapshot = brief.step_at(1).fetch("templates")
    assert_includes snapshot.fetch("requirements"), "explicitly approved"
    assert_includes snapshot.fetch("specification"), "Self-contained concise approved behavior"
    assert_includes snapshot.fetch("specification"), "verifiable project revision"
    assert_includes snapshot.fetch("implementation_plan"), "details belong to each Execution task"
    assert_includes snapshot.fetch("planning_report"), "explicitly record gaps"
    assert_includes brief.step_at(2).fetch("templates").fetch("publication_report"), "no findings"

    execution = Workflow.find_by!(name: "KOS Execution v4")
    assert_includes execution.step_at(0).fetch("instructions"), "if they differ materially"
    [ execution, Workflow.find_by!(name: "KOS Fix v4") ].each do |workflow|
      documentation = workflow.steps.find { |step| step.fetch("name") == "Update project documentation" }
      assert_includes documentation.dig("templates", "documentation_report"), "no findings"
      assert_includes documentation.fetch("instructions"), "verified corrections"
    end
  end
end
