require "test_helper"

class AdministrationApiTest < ActionDispatch::IntegrationTest
  setup do
    @headers = { "Authorization" => "Bearer test-api-token" }
  end

  test "registers projects workflows and task types" do
    post projects_path, params: {
      name: "KOS",
      remote_url: "https://example.test/kos.git",
      default_branch: "main"
    }, headers: @headers, as: :json
    assert_response :created
    assert_equal "KOS", response.parsed_body.dig("project", "name")

    post workflows_path, params: {
      name: "Default",
      definition_json: valid_workflow_definition
    }, headers: @headers, as: :json
    assert_response :created
    workflow_id = response.parsed_body.dig("workflow", "id")
    assert_equal valid_workflow_definition, response.parsed_body.dig("workflow", "definition_json")

    post task_types_path, params: { key: "feature", name: "Feature", workflow_id: }, headers: @headers, as: :json
    assert_response :created
    assert_equal "feature", response.parsed_body.dig("task_type", "key")
    assert_equal workflow_id, response.parsed_body.dig("task_type", "workflow_id")
  end

  test "rejects a new workflow without an explicit model tier" do
    definition = valid_workflow_definition
    definition["steps"][0].delete("model_tier")

    post workflows_path, params: { name: "Missing tier", definition_json: definition }, headers: @headers, as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
  end

  test "changes a task type workflow without changing existing tasks" do
    original = create_workflow(name: "Original")
    replacement = create_workflow(name: "Replacement")
    task_type = create_task_type(name: "Feature", key: "feature", workflow: original)
    task = create_task(workflow: original, task_type:)

    patch task_type_path(task_type), params: { workflow_id: replacement.id }, headers: @headers, as: :json

    assert_response :success
    assert_equal "feature", response.parsed_body.dig("task_type", "key")
    assert_equal replacement.id, response.parsed_body.dig("task_type", "workflow_id")
    assert_equal original, task.reload.workflow
  end

  test "rejects duplicate and reserved task type keys" do
    workflow = create_workflow
    create_task_type(key: "feature", workflow:)

    [ "feature", "brief", "development", "fix" ].each do |key|
      post task_types_path, params: { key:, name: key.titleize, workflow_id: workflow.id }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_equal "validation_failed", response.parsed_body["error"]
      assert response.parsed_body.fetch("details").key?("key")
    end
  end

  test "returns stable errors for malformed and invalid administration requests" do
    post projects_path, params: { name: "Missing fields" }, headers: @headers, as: :json
    assert_response :bad_request
    assert_equal "bad_request", response.parsed_body["error"]

    post workflows_path, params: { name: "Invalid", definition_json: { steps: [] } }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
    assert response.parsed_body.fetch("details").key?("definition_json")

    post task_types_path, params: { key: "missing", name: "Missing workflow", workflow_id: -1 }, headers: @headers,
      as: :json
    assert_response :not_found
    assert_equal({ "error" => "not_found" }, response.parsed_body)
  end

  test "returns bad request for malformed JSON" do
    post projects_path, params: "{", headers: @headers.merge("Content-Type" => "application/json")

    assert_response :bad_request
    assert_equal "bad_request", response.parsed_body["error"]
  end

  test "requires authentication on every administration route" do
    requests = [
      -> { post projects_path, params: {}, as: :json },
      -> { post workflows_path, params: {}, as: :json },
      -> { post task_types_path, params: {}, as: :json },
      -> { patch task_type_path(1), params: {}, as: :json }
    ]

    requests.each do |request|
      request.call
      assert_response :unauthorized
      assert_equal({ "error" => "unauthorized" }, response.parsed_body)
    end
  end

  test "does not expose PUT as an update alias" do
    put task_type_path(1), params: {}, headers: @headers, as: :json

    assert_response :not_found
  end
end
