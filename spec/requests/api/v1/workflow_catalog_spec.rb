require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe "API v1 workflow catalog", :aggregate_failures, type: :request do
  include WorkflowCatalogHelpers

  around do |example|
    previous = ENV["KOS_API_TOKEN"]
    ENV["KOS_API_TOKEN"] = "catalog-test-token"
    example.run
  ensure
    ENV["KOS_API_TOKEN"] = previous
  end

  before { quick_fix_task_type }

  def headers(key: nil)
    value = { "Authorization" => "Bearer catalog-test-token", "Accept" => "application/json" }
    value["Idempotency-Key"] = key if key
    value
  end

  def document
    JSON.parse(response.body)
  end

  def command_request(command, body)
    { "schema_version" => "1", "command" => command, "body" => body }
  end

  def import_body(definition = workflow_definition, expected_lock_version: 0)
    { "workflow_id" => "quick-fix", "definition" => definition,
      "expected_lock_version" => expected_lock_version }
  end

  def post_command(path, command, body, key: "catalog-key-1")
    post path, params: command_request(command, body), headers: headers(key: key), as: :json
  end

  def expect_result_schema
    expect(Kos::Cli::SchemaRegistry.new).to be_valid("commands.json", "result", document)
  end

  it "requires authentication for catalog mutations" do
    post "/api/v1/workflow-drafts/quick-fix", params: command_request("workflow_draft.import", import_body),
      headers: { "Idempotency-Key" => "catalog-key-1" }, as: :json

    expect([ response.status, document.dig("error", "code") ]).to eq([ 401, "authentication_required" ])
  end

  it "creates a draft and replays its original semantic result" do
    2.times { post_command("/api/v1/workflow-drafts/quick-fix", "workflow_draft.import", import_body) }

    expect([ response.status, document.dig("data", "lock_version"), WorkflowDraft.count,
      IdempotencyRecord.count ]).to eq([ 200, 1, 1, 1 ])
    expect_result_schema
  end

  it "replaces the whole draft under optimistic locking" do
    replace_draft

    expect([ response.status, document.dig("data", "definition", "version"),
      document.dig("data", "lock_version") ]).to eq([ 200, "1.1.0", 2 ])
  end

  it "rejects path identity mismatch and missing idempotency keys" do
    first = mismatched_path_result
    post_import_without_key

    expect([ first, response.status, document.dig("error", "code") ])
      .to eq([ [ 400, "malformed_input" ], 400, "malformed_input" ])
  end

  it "rejects idempotency key reuse with another payload" do
    post_command("/api/v1/workflow-drafts/quick-fix", "workflow_draft.import", import_body)
    post_command("/api/v1/workflow-drafts/quick-fix", "workflow_draft.import",
      import_body(workflow_definition(version: "1.1.0")))

    expect([ response.status, document.dig("error", "code") ]).to eq([ 409, "idempotency_conflict" ])
  end

  it "reports an unsupported mutation body schema version explicitly" do
    request = command_request("workflow_draft.import", import_body).merge("schema_version" => "2")
    post "/api/v1/workflow-drafts/quick-fix", params: request, headers: headers(key: "catalog-key-1"), as: :json

    expect([ response.status, document.dig("error", "code") ]).to eq([ 400, "unsupported_schema_version" ])
  end

  it "rejects duplicate JSON object member names" do
    payload = '{"schema_version":"1","command":"workflow.publish","command":"workflow.publish","body":{}}'
    post "/api/v1/workflow-drafts/quick-fix/publication", params: payload,
      headers: headers(key: "catalog-key-1").merge("Content-Type" => "application/json")

    expect([ response.status, document.dig("error", "code") ]).to eq([ 400, "malformed_input" ])
  end

  it "rejects non-object JSON mutation documents" do
    %w[[] null 1 true].each do |payload|
      post "/api/v1/workflow-drafts/quick-fix/publication", params: payload,
        headers: headers(key: "catalog-key-1").merge("Content-Type" => "application/json")
      expect([ response.status, document.dig("error", "code") ]).to eq([ 400, "malformed_input" ])
    end
  end

  it "reports graph errors without publishing" do
    import_invalid_draft
    get "/api/v1/workflow-drafts/quick-fix/validation", headers: headers

    expect_validation_result
  end

  it "publishes, exports, and semantically replays an identical version" do
    workflow_id, first_digest = published_identity
    republish_with_new_key
    get "/api/v1/workflow-versions/#{workflow_id}/export", headers: headers

    expect_export_result(first_digest)
  end

  it "rejects publication of a graph-invalid draft" do
    import_invalid_draft
    publish_request(key: "catalog-key-2")

    expect([ response.status, document.dig("error", "code"), WorkflowVersion.count ])
      .to eq([ 422, "workflow_definition_invalid", 0 ])
  end

  it "activates a published version and returns the advanced task type lock" do
    import_and_publish
    workflow_id = document.dig("data", "id")
    activate_request(workflow_id)

    expect_activation_result(workflow_id)
  end

  def import_and_publish
    post_command("/api/v1/workflow-drafts/quick-fix", "workflow_draft.import", import_body)
    publish_request(key: "catalog-key-2")
    expect(response).to have_http_status(:created)
    expect_result_schema
  end

  def replace_draft
    post_command("/api/v1/workflow-drafts/quick-fix", "workflow_draft.import", import_body)
    post_command("/api/v1/workflow-drafts/quick-fix", "workflow_draft.import",
      import_body(workflow_definition(version: "1.1.0"), expected_lock_version: 1), key: "catalog-key-2")
  end

  def mismatched_path_result
    post_command("/api/v1/workflow-drafts/other", "workflow_draft.import", import_body)
    [ response.status, document.dig("error", "code") ]
  end

  def post_import_without_key
    post "/api/v1/workflow-drafts/quick-fix", params: command_request("workflow_draft.import", import_body),
      headers: headers, as: :json
  end

  def import_invalid_draft
    invalid = workflow_definition
    invalid.fetch("transitions").first["to"] = "missing"
    post_command("/api/v1/workflow-drafts/quick-fix", "workflow_draft.import", import_body(invalid))
  end

  def publish_request(key:)
    post_command("/api/v1/workflow-drafts/quick-fix/publication", "workflow.publish",
      { "workflow_id" => "quick-fix", "expected_lock_version" => 1 }, key: key)
  end

  def published_identity
    import_and_publish
    [ document.dig("data", "id"), document.dig("data", "content_digest") ]
  end

  def republish_with_new_key
    publish_request(key: "catalog-key-3")
  end

  def activate_request(workflow_id)
    body = { "task_type" => "quick-fix", "workflow_version_id" => workflow_id, "expected_lock_version" => 0 }
    post_command("/api/v1/task-types/quick-fix/current-workflow", "workflow.activate", body,
      key: "catalog-key-3")
  end

  def expect_validation_result
    expect([ response.status, document.dig("data", "valid"), document.dig("data", "errors").empty?,
      WorkflowVersion.count ]).to eq([ 200, false, false, 0 ])
    expect_result_schema
  end

  def expect_export_result(digest)
    expect([ response.status, WorkflowVersion.count,
      WorkflowCatalog::CanonicalDefinition.digest(document.fetch("data")) ]).to eq([ 200, 1, digest ])
    expect_result_schema
  end

  def expect_activation_result(workflow_id)
    expect([ response.status, document.dig("data", "current_workflow_version_id"),
      document.dig("data", "lock_version") ]).to eq([ 200, workflow_id, 1 ])
    expect_result_schema
  end
end
