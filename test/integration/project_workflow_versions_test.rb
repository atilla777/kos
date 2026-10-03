require "test_helper"

class ProjectWorkflowVersionsTest < ActionDispatch::IntegrationTest
  REPOSITORY = "github.com/workflow/versions"

  setup { load Rails.root.join("db/seeds.rb") }

  test "installs three project copies atomically and reuses their ids on retry" do
    post "/api/v1/workflows/install-base", params: { project: REPOSITORY }, as: :json
    assert_response :ok
    editions = response.parsed_body.dig("data", "workflows")
    assert_equal %w[KOS KOS KOS], editions.map { |edition| edition.fetch("name").split.first }
    assert_equal [ 1, 1, 1 ], editions.map { |edition| edition.fetch("edition") }
    assert_equal 3, editions.map { |edition| edition.fetch("base_workflow_id") }.uniq.length

    post "/api/v1/workflows/install-base", params: { project: REPOSITORY }, as: :json
    assert_response :ok
    assert_equal editions.map { |edition| edition.fetch("id") }, response.parsed_body.dig("data", "workflows").map { |edition| edition.fetch("id") }
    assert_equal 3, Project.find_by!(repository: REPOSITORY).workflows.count

    delete "/api/v1/workflows/#{editions.first.fetch('base_workflow_id')}", params: { project: REPOSITORY }
    assert_response :conflict
    assert_equal "workflow_in_use", response.parsed_body.dig("error", "code")
  end

  test "missing base and conflicting existing copy do not leave a partial installation" do
    Workflow.find_by!(project_id: nil, name: "KOS Base Fix v1").destroy!
    post "/api/v1/workflows/install-base", params: { project: REPOSITORY }, as: :json
    assert_response :conflict
    assert_equal "workflow_base_missing", response.parsed_body.dig("error", "code")
    assert_nil Project.find_by(repository: REPOSITORY)

    load Rails.root.join("db/seeds.rb")
    post "/api/v1/workflows/install-base", params: { project: REPOSITORY }, as: :json
    project = Project.find_by!(repository: REPOSITORY)
    project.workflows.find_by!(name: "KOS Execution v1").update_columns(steps: [])
    post "/api/v1/workflows/install-base", params: { project: REPOSITORY }, as: :json
    assert_response :conflict
    assert_equal "workflow_install_conflict", response.parsed_body.dig("error", "code")
    assert_equal 3, project.workflows.count
  end

  test "a new edition keeps old task steps and stale or foreign source cannot create versions" do
    post "/api/v1/workflows/install-base", params: { project: REPOSITORY }, as: :json
    brief, execution, fix = response.parsed_body.dig("data", "workflows")
    post "/api/v1/tasks", params: { project: REPOSITORY, workflow_id: brief.fetch("id"),
      kind: "decomposition", title: "Brief", description: "Plan work" }, as: :json
    assert_response :created
    task = Task.find(response.parsed_body.dig("data", "task", "id"))
    task.update_columns(current_step: 1)
    report = TaskArtifact.create!(task: task, key: "requirements", content: "# Approved result")
    old_steps = task.workflow.steps.deep_dup

    post "/api/v1/workflows", params: { project: REPOSITORY, based_on_id: brief.fetch("id"),
      steps: old_steps.map { |step| step.merge("instructions" => "Updated: #{step.fetch('instructions')}") } }, as: :json
    assert_response :created
    newer = response.parsed_body.dig("data", "workflow")
    assert_equal "KOS Brief v2", newer.fetch("name")
    assert_equal brief.fetch("base_workflow_id"), newer.fetch("base_workflow_id")
    assert_equal 2, newer.fetch("edition")
    assert_equal old_steps, task.reload.workflow.steps
    assert_equal brief.fetch("id"), task.workflow_id
    assert_equal 1, task.current_step
    assert_equal "# Approved result", report.reload.content

    post "/api/v1/workflows", params: { project: REPOSITORY, based_on_id: brief.fetch("id"), steps: old_steps }, as: :json
    assert_response :conflict
    assert_equal "workflow_version_conflict", response.parsed_body.dig("error", "code")
    post "/api/v1/workflows", params: { project: "github.com/another/owner", based_on_id: newer.fetch("id"), steps: old_steps }, as: :json
    assert_response :not_found
    assert_equal 2, Workflow.where(base_workflow_id: brief.fetch("base_workflow_id"), project_id: task.project_id).count
    assert_equal 1, Workflow.find(execution.fetch("id")).edition
    assert_equal 1, Workflow.find(fix.fetch("id")).edition

    assert_raises(ActiveRecord::StatementInvalid) do
      Workflow.connection.execute("UPDATE workflows SET edition = 3 WHERE id = #{newer.fetch('id')}")
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      Workflow.connection.execute("UPDATE workflows SET base_workflow_id = #{fix.fetch('base_workflow_id')} WHERE id = #{newer.fetch('id')}")
    end
  end
end
