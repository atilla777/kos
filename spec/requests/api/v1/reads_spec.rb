require "rails_helper"

RSpec.describe "API v1 reads", :aggregate_failures, type: :request do
  around do |example|
    previous = ENV["KOS_API_TOKEN"]
    ENV["KOS_API_TOKEN"] = token
    example.run
  ensure
    ENV["KOS_API_TOKEN"] = previous
  end

  def token
    "test-api-token"
  end

  def headers(token = self.token)
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end

  def document
    JSON.parse(response.body)
  end

  def expect_schema_valid(schema, definition, value = document)
    expect(Kos::Cli::SchemaRegistry.new).to be_valid(schema, definition, value)
  end

  def definition(version: "1.0.0")
    path = Rails.root.join("spec/fixtures/workflow_definitions/v1/valid/quick-fix.json")
    JSON.parse(File.read(path)).merge("version" => version)
  end

  def canonical_json(value)
    case value
    when Hash
      "{#{value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(',')}}"
    when Array
      "[#{value.map { |item| canonical_json(item) }.join(',')}]"
    else
      JSON.generate(value)
    end
  end

  def serialized_definition(value)
    copy = Marshal.load(Marshal.dump(value))
    copy.fetch("statuses").sort_by! { |status| status.fetch("id") }
    copy.fetch("statuses").each do |status|
      status.fetch("artifact_templates").sort_by! { |template| template.fetch("id") }
      status.fetch("allowed_repository_effects").sort!
      status.fetch("required_artifacts").sort_by! { |requirement| requirement.fetch("type") }
      status.fetch("required_artifacts").each { |requirement| requirement.fetch("allowed_states").sort! }
    end
    copy.fetch("transitions").sort_by! { |transition| transition.values_at("from", "to") }
    copy
  end

  def create_catalog(version: "1.0.0", published_at: Time.utc(2026, 9, 10, 12))
    task_type = TaskType.find_or_create_by!(id: "quick-fix") do |record|
      record.name = "quick-fix"
      record.workflow_id = "quick-fix"
    end
    value = definition(version:)
    draft = WorkflowDraft.find_or_create_by!(workflow_id: "quick-fix") do |record|
      record.task_type = task_type
      record.definition = value
    end
    workflow = WorkflowVersion.create!(task_type:, workflow_id: "quick-fix", version:,
      content_digest: "sha256:#{Digest::SHA256.hexdigest(canonical_json(serialized_definition(value)))}")
    states = value.fetch("statuses").to_h do |status|
      state = WorkflowState.create!(workflow_version: workflow, identifier: status.fetch("id"),
        initial: status.fetch("id") == value.fetch("initial_status"), execution_mode: status.fetch("execution_mode"),
        instruction: status.fetch("instruction"), worktree_policy: status.fetch("worktree"),
        repository_changes_policy: status.fetch("repository_changes"))
      status.fetch("artifact_templates").each do |template|
        ArtifactTemplate.create!(workflow_state: state, identifier: template.fetch("id"),
          media_type: template.fetch("media_type"), content: template.fetch("content"))
      end
      status.fetch("allowed_repository_effects").each do |effect|
        WorkflowStateEffect.create!(workflow_state: state, effect:)
      end
      status.fetch("required_artifacts").each do |requirement|
        record = ArtifactRequirement.create!(workflow_state: state,
          artifact_type: requirement.fetch("type"), cardinality: requirement.fetch("cardinality"),
          subject: requirement.fetch("subject"))
        requirement.fetch("allowed_states").each do |allowed_state|
          ArtifactRequirementState.create!(artifact_requirement: record, state: allowed_state)
        end
      end
      [ status.fetch("id"), state ]
    end
    states[value.fetch("terminal_status")] = WorkflowState.create!(workflow_version: workflow,
      identifier: value.fetch("terminal_status"), terminal: true)
    value.fetch("transitions").each do |transition|
      record = WorkflowTransition.create!(workflow_version: workflow,
        from_state: states.fetch(transition.fetch("from")), to_state: states.fetch(transition.fetch("to")))
      transition.fetch("conditions").each_with_index do |condition, position|
        WorkflowTransitionCondition.create!(workflow_transition: record, position:,
          condition_type: condition.fetch("type"), artifact_type: condition["artifact_type"],
          artifact_state: condition["state"], decision: condition["decision"], value: condition["value"])
      end
    end
    workflow.update!(published_at:) if published_at
    [ task_type, draft, workflow, states ]
  end

  def create_repository(prefix: "KOS")
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: prefix,
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end

  def create_execution(artifact_created_at: nil)
    task_type, _draft, workflow, states = create_catalog
    repository = create_repository
    task = Task.create!(repository:, sequence: 1, title: "Read API state", task_type:, workflow_version: workflow,
      workflow_state: states.fetch("development"))
    now = Time.utc(2026, 9, 10, 13)
    attempt = WorkflowAttempt.create!(repository:, task:, workflow_state: task.workflow_state,
      owner_id: "orchestrator", idempotency_key: "read-api-attempt", fencing_token: 1,
      lease_expires_at: now + 300, heartbeat_at: now, started_at: now)
    task.update!(active_attempt: attempt)
    reservation = WorktreeReservation.create!(repository:, task:, workflow_attempt: attempt,
      branch: "kos/task-#{task.number}", path: "/tmp/worktrees/#{task.number}", fencing_token: 1)
    task.update!(worktree_reservation: reservation)
    artifact = TaskArtifact.create!(repository:, task:, workflow_attempt: attempt, artifact_type: "candidate",
      state: "produced", producer: "developer", created_at: artifact_created_at || now,
      metadata: { "kind" => "candidate", "candidate_sha" => "a" * 40, "task_trailer" => task.number })
    { repository:, task:, attempt:, reservation:, artifact: }
  end

  it "keeps the health check public" do
    get "/up"
    expect(response).to have_http_status(:ok)
  end

  it "requires authentication for API reads" do
    get "/api/v1/task-types", params: { limit: 1 }
    expect([ response.status, document.dig("error", "code") ]).to eq([ 401, "authentication_required" ])
    expect_schema_valid("envelopes.json", "failure")
  end

  it "rejects an invalid token" do
    get "/api/v1/task-types", params: { limit: 1 }, headers: headers("wrong")
    expect([ response.status, document.dig("error", "code") ]).to eq([ 401, "invalid_token" ])
  end

  it "returns task types" do
    task_type, = create_catalog
    get "/api/v1/task-types", params: { limit: 20 }, headers: headers
    expect(document.dig("data", "task_types")).to eq([ Api::V1::Serializer.task_type(task_type) ])
    expect_schema_valid("commands.json", "result")
  end

  it "lists published workflow versions" do
    _, _, workflow, = create_catalog
    get "/api/v1/workflow-versions", params: { limit: 20 }, headers: headers
    expect(document.dig("data", "workflows", 0, "id")).to eq(workflow.id)
    expect_schema_valid("commands.json", "result")
  end

  it "reconstructs a complete deterministic workflow version" do
    _, _, workflow, = create_catalog
    get "/api/v1/workflow-versions/#{workflow.id}", headers: headers
    expect(document.dig("data", "definition")).to eq(serialized_definition(definition))
    expect_schema_valid("commands.json", "result")
  end

  it "returns the complete workflow draft" do
    _, draft, = create_catalog
    get "/api/v1/workflow-drafts/#{draft.workflow_id}", headers: headers
    expect(document.dig("data", "definition")).to eq(definition)
    expect_schema_valid("commands.json", "result")
  end

  it "omits a current version before task type activation" do
    task_type, = create_catalog(published_at: nil)
    get "/api/v1/task-types", params: { limit: 20 }, headers: headers
    expect(document.dig("data", "task_types", 0)).not_to have_key("current_workflow_version_id")
    expect_schema_valid("commands.json", "result")
    expect(task_type.current_workflow_version_id).to be_nil
  end

  it "excludes unpublished workflow versions" do
    create_catalog(published_at: nil)
    get "/api/v1/workflow-versions", params: { limit: 20 }, headers: headers
    expect(document.dig("data", "workflows")).to be_empty
  end

  it "returns a repository-scoped task with derived status" do
    records = create_execution
    repository = records.fetch(:repository)
    get "/api/v1/repositories/#{repository.id}/tasks/#{records.fetch(:task).number}", headers: headers
    expect(document.dig("data", "status")).to eq("active")
    expect_schema_valid("commands.json", "result")
  end

  it "returns a repository-scoped attempt" do
    records = create_execution
    repository = records.fetch(:repository)
    get "/api/v1/repositories/#{repository.id}/attempts/#{records.fetch(:attempt).id}", headers: headers
    expect(document.dig("data", "id")).to eq(records.fetch(:attempt).id)
    expect_schema_valid("commands.json", "result")
  end

  it "returns a repository-scoped worktree reservation" do
    records = create_execution
    repository = records.fetch(:repository)
    get "/api/v1/repositories/#{repository.id}/worktree-reservations/#{records.fetch(:reservation).id}", headers: headers
    expect(document.dig("data", "attempt_id")).to eq(records.fetch(:attempt).id)
    expect_schema_valid("commands.json", "result")
  end

  it "lists repository-scoped task artifacts" do
    expect_artifact_list(create_execution)
  end

  it "does not reveal absent repositories" do
    records = create_execution
    get "/api/v1/repositories/#{SecureRandom.uuid}/tasks/#{records.fetch(:task).number}", headers: headers
    expect([ response.status, document.dig("error", "code") ]).to eq([ 403, "repository_access_denied" ])
    expect_schema_valid("envelopes.json", "failure")
  end

  it "hides resources owned by another repository" do
    records = create_execution
    other = create_repository(prefix: "ALT")
    get "/api/v1/repositories/#{other.id}/attempts/#{records.fetch(:attempt).id}", headers: headers
    expect([ response.status, document.dig("error", "code") ]).to eq([ 404, "attempt_not_found" ])
  end

  it "binds deterministic cursors to their command and scope" do
    expect_cursor_binding
  end

  it "keeps a maximum-length task type cursor within the protocol limit" do
    cursor = Api::V1::Cursor.new(command: "task_type.list", scope: "global")

    expect(cursor.encode([ "a" * 128 ]).length).to be <= 255
  end

  it "does not repeat artifacts whose timestamps include fractional seconds" do
    expect_fractional_timestamp_pagination
  end

  def expect_fractional_timestamp_pagination
    records = create_execution(artifact_created_at: Time.utc(2026, 9, 10, 13, 0, 0, 100_000))
    task = records.fetch(:task)
    second = TaskArtifact.create!(repository: task.repository, task:,
      workflow_attempt: records.fetch(:attempt), artifact_type: "candidate", state: "produced",
      producer: "developer", created_at: Time.utc(2026, 9, 10, 13, 0, 0, 200_000),
      metadata: { "kind" => "candidate", "candidate_sha" => "b" * 40, "task_trailer" => task.number })
    path = "/api/v1/repositories/#{task.repository_id}/tasks/#{task.number}/artifacts"

    get path, params: { limit: 1 }, headers: headers
    cursor = document.dig("data", "next_cursor")
    get path, params: { limit: 1, cursor: }, headers: headers

    expect(document.dig("data", "artifacts", 0, "id")).to eq(second.id)
  end

  it "rejects malformed arguments" do
    get "/api/v1/workflow-versions/not-a-uuid", headers: headers
    expect([ response.status, document.dig("error", "code") ]).to eq([ 400, "malformed_input" ])
  end

  it "rejects query parameters on path-only reads" do
    _, _, workflow, = create_catalog
    get "/api/v1/workflow-versions/#{workflow.id}", params: { workflow_version_id: SecureRandom.uuid },
      headers: headers

    expect([ response.status, document.dig("error", "code") ]).to eq([ 400, "malformed_input" ])
  end

  it "rejects a task locator query on artifact listing" do
    records = create_execution
    task = records.fetch(:task)
    path = "/api/v1/repositories/#{task.repository_id}/tasks/#{task.number}/artifacts"

    get path, params: { limit: 1, task_number: "ALT-000001" }, headers: headers

    expect([ response.status, document.dig("error", "code") ]).to eq([ 400, "malformed_input" ])
  end

  it "rejects an unsupported API schema version" do
    get "/api/v2/task-types", headers: headers
    expect([ response.status, document.dig("error", "code") ]).to eq([ 400, "unsupported_schema_version" ])
    expect_schema_valid("envelopes.json", "failure")
  end

  it "returns resource-specific absence" do
    create_catalog
    get "/api/v1/workflow-drafts/missing", headers: headers
    expect([ response.status, document.dig("error", "code") ]).to eq([ 404, "workflow_draft_not_found" ])
    expect_schema_valid("envelopes.json", "failure")
  end

  def expect_cursor_binding
    records = create_execution
    task = records.fetch(:task)
    TaskArtifact.create!(repository: task.repository, task:, workflow_attempt: records.fetch(:attempt),
      artifact_type: "candidate", state: "produced", producer: "developer",
      created_at: records.fetch(:artifact).created_at,
      metadata: { "kind" => "candidate", "candidate_sha" => "b" * 40, "task_trailer" => task.number })
    path = "/api/v1/repositories/#{task.repository_id}/tasks/#{task.number}/artifacts"
    get path, params: { limit: 1 }, headers: headers
    first_id = document.dig("data", "artifacts", 0, "id")
    cursor = document.dig("data", "next_cursor")
    expect(cursor.length).to be <= 255
    get path, params: { limit: 1, cursor: }, headers: headers
    expect(document.dig("data", "artifacts", 0, "id")).not_to eq(first_id)
    get "/api/v1/workflow-versions", params: { limit: 1, cursor: }, headers: headers
    expect([ response.status, document.dig("error", "code") ]).to eq([ 400, "malformed_input" ])
    other_task = Task.create!(repository: task.repository, sequence: 2, title: "Other task",
      task_type: task.task_type, workflow_version: task.workflow_version, workflow_state: task.workflow_state)
    other_path = "/api/v1/repositories/#{task.repository_id}/tasks/#{other_task.number}/artifacts"
    get other_path, params: { limit: 1, cursor: }, headers: headers
    expect([ response.status, document.dig("error", "code") ]).to eq([ 400, "malformed_input" ])
    expect_schema_valid("envelopes.json", "failure")
  end

  def expect_artifact_list(records)
    repository = records.fetch(:repository)
    get "/api/v1/repositories/#{repository.id}/tasks/#{records.fetch(:task).number}/artifacts",
      params: { limit: 20 }, headers: headers
    expect(document.dig("data", "artifacts", 0, "id")).to eq(records.fetch(:artifact).id)
    expect_schema_valid("commands.json", "result")
  end
end
