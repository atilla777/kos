require "json"
require "json_schemer"
require "spec_helper"

module CliV1Contract
  SCHEMA_DIRECTORY = File.expand_path("../../schemas/cli/v1", __dir__)
  FIXTURE_DIRECTORY = File.expand_path("../fixtures/cli/v1", __dir__)
  SCHEMAS = Dir[File.join(SCHEMA_DIRECTORY, "*.json")].sort.to_h do |path|
    [ File.basename(path), JSON.parse(File.read(path)) ]
  end
  REGISTRY = SCHEMAS.values.to_h { |schema| [ URI(schema.fetch("$id")), schema ] }
  EXPECTED_COMMANDS = %w[task_type.list workflow.list workflow.get task.get attempt.get worktree.get artifact.list
    publication.get task.create attempt.claim attempt.renew attempt.fail attempt.needs_human attempt.reconcile worktree.reserve
    worktree.confirm worktree.reconcile worktree.release artifact.register step.complete publication.prepare
    publication.reconcile publication.complete]
  REQUEST_ID = "99999999-9999-4999-8999-999999999999"
  REPOSITORY_ID = "33333333-3333-4333-8333-333333333333"
  TASK_ID = "11111111-1111-4111-8111-111111111111"
  ATTEMPT_ID = "22222222-2222-4222-8222-222222222222"
  RESERVATION_ID = "55555555-5555-4555-8555-555555555555"
  PUBLICATION_ID = "44444444-4444-4444-8444-444444444444"
  DIGEST = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  SHA = "1111111111111111111111111111111111111111"

  def self.references(value)
    case value
    when Hash
      value.flat_map { |key, child| (key == "$ref" ? [ child ] : []) + references(child) }
    when Array
      value.flat_map { |child| references(child) }
    else
      []
    end
  end

  def self.dispatched_commands(value)
    return [] unless value.is_a?(Hash) || value.is_a?(Array)
    return value.flat_map { |child| dispatched_commands(child) } if value.is_a?(Array)

    command = value.dig("properties", "command")
    own_commands = command ? Array(command["const"] || command["enum"]) : []
    own_commands + value.values.flat_map { |child| dispatched_commands(child) }
  end

  def self.preconditions
    { "expected_lock_version" => 3, "attempt_id" => ATTEMPT_ID, "fencing_token" => 8 }
  end

  def self.manifest(outcome, artifacts = [])
    { "schema_version" => "1", "attempt_id" => ATTEMPT_ID, "input_context_digest" => DIGEST,
      "outcome" => outcome, "artifacts" => artifacts }
  end

  def self.artifact_input(type = "candidate")
    return publication_artifact_input if type == "publication"

    { "schema_version" => "1", "type" => "candidate", "state" => "produced", "producer" => "kos-development",
      "evidence_digest" => DIGEST,
      "metadata" => { "kind" => "candidate", "candidate_sha" => SHA, "task_trailer" => "TASK-000123" } }
  end

  def self.publication_artifact_input
    metadata = { "kind" => "publication", "publication_id" => PUBLICATION_ID, "candidate_sha" => SHA,
      "remote" => "origin", "base_ref" => "refs/heads/main", "observed_remote_tip" => SHA,
      "reachable" => true, "observed_at" => "2026-09-09T12:00:00Z" }
    { "schema_version" => "1", "type" => "publication", "state" => "published", "producer" => "kos-publish",
      "evidence_digest" => DIGEST, "metadata" => metadata }
  end

  def self.artifact_examples
    {
      "document" => [ "produced", "passed", { "kind" => "document", "path" => "tasks/TASK-000123/task.md",
        "commit_sha" => SHA, "content_digest" => DIGEST } ],
      "candidate" => [ "produced", "approved", artifact_input.fetch("metadata") ],
      "test" => [ "passed", "produced", { "kind" => "test", "candidate_sha" => SHA,
        "command" => "bundle exec rspec", "exit_code" => 0, "log_digest" => DIGEST } ],
      "review" => [ "approved", "passed", { "kind" => "review", "candidate_sha" => SHA,
        "verdict" => "approved", "review_attempt_id" => "88888888-8888-4888-8888-888888888888" } ],
      "publication" => [ "published", "approved", publication_artifact_input.fetch("metadata") ]
    }
  end

  def self.artifact_with(type, state, metadata)
    { "schema_version" => "1", "type" => type, "state" => state, "producer" => "kos-development",
      "evidence_digest" => DIGEST, "metadata" => metadata }
  end

  def self.task
    { "schema_version" => "1", "id" => TASK_ID, "repository_id" => REPOSITORY_ID, "number" => "TASK-000123",
      "title" => "Repair timeout handling", "task_type" => "quick-fix", "status" => "active",
      "workflow_status" => "development", "workflow_id" => "quick-fix", "workflow_version" => "1.0.0",
      "bundle_digest" => DIGEST, "lock_version" => 3, "active_publication_id" => PUBLICATION_ID,
      "created_at" => "2026-09-09T12:00:00Z",
      "updated_at" => "2026-09-09T12:01:00Z" }
  end

  def self.workflow
    { "schema_version" => "1", "id" => "quick-fix", "version" => "1.0.0", "bundle_digest" => DIGEST,
      "statuses" => %w[implementation-planning development review publication completed] }
  end

  def self.attempt
    { "schema_version" => "1", "id" => ATTEMPT_ID, "task_id" => TASK_ID, "workflow_status" => "development",
      "owner_id" => "orchestrator-1", "state" => "started", "fencing_token" => 8,
      "started_at" => "2026-09-09T12:00:00Z", "input_context_digest" => DIGEST }
  end

  def self.worktree
    { "schema_version" => "1", "id" => RESERVATION_ID, "repository_id" => REPOSITORY_ID, "task_id" => TASK_ID,
      "attempt_id" => ATTEMPT_ID, "branch" => "kos/task-TASK-000123", "path" => "/tmp/task-123",
      "state" => "confirmed", "fencing_token" => 8, "created_at" => "2026-09-09T12:00:00Z" }
  end

  def self.publication(state = "prepared")
    value = { "schema_version" => "1", "id" => PUBLICATION_ID, "repository_id" => REPOSITORY_ID,
      "task_id" => TASK_ID, "prepared_attempt_id" => ATTEMPT_ID, "current_owner_attempt_id" => ATTEMPT_ID,
      "candidate_sha" => SHA, "remote" => "origin", "base_ref" => "refs/heads/main", "expected_remote_oid" => SHA,
      "state" => state, "prepared_at" => "2026-09-09T12:00:00Z", "updated_at" => "2026-09-09T12:01:00Z" }
    if %w[reconciled superseded completed].include?(state)
      value.merge!("observed_remote_tip" => SHA, "candidate_reachable" => state != "superseded",
        "observation_digest" => DIGEST, "observed_at" => "2026-09-09T12:01:00Z",
        "reconciled_at" => "2026-09-09T12:01:00Z")
    end
    value["completed_at"] = "2026-09-09T12:02:00Z" if state == "completed"
    value
  end

  def self.artifact
    artifact_input.merge("id" => "66666666-6666-4666-8666-666666666666", "task_id" => TASK_ID,
      "attempt_id" => ATTEMPT_ID, "created_at" => "2026-09-09T12:00:00Z")
  end

  def self.publication_artifact
    publication_artifact_input.merge("id" => "77777777-7777-4777-8777-777777777777", "task_id" => TASK_ID,
      "attempt_id" => ATTEMPT_ID, "created_at" => "2026-09-09T12:00:00Z")
  end

  def self.request_bodies
    {
      "task_type.list" => { "limit" => 20 }, "workflow.list" => { "limit" => 20 },
      "workflow.get" => { "workflow_id" => "quick-fix", "version" => "1.0.0" },
      "task.get" => { "task_number" => "TASK-000123" }, "attempt.get" => { "attempt_id" => ATTEMPT_ID },
      "worktree.get" => { "reservation_id" => RESERVATION_ID },
      "artifact.list" => { "task_number" => "TASK-000123", "limit" => 20 },
      "publication.get" => { "publication_id" => PUBLICATION_ID },
      "task.create" => { "title" => "Repair timeout handling", "task_type" => "quick-fix" },
      "attempt.claim" => { "task_number" => "TASK-000123", "owner_id" => "orchestrator-1",
        "lease_seconds" => 300, "preconditions" => { "expected_lock_version" => 3 } },
      "attempt.renew" => { "lease_seconds" => 300, "preconditions" => preconditions },
      "attempt.fail" => { "result_manifest" => manifest("failed"), "preconditions" => preconditions },
      "attempt.needs_human" => { "result_manifest" => manifest("needs_human"), "preconditions" => preconditions },
      "attempt.reconcile" => { "attempt_id" => ATTEMPT_ID, "observed_state" => "no_effect",
        "evidence_digest" => DIGEST, "expected_lock_version" => 3 },
      "worktree.reserve" => { "task_number" => "TASK-000123", "branch" => "kos/task-TASK-000123",
        "path" => "/tmp/task-123", "preconditions" => preconditions },
      "worktree.confirm" => { "reservation_id" => RESERVATION_ID, "git_common_dir_digest" => DIGEST,
        "head_sha" => SHA, "preconditions" => preconditions },
      "worktree.reconcile" => worktree_observation, "worktree.release" => worktree_observation,
      "artifact.register" => { "task_number" => "TASK-000123", "artifact" => artifact_input,
        "preconditions" => preconditions },
      "step.complete" => { "task_number" => "TASK-000123", "to_status" => "review",
        "result_manifest" => manifest("succeeded"), "preconditions" => preconditions },
      "publication.prepare" => { "task_number" => "TASK-000123", "candidate_sha" => SHA, "remote" => "origin",
        "base_ref" => "refs/heads/main", "expected_remote_oid" => SHA, "preconditions" => preconditions },
      "publication.reconcile" => publication_reconciliation,
      "publication.complete" => { "publication_id" => PUBLICATION_ID, "task_number" => "TASK-000123",
        "to_status" => "completed", "result_manifest" => manifest("succeeded", [ publication_artifact_input ]),
        "preconditions" => preconditions }
    }
  end

  def self.worktree_observation
    { "reservation_id" => RESERVATION_ID, "observed_state" => "clean", "head_sha" => SHA,
      "evidence_digest" => DIGEST, "preconditions" => preconditions }
  end

  def self.publication_reconciliation
    { "publication_id" => PUBLICATION_ID, "candidate_sha" => SHA, "observed_remote_tip" => SHA,
      "candidate_reachable" => true, "observed_at" => "2026-09-09T12:00:00Z", "evidence_digest" => DIGEST,
      "preconditions" => preconditions }
  end

  def self.result_data
    attempt_commands = %w[attempt.get attempt.claim attempt.renew attempt.fail attempt.needs_human attempt.reconcile]
    worktree_commands = %w[worktree.get worktree.reserve worktree.confirm worktree.reconcile worktree.release]
    data = { "task_type.list" => { "task_types" => [ task_type ] }, "workflow.list" => { "workflows" => [ workflow ] },
      "workflow.get" => workflow, "task.get" => task, "task.create" => task, "artifact.list" => { "artifacts" => [ artifact ] },
      "artifact.register" => artifact, "step.complete" => completion_data, "publication.get" => publication,
      "publication.prepare" => publication, "publication.reconcile" => publication("reconciled"),
      "publication.complete" => { "task" => completed_task, "artifacts" => [ publication_artifact ] } }
    attempt_commands.each { |command| data[command] = attempt }
    worktree_commands.each { |command| data[command] = worktree }
    data
  end

  def self.task_type
    { "schema_version" => "1", "id" => "quick-fix", "name" => "quick-fix", "workflow_id" => "quick-fix" }
  end

  def self.completion_data
    { "task" => task, "artifacts" => [ artifact ] }
  end

  def self.completed_task
    task.merge("status" => "completed", "workflow_status" => "completed").tap do |value|
      value.delete("active_publication_id")
    end
  end

  def self.request(command)
    request = { "schema_version" => "1", "command" => command, "repository_id" => REPOSITORY_ID,
      "body" => request_bodies.fetch(command) }
    request
  end

  def self.result(command)
    { "schema_version" => "1", "request_id" => REQUEST_ID, "command" => command,
      "data" => result_data.fetch(command) }
  end

  def self.definition(name)
    schema = JSONSchemer.schema(SCHEMAS.fetch("commands.json"), ref_resolver: REGISTRY.to_proc)
    schema.ref("#/$defs/#{name}")
  end

  def self.artifact_input_definition
    schema = JSONSchemer.schema(SCHEMAS.fetch("artifacts.json"), ref_resolver: REGISTRY.to_proc)
    schema.ref("#/$defs/artifact_input")
  end

  def self.requested_effect_definition
    schema = JSONSchemer.schema(SCHEMAS.fetch("workflow.json"), ref_resolver: REGISTRY.to_proc)
    schema.ref("#/$defs/requested_effect")
  end

  def self.task_definition
    schema = JSONSchemer.schema(SCHEMAS.fetch("resources.json"), ref_resolver: REGISTRY.to_proc)
    schema.ref("#/$defs/task")
  end

  def self.commit_effect
    { "operation" => "commit", "reservation_id" => RESERVATION_ID, "expected_head_sha" => SHA,
      "expected_diff_digest" => DIGEST, "expected_index_digest" => DIGEST,
      "paths" => [ "app/models/task.rb" ], "message" => "Implement task", "task_number" => "TASK-000123" }
  end

  def self.contains_key?(value, key)
    return value.any? { |child| contains_key?(child, key) } if value.is_a?(Array)
    return false unless value.is_a?(Hash)

    value.key?(key) || value.values.any? { |child| contains_key?(child, key) }
  end

  def self.error_pairs
    branches = SCHEMAS.fetch("envelopes.json").dig("$defs", "error", "allOf", 1, "oneOf")
    branches.flat_map do |branch|
      properties = branch.fetch("properties")
      Array(properties.dig("code", "enum") || properties.dig("code", "const")).map do |code|
        [ properties.dig("category", "const"), code ]
      end
    end
  end

  def self.resolve_reference(root, reference)
    uri = URI.join(root.fetch("$id"), reference)
    document_uri = uri.dup
    document_uri.fragment = nil
    target = REGISTRY.fetch(document_uri)
    return target unless uri.fragment

    uri.fragment.delete_prefix("/").split("/").reduce(target) do |value, token|
      value.fetch(token.gsub("~1", "/").gsub("~0", "~"))
    end
  end

  def self.without_precondition(command, precondition)
    request = Marshal.load(Marshal.dump(request(command)))
    body = request.fetch("body")
    values = body["preconditions"] || body
    keys = { "lock" => "expected_lock_version", "attempt" => "attempt_id", "fencing" => "fencing_token" }
    values.delete(keys.fetch(precondition))
    request
  end

  def self.precondition_classes(entry)
    return [] unless entry.fetch("mutation")

    body = request(entry.fetch("identifier")).fetch("body")
    classes = [ "idempotency" ]
    classes << "lock" if contains_key?(body, "expected_lock_version")
    classes << "attempt" if contains_key?(body, "attempt_id")
    classes << "fencing" if contains_key?(body, "fencing_token")
    classes
  end

  def self.valid_error_transport?(entry)
    exits = { "validation" => 2, "authentication" => 3, "authorization" => 4, "not_found" => 5,
      "conflict" => 6, "lease_lost" => 7, "transient" => 8, "internal" => 1 }
    statuses = { "validation" => 400, "authentication" => 401, "authorization" => 403, "not_found" => 404,
      "conflict" => 409, "lease_lost" => 409, "internal" => 500 }
    status = if entry["code"] == "invalid_artifact"
      422
    elsif entry["category"] == "transient"
      entry["code"] == "request_timeout" ? 504 : 503
    else
      statuses.fetch(entry["category"])
    end
    entry["cli_exit"] == exits.fetch(entry["category"]) && entry["http_status"] == status
  end

  def self.invalid_catalog_precondition_requests
    SCHEMAS.fetch("catalog.json").fetch("x-command-catalog").flat_map do |entry|
      entry.fetch("required_preconditions").grep_v("idempotency").map do |precondition|
        without_precondition(entry.fetch("identifier"), precondition)
      end
    end
  end

  ARTIFACT_EXAMPLES = artifact_examples
end

RSpec.describe CliV1Contract do
  it "parses at least one schema" do
    expect(described_class::SCHEMAS).not_to be_empty
  end

  it "validates every schema against its metaschema" do
    expect(described_class::SCHEMAS.values).to all(satisfy { |schema| JSONSchemer.valid_schema?(schema) })
  end

  it "declares draft 2020-12 for every schema" do
    dialects = described_class::SCHEMAS.values.map { |schema| schema.fetch("$schema") }

    expect(dialects).to all(eq("https://json-schema.org/draft/2020-12/schema"))
  end

  it "uses unique versioned identifiers" do
    identifiers = described_class::SCHEMAS.values.map { |schema| schema.fetch("$id") }

    expect(identifiers.uniq).to eq(identifiers).and all(include("/schemas/cli/v1/"))
  end

  it "uses only local relative references" do
    references = described_class::SCHEMAS.values.flat_map { |schema| described_class.references(schema) }

    expect(references).to all(satisfy { |ref| ref.start_with?("#") || ref.match?(/\A[a-z_]+\.json#/) })
  end

  it "resolves every reference document and fragment locally" do
    references = described_class::SCHEMAS.flat_map do |_name, schema|
      described_class.references(schema).map { |reference| [ schema, reference ] }
    end

    expect { references.each { |root, reference| described_class.resolve_reference(root, reference) } }.not_to raise_error
  end

  %w[valid invalid].each do |validity|
    path = File.join(CliV1Contract::FIXTURE_DIRECTORY, "#{validity}.json")

    JSON.parse(File.read(path)).each do |fixture|
      it "#{validity == 'valid' ? 'accepts' : 'rejects'} #{fixture.fetch('name')}" do
        root = described_class::SCHEMAS.fetch(fixture.fetch("schema"))
        schema = JSONSchemer.schema(root, ref_resolver: described_class::REGISTRY.to_proc)
        definition = schema.ref("#/$defs/#{fixture.fetch('definition')}")

        expect(definition.valid?(fixture.fetch("instance"))).to eq(validity == "valid")
      end
    end
  end

  CliV1Contract::EXPECTED_COMMANDS.each do |command|
    it "validates the #{command} request" do
      expect(described_class.definition("request")).to be_valid(described_class.request(command))
    end

    it "validates the #{command} result" do
      expect(described_class.definition("result")).to be_valid(described_class.result(command))
    end
  end

  it "rejects publication completion data without a publication artifact" do
    result = described_class.result("publication.complete")
    result.fetch("data")["artifacts"] = [ described_class.artifact ]

    expect(described_class.definition("result")).not_to be_valid(result)
  end

  it "rejects an active publication on a completed task" do
    completed_task = described_class.completed_task.merge("active_publication_id" => described_class::PUBLICATION_ID)

    expect(described_class.task_definition).not_to be_valid(completed_task)
  end

  it "accepts both exact review state and verdict pairs" do
    metadata = described_class::ARTIFACT_EXAMPLES.fetch("review").last
    artifact = described_class.artifact_with("review", "changes_requested", metadata.merge("verdict" => "changes_requested"))

    expect(described_class.artifact_input_definition).to be_valid(artifact)
  end

  it "rejects changes requested state with approved verdict" do
    metadata = described_class::ARTIFACT_EXAMPLES.fetch("review").last
    artifact = described_class.artifact_with("review", "changes_requested", metadata)

    expect(described_class.artifact_input_definition).not_to be_valid(artifact)
  end

  it "accepts failed tests with nonzero exit" do
    metadata = described_class::ARTIFACT_EXAMPLES.fetch("test").last.merge("exit_code" => 1)

    expect(described_class.artifact_input_definition)
      .to be_valid(described_class.artifact_with("test", "failed", metadata))
  end

  CliV1Contract::ARTIFACT_EXAMPLES.each do |type, (valid_state, invalid_state, metadata)|
    it "accepts the compatible #{type} artifact state" do
      expect(described_class.artifact_input_definition)
        .to be_valid(described_class.artifact_with(type, valid_state, metadata))
    end

    it "rejects an incompatible #{type} artifact state" do
      expect(described_class.artifact_input_definition)
        .not_to be_valid(described_class.artifact_with(type, invalid_state, metadata))
    end
  end

  { "attempt.fail" => "needs_human", "attempt.needs_human" => "failed" }.each do |command, wrong_outcome|
    it "rejects #{wrong_outcome} for #{command}" do
      request = described_class.request(command)
      request.fetch("body").fetch("result_manifest")["outcome"] = wrong_outcome

      expect(described_class.definition("request")).not_to be_valid(request)
    end
  end

  it "rejects a non-successful step completion" do
    request = described_class.request("step.complete")
    request.fetch("body").fetch("result_manifest")["outcome"] = "failed"

    expect(described_class.definition("request")).not_to be_valid(request)
  end

  it "publishes the complete operational command identifier set" do
    actual = described_class::SCHEMAS.fetch("commands.json").dig("$defs", "command_identifier", "enum")

    expect(actual).to match_array(described_class::EXPECTED_COMMANDS)
  end

  it "defines request and result dispatch for every command" do
    definitions = described_class::SCHEMAS.fetch("commands.json").fetch("$defs")
    request_commands = described_class.dispatched_commands(definitions.values_at("read_request", "mutation_request"))
    result_commands = described_class.dispatched_commands(definitions.fetch("result"))

    expect(request_commands.uniq).to match_array(described_class::EXPECTED_COMMANDS)
      .and match_array(result_commands.uniq)
  end

  it "publishes the stable error categories" do
    categories = described_class::SCHEMAS.fetch("envelopes.json").dig("$defs", "error_category", "enum")

    expect(categories).to match_array(%w[validation authentication authorization conflict lease_lost not_found transient internal])
  end

  it "publishes acceptance-criteria error leaf codes" do
    codes = described_class::SCHEMAS.fetch("envelopes.json").dig("$defs", "error_code", "enum")

    expect(codes).to include("malformed_input", "unsupported_schema_version", "authentication_required", "forbidden",
      "stale_lock_version", "lease_expired", "idempotency_conflict", "invalid_transition", "invalid_artifact",
      "idempotency_in_progress", "base_moved", "transport_unavailable", "internal_error")
  end


  it "makes the catalog command set exactly match the command enum" do
    catalog = described_class::SCHEMAS.fetch("catalog.json").fetch("x-command-catalog")

    expect(catalog.map { |entry| entry.fetch("identifier") }).to match_array(described_class::EXPECTED_COMMANDS)
  end

  it "validates every command catalog entry" do
    root = described_class::SCHEMAS.fetch("catalog.json")
    schema = JSONSchemer.schema(root, ref_resolver: described_class::REGISTRY.to_proc).ref("#/$defs/command_entry")

    expect(root.fetch("x-command-catalog")).to all(satisfy { |entry| schema.valid?(entry) })
  end

  it "defines zero as the success exit for every command" do
    expect(described_class::SCHEMAS.fetch("catalog.json").fetch("x-success-cli-exit")).to eq(0)
  end

  it "requires safe commit preconditions" do
    %w[expected_diff_digest expected_index_digest paths message task_number].each do |field|
      expect(described_class.requested_effect_definition).not_to be_valid(described_class.commit_effect.except(field))
    end
  end

  it "aligns catalog precondition classes with valid request schemas" do
    catalog = described_class::SCHEMAS.fetch("catalog.json").fetch("x-command-catalog")

    expect(catalog).to all(satisfy do |entry|
      entry.fetch("required_preconditions").sort == described_class.precondition_classes(entry).sort
    end)
  end

  it "requires every cataloged JSON precondition in its command schema" do
    invalid_requests = described_class.invalid_catalog_precondition_requests

    expect(invalid_requests).to all(satisfy { |request| !described_class.definition("request").valid?(request) })
  end

  it "keeps idempotency out of JSON requests" do
    requests = described_class::EXPECTED_COMMANDS.map { |command| described_class.request(command) }

    expect(requests).to all(satisfy { |request| !described_class.contains_key?(request, "idempotency_key") })
  end

  it "contracts the idempotency header value" do
    common = JSONSchemer.schema(described_class::SCHEMAS.fetch("common.json"))

    expect(common.ref("#/$defs/idempotency_key")).to be_valid("task.create:request-1")
  end

  it "makes the catalog error pairs exactly match the error schema" do
    catalog = described_class::SCHEMAS.fetch("catalog.json").fetch("x-error-catalog")

    expect(catalog.map { |entry| entry.values_at("category", "code") }).to match_array(described_class.error_pairs)
  end

  it "lists every error leaf code exactly once" do
    catalog = described_class::SCHEMAS.fetch("catalog.json").fetch("x-error-catalog")

    expect(catalog.map { |entry| entry.fetch("code") }.uniq.length).to eq(catalog.length)
  end

  it "validates every error catalog entry" do
    root = described_class::SCHEMAS.fetch("catalog.json")
    schema = JSONSchemer.schema(root, ref_resolver: described_class::REGISTRY.to_proc).ref("#/$defs/error_entry")

    expect(root.fetch("x-error-catalog")).to all(satisfy { |entry| schema.valid?(entry) })
  end

  it "uses the stable CLI exits and HTTP statuses" do
    entries = described_class::SCHEMAS.fetch("catalog.json").fetch("x-error-catalog")

    expect(entries).to all(satisfy { |entry| described_class.valid_error_transport?(entry) })
  end

  it "marks only transient catalog errors retryable" do
    entries = described_class::SCHEMAS.fetch("catalog.json").fetch("x-error-catalog")

    expect(entries).to all(satisfy { |entry| entry.fetch("retryable") == (entry.fetch("category") == "transient") })
  end
end
