require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe "API v1 task creation", :aggregate_failures, type: :request do
  include WorkflowCatalogHelpers

  around do |example|
    previous = ENV["KOS_API_TOKEN"]
    ENV["KOS_API_TOKEN"] = "task-test-token"
    example.run
  ensure
    ENV["KOS_API_TOKEN"] = previous
  end

  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end

  def headers(key: "task-create-key-1")
    { "Authorization" => "Bearer task-test-token", "Accept" => "application/json",
      "Idempotency-Key" => key }
  end

  def request_document(body = { "title" => "Repair timeout", "task_type" => "quick-fix" },
    repository_id: repository.id)
    { "schema_version" => "1", "command" => "task.create", "repository_id" => repository_id, "body" => body }
  end

  def create_request(document = request_document, request_headers: headers)
    post "/api/v1/repositories/#{repository.id}/tasks", params: document, headers: request_headers, as: :json
  end

  def document
    JSON.parse(response.body)
  end

  def activate_workflow
    version = publish_workflow
    quick_fix_task_type.update!(current_workflow_version: version)
    version
  end

  def created_task_summary
    [ response.status, document.dig("data", "number"), document.dig("data", "workflow_version_id"),
      document.dig("data", "workflow_status"), document.dig("data", "status"), Task.count,
      repository.reload.next_task_sequence, IdempotencyRecord.count ]
  end

  def malformed_scope_and_title_results
    create_request(request_document(repository_id: SecureRandom.uuid))
    mismatch = [ response.status, document.dig("error", "code") ]
    create_request(request_document({ "title" => " \t", "task_type" => "quick-fix" }))
    [ mismatch, response.status, document.dig("error", "code"), Task.count ]
  end

  def authentication_results
    create_request(request_document, request_headers: headers.except("Authorization"))
    unauthenticated = [ response.status, document.dig("error", "code") ]
    create_request(request_document, request_headers: headers(key: "short"))
    [ unauthenticated, response.status, document.dig("error", "code"), Task.count ]
  end

  def replay_after_activation
    create_request
    first = [ response.status, document.dig("error", "code") ]
    activate_workflow
    create_request
    [ first, response.status, document.dig("error", "code"), repository.reload.next_task_sequence,
      IdempotencyRecord.count ]
  end

  it "creates and idempotently replays one pinned task" do
    version = activate_workflow
    2.times { create_request }

    expect(created_task_summary)
      .to eq([ 201, "KOS-000001", version.id, "implementation-planning", "open", 1, 2, 1 ])
    expect(Kos::Cli::SchemaRegistry.new).to be_valid("commands.json", "result", document)
  end

  it "rejects key reuse with another title without allocating" do
    activate_workflow
    create_request
    create_request(request_document({ "title" => "Another fix", "task_type" => "quick-fix" }))

    expect([ response.status, document.dig("error", "code"), Task.count,
      repository.reload.next_task_sequence ]).to eq([ 409, "idempotency_conflict", 1, 2 ])
  end

  it "rejects repository path/body mismatch and whitespace-only titles" do
    activate_workflow

    expect(malformed_scope_and_title_results)
      .to eq([ [ 400, "malformed_input" ], 400, "malformed_input", 0 ])
  end

  it "returns task_type_unavailable without consuming a number" do
    quick_fix_task_type

    expect(replay_after_activation)
      .to eq([ [ 409, "task_type_unavailable" ], 409, "task_type_unavailable", 1, 1 ])
  end

  it "returns task_number_exhausted after the final number" do
    activate_workflow
    repository.update!(next_task_sequence: 1_000_000)
    create_request

    expect([ response.status, document.dig("error", "code"), Task.count,
      repository.reload.next_task_sequence ]).to eq([ 409, "task_number_exhausted", 0, 1_000_000 ])
  end

  it "requires authentication and a valid idempotency key" do
    activate_workflow

    expect(authentication_results)
      .to eq([ [ 401, "authentication_required" ], 400, "malformed_input", 0 ])
  end
end
