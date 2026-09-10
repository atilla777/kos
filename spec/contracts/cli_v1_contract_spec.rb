require "digest"
require "json"
require "json_schemer"
require "spec_helper"

module CliV1Contract
  SCHEMA_DIRECTORY = File.expand_path("../../schemas/cli/v1", __dir__)
  RUNTIME_SCHEMA_PATH = File.expand_path("../../schemas/runtime/v1/retrospective.json", __dir__)
  WORKFLOW_FIXTURE = File.expand_path("../fixtures/workflow_definitions/v1/valid/quick-fix.json", __dir__)
  INVALID_WORKFLOW_FIXTURES = File.expand_path("../fixtures/workflow_definitions/v1/invalid/*.json", __dir__)
  INVALID_WORKFLOW_CASES = Dir[INVALID_WORKFLOW_FIXTURES].sort.map do |path|
    [ File.basename(path), JSON.parse(File.read(path)) ]
  end.freeze
  CLI_FIXTURE_DIRECTORY = File.expand_path("../fixtures/cli/v1", __dir__)
  CLI_FIXTURES = %w[valid invalid].to_h do |validity|
    [ validity, JSON.parse(File.read(File.join(CLI_FIXTURE_DIRECTORY, "#{validity}.json"))) ]
  end.freeze
  SCHEMAS = Dir[File.join(SCHEMA_DIRECTORY, "*.json")].sort.to_h do |path|
    [ File.basename(path), JSON.parse(File.read(path)) ]
  end
  REGISTRY = SCHEMAS.values.to_h { |schema| [ URI(schema.fetch("$id")), schema ] }
  EXPECTED_COMMANDS = %w[
    repository.register runtime_config.get runtime_config.update task_type.list workflow.list workflow.get workflow.export
    workflow_draft.get workflow_draft.import workflow_draft.validate workflow.publish workflow.activate task.get attempt.get
    step.context worktree.get effect.get artifact.list publication.get task.create attempt.claim attempt.renew attempt.fail
    attempt.needs_human attempt.reconcile worktree.reserve worktree.confirm worktree.reconcile worktree.release
    effect.prepare effect.reconcile artifact.register step.complete publication.prepare publication.reconcile
    publication.complete
  ].freeze
  GLOBAL_COMMANDS = %w[
    runtime_config.get runtime_config.update task_type.list workflow.list workflow.get workflow.export workflow_draft.get
    workflow_draft.import workflow_draft.validate workflow.publish workflow.activate
  ].freeze
  REQUEST_ID = "99999999-9999-4999-8999-999999999999"
  REPOSITORY_ID = "33333333-3333-4333-8333-333333333333"
  TASK_ID = "11111111-1111-4111-8111-111111111111"
  ATTEMPT_ID = "22222222-2222-4222-8222-222222222222"
  WORKFLOW_VERSION_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  DRAFT_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
  RESERVATION_ID = "55555555-5555-4555-8555-555555555555"
  PUBLICATION_ID = "44444444-4444-4444-8444-444444444444"
  EFFECT_ID = "77777777-7777-4777-8777-777777777777"
  DIGEST = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  SHA = "1111111111111111111111111111111111111111"

  module_function

  def definition(schema_name, definition_name)
    JSONSchemer.schema(SCHEMAS.fetch(schema_name), ref_resolver: REGISTRY.to_proc).ref("#/$defs/#{definition_name}")
  end

  def workflow_definition
    JSON.parse(File.read(WORKFLOW_FIXTURE))
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

  def workflow_content_digest
    "sha256:#{Digest::SHA256.hexdigest(canonical_json(workflow_definition))}"
  end

  def preconditions
    { "expected_lock_version" => 3, "attempt_id" => ATTEMPT_ID, "fencing_token" => 8 }
  end

  def artifact_input(type = "candidate")
    metadata = case type
    when "candidate"
      { "kind" => "candidate", "candidate_sha" => SHA, "task_trailer" => "KOS-000123" }
    when "publication"
      { "kind" => "publication", "publication_id" => PUBLICATION_ID, "candidate_sha" => SHA, "remote" => "origin",
        "base_ref" => "refs/heads/main", "observed_remote_tip" => SHA, "reachable" => true,
        "observed_at" => "2026-09-09T12:00:00Z" }
    end
    state = type == "publication" ? "published" : "produced"
    { "schema_version" => "1", "type" => type, "state" => state, "producer" => "kos-workflow-step",
      "metadata" => metadata }
  end

  def manifest(outcome, artifacts = [])
    { "schema_version" => "1", "attempt_id" => ATTEMPT_ID, "input_context_digest" => DIGEST,
      "outcome" => outcome, "artifacts" => artifacts }
  end

  def task_type
    { "schema_version" => "1", "id" => "quick-fix", "name" => "quick-fix", "workflow_id" => "quick-fix",
      "current_workflow_version_id" => WORKFLOW_VERSION_ID, "lock_version" => 2 }
  end

  def workflow_summary
    { "schema_version" => "1", "id" => WORKFLOW_VERSION_ID, "workflow_id" => "quick-fix", "task_type" => "quick-fix",
      "version" => "1.0.0", "content_digest" => workflow_content_digest,
      "published_at" => "2026-09-09T12:00:00Z" }
  end

  def workflow_version
    workflow_summary.merge("definition" => workflow_definition)
  end

  def workflow_draft
    { "schema_version" => "1", "id" => DRAFT_ID, "workflow_id" => "quick-fix", "task_type" => "quick-fix",
      "definition" => workflow_definition, "lock_version" => 3, "updated_at" => "2026-09-09T12:00:00Z" }
  end

  def runtime_config
    { "schema_version" => "1", "retrospective_enabled" => true, "lock_version" => 1,
      "updated_at" => "2026-09-09T12:00:00Z" }
  end

  def repository
    { "schema_version" => "1", "id" => REPOSITORY_ID, "git_common_dir" => "/home/user/project/.git",
      "task_prefix" => "KOS", "trusted_remote" => "origin",
      "trusted_remote_url" => "ssh://git@example.com/team/project.git", "base_ref" => "refs/heads/main",
      "registered_at" => "2026-09-09T12:00:00Z" }
  end

  def task
    { "schema_version" => "1", "id" => TASK_ID, "repository_id" => REPOSITORY_ID, "number" => "KOS-000123",
      "title" => "Repair timeout handling", "task_type" => "quick-fix", "status" => "active",
      "workflow_status" => "development", "workflow_version_id" => WORKFLOW_VERSION_ID, "lock_version" => 3,
      "active_publication_id" => PUBLICATION_ID, "created_at" => "2026-09-09T12:00:00Z",
      "updated_at" => "2026-09-09T12:01:00Z" }
  end

  def context
    value = { "schema_version" => "1", "task_id" => TASK_ID, "task_number" => "KOS-000123", "attempt_id" => ATTEMPT_ID,
      "repository_id" => REPOSITORY_ID, "workflow_version_id" => WORKFLOW_VERSION_ID, "workflow_status" => "development",
      "instruction" => "# Development\n\nImplement and test the approved change.\n", "artifact_templates" => [],
      "expected_lock_version" => 3, "fencing_token" => 8, "base_ref" => "refs/heads/main",
      "worktree" => { "reservation_id" => RESERVATION_ID, "path" => "/tmp/task-123", "branch" => "kos/task-KOS-000123",
        "head_sha" => SHA },
      "required_artifacts" => [
        { "type" => "candidate", "cardinality" => "one", "subject" => "task", "allowed_states" => [ "produced" ] },
        { "type" => "test", "cardinality" => "many", "subject" => "candidate", "allowed_states" => [ "passed" ] }
      ], "allowed_repository_effects" => [ "commit" ], "retrospective_enabled" => true }
    value.merge("input_context_digest" => "sha256:#{Digest::SHA256.hexdigest(canonical_json(value))}")
  end

  def attempt(state = "started")
    value = { "schema_version" => "1", "id" => ATTEMPT_ID, "task_id" => TASK_ID, "workflow_status" => "development",
      "owner_id" => "orchestrator-1", "state" => state, "fencing_token" => 8,
      "started_at" => "2026-09-09T12:00:00Z" }
    return value if state == "started"
    return value.merge("completed_at" => "2026-09-09T12:01:00Z") if state == "interrupted"

    outcome = state == "needs_human" ? "needs_human" : state
    value.merge("completed_at" => "2026-09-09T12:01:00Z", "input_context_digest" => DIGEST,
      "result_manifest" => manifest(outcome))
  end

  def worktree
    { "schema_version" => "1", "id" => RESERVATION_ID, "repository_id" => REPOSITORY_ID, "task_id" => TASK_ID,
      "attempt_id" => ATTEMPT_ID, "branch" => "kos/task-KOS-000123", "path" => "/tmp/task-123", "state" => "confirmed",
      "fencing_token" => 8, "created_at" => "2026-09-09T12:00:00Z" }
  end

  def publication(state = "prepared")
    value = { "schema_version" => "1", "id" => PUBLICATION_ID, "repository_id" => REPOSITORY_ID, "task_id" => TASK_ID,
      "prepared_attempt_id" => ATTEMPT_ID, "current_owner_attempt_id" => ATTEMPT_ID, "candidate_sha" => SHA,
      "remote" => "origin", "base_ref" => "refs/heads/main", "expected_remote_oid" => SHA, "state" => state,
      "prepared_at" => "2026-09-09T12:00:00Z", "updated_at" => "2026-09-09T12:01:00Z" }
    if %w[reconciled superseded completed].include?(state)
      value.merge!("observed_remote_tip" => SHA, "candidate_reachable" => state != "superseded",
        "observation_digest" => DIGEST, "observed_at" => "2026-09-09T12:01:00Z",
        "reconciled_at" => "2026-09-09T12:01:00Z")
    end
    value["completed_at"] = "2026-09-09T12:02:00Z" if state == "completed"
    value
  end

  def artifact(input = artifact_input)
    input.merge("id" => "66666666-6666-4666-8666-666666666666", "task_id" => TASK_ID,
      "attempt_id" => ATTEMPT_ID, "created_at" => "2026-09-09T12:00:00Z")
  end

  def request_bodies
    {
      "repository.register" => { "git_common_dir" => "/home/user/project/.git", "task_prefix" => "KOS",
        "trusted_remote" => "origin", "trusted_remote_url" => "ssh://git@example.com/team/project.git",
        "base_ref" => "refs/heads/main" },
      "runtime_config.get" => {},
      "runtime_config.update" => { "retrospective_enabled" => true, "expected_lock_version" => 0 },
      "task_type.list" => { "limit" => 20 }, "workflow.list" => { "limit" => 20 },
      "workflow.get" => { "workflow_version_id" => WORKFLOW_VERSION_ID },
      "workflow.export" => { "workflow_version_id" => WORKFLOW_VERSION_ID },
      "workflow_draft.get" => { "workflow_id" => "quick-fix" },
      "workflow_draft.import" => { "workflow_id" => "quick-fix", "definition" => workflow_definition,
        "expected_lock_version" => 3 },
      "workflow_draft.validate" => { "workflow_id" => "quick-fix" },
      "workflow.publish" => { "workflow_id" => "quick-fix", "expected_lock_version" => 3 },
      "workflow.activate" => { "task_type" => "quick-fix", "workflow_version_id" => WORKFLOW_VERSION_ID,
        "expected_lock_version" => 2 },
      "task.get" => { "task_number" => "KOS-000123" }, "attempt.get" => { "attempt_id" => ATTEMPT_ID },
      "step.context" => { "preconditions" => preconditions }, "worktree.get" => { "reservation_id" => RESERVATION_ID },
      "effect.get" => { "effect_id" => EFFECT_ID },
      "artifact.list" => { "task_number" => "KOS-000123", "limit" => 20 },
      "publication.get" => { "publication_id" => PUBLICATION_ID },
      "task.create" => { "title" => "Repair timeout handling", "task_type" => "quick-fix" },
      "attempt.claim" => { "task_number" => "KOS-000123", "owner_id" => "orchestrator-1", "lease_seconds" => 300,
        "preconditions" => { "expected_lock_version" => 3 } },
      "attempt.renew" => { "lease_seconds" => 300, "preconditions" => preconditions },
      "attempt.fail" => { "result_manifest" => manifest("failed"), "preconditions" => preconditions },
      "attempt.needs_human" => { "result_manifest" => manifest("needs_human"), "preconditions" => preconditions },
      "attempt.reconcile" => { "attempt_id" => ATTEMPT_ID, "observed_state" => "no_effect", "evidence_digest" => DIGEST,
        "expected_lock_version" => 3 },
      "worktree.reserve" => { "task_number" => "KOS-000123", "branch" => "kos/task-KOS-000123",
        "path" => "/tmp/task-123", "preconditions" => preconditions },
      "worktree.confirm" => { "reservation_id" => RESERVATION_ID, "git_common_dir_digest" => DIGEST,
        "head_sha" => SHA, "preconditions" => preconditions },
      "worktree.reconcile" => worktree_observation, "worktree.release" => worktree_observation,
      "effect.prepare" => { "task_number" => "KOS-000123", "effect_request" => effect_round_trip.first,
        "preconditions" => preconditions },
      "effect.reconcile" => { "effect_id" => EFFECT_ID, "effect_result" => effect_round_trip.last,
        "preconditions" => preconditions },
      "artifact.register" => { "task_number" => "KOS-000123", "artifact" => artifact_input, "preconditions" => preconditions },
      "step.complete" => { "task_number" => "KOS-000123", "to_status" => "review",
        "result_manifest" => manifest("succeeded"), "preconditions" => preconditions },
      "publication.prepare" => { "task_number" => "KOS-000123", "candidate_sha" => SHA, "remote" => "origin",
        "base_ref" => "refs/heads/main", "expected_remote_oid" => SHA, "preconditions" => preconditions },
      "publication.reconcile" => publication_reconciliation,
      "publication.complete" => { "publication_id" => PUBLICATION_ID, "task_number" => "KOS-000123",
        "to_status" => "completed", "result_manifest" => manifest("succeeded", [ artifact_input("publication") ]),
        "preconditions" => preconditions }
    }
  end

  def worktree_observation
    { "reservation_id" => RESERVATION_ID, "observed_state" => "clean", "head_sha" => SHA,
      "evidence_digest" => DIGEST, "preconditions" => preconditions }
  end

  def publication_reconciliation
    { "publication_id" => PUBLICATION_ID, "candidate_sha" => SHA, "observed_remote_tip" => SHA,
      "candidate_reachable" => true, "observed_at" => "2026-09-09T12:00:00Z", "evidence_digest" => DIGEST,
      "preconditions" => preconditions }
  end

  def result_data
    completed_task = task.merge("status" => "completed", "workflow_status" => "completed").except("active_publication_id")
    data = {
      "repository.register" => repository, "runtime_config.get" => runtime_config,
      "runtime_config.update" => runtime_config, "task_type.list" => { "task_types" => [ task_type ] },
      "workflow.list" => { "workflows" => [ workflow_summary ] }, "workflow.get" => workflow_version,
      "workflow.export" => workflow_definition, "workflow_draft.get" => workflow_draft,
      "workflow_draft.import" => workflow_draft, "workflow_draft.validate" => { "valid" => true, "errors" => [] },
      "workflow.publish" => workflow_version, "workflow.activate" => task_type, "task.get" => task,
      "task.create" => task, "step.context" => context, "worktree.get" => worktree,
      "effect.get" => repository_effect, "effect.prepare" => repository_effect,
      "effect.reconcile" => repository_effect("succeeded"),
      "artifact.list" => { "artifacts" => [ artifact ] }, "artifact.register" => artifact,
      "step.complete" => { "task" => task, "artifacts" => [ artifact ] }, "publication.get" => publication,
      "publication.prepare" => publication, "publication.reconcile" => publication("reconciled"),
      "publication.complete" => { "task" => completed_task, "artifacts" => [ artifact(artifact_input("publication")) ] }
    }
    %w[attempt.get attempt.claim attempt.renew attempt.reconcile].each { |command| data[command] = attempt }
    data["attempt.fail"] = attempt("failed")
    data["attempt.needs_human"] = attempt("needs_human")
    %w[worktree.reserve worktree.confirm worktree.reconcile worktree.release].each { |command| data[command] = worktree }
    data
  end

  def request(command)
    value = { "schema_version" => "1", "command" => command, "body" => request_bodies.fetch(command) }
    value["repository_id"] = REPOSITORY_ID unless GLOBAL_COMMANDS.include?(command) || command == "repository.register"
    value
  end

  def result(command)
    { "schema_version" => "1", "request_id" => REQUEST_ID, "command" => command, "data" => result_data.fetch(command) }
  end

  def references(value)
    case value
    when Hash then value.flat_map { |key, child| (key == "$ref" ? [ child ] : []) + references(child) }
    when Array then value.flat_map { |child| references(child) }
    else []
    end
  end

  def resolve_reference(root, reference)
    uri = URI.join(root.fetch("$id"), reference)
    document_uri = uri.dup
    document_uri.fragment = nil
    target = REGISTRY.fetch(document_uri)
    return target unless uri.fragment

    uri.fragment.delete_prefix("/").split("/").reduce(target) do |value, token|
      value.fetch(token.gsub("~1", "/").gsub("~0", "~"))
    end
  end

  def dispatched_commands(value)
    return [] unless value.is_a?(Hash) || value.is_a?(Array)
    return value.flat_map { |child| dispatched_commands(child) } if value.is_a?(Array)

    command = value.dig("properties", "command")
    own = command ? Array(command["const"] || command["enum"]) : []
    own + value.values.flat_map { |child| dispatched_commands(child) }
  end

  def graph_errors(definition)
    statuses = definition.fetch("statuses")
    status_ids = statuses.map { |status| status.fetch("id") }
    initial = definition.fetch("initial_status")
    terminal = definition.fetch("terminal_status")
    known = status_ids + [ terminal ]
    transitions = definition.fetch("transitions")
    errors = []
    errors << "duplicate_status" unless status_ids.uniq == status_ids
    errors << "initial_not_executable" unless status_ids.include?(initial)
    errors << "terminal_executable" if status_ids.include?(terminal)
    errors << "unknown_endpoint" unless transitions.all? { |edge| known.include?(edge.fetch("from")) && known.include?(edge.fetch("to")) }
    errors << "terminal_outgoing" if transitions.any? { |edge| edge.fetch("from") == terminal }
    edge_pairs = transitions.map { |edge| edge.values_at("from", "to") }
    errors << "duplicate_edge" unless edge_pairs.uniq == edge_pairs
    errors << "missing_outgoing" unless status_ids.all? { |id| transitions.any? { |edge| edge.fetch("from") == id } }
    reachable = [ initial ]
    reachable << transitions.find { |edge| reachable.include?(edge.fetch("from")) && !reachable.include?(edge.fetch("to")) }
      &.fetch("to") while transitions.any? { |edge| reachable.include?(edge.fetch("from")) && !reachable.include?(edge.fetch("to")) }
    errors << "unreachable_status" unless (known - reachable).empty?
    errors << "worktree_required" if statuses.any? do |status|
      status.fetch("repository_changes") == "allowed" && status.fetch("worktree") != "required"
    end
    errors << "effect_policy" if statuses.any? do |status|
      status.fetch("repository_changes") == "forbidden" &&
        (status.fetch("allowed_repository_effects") & %w[commit rebase]).any?
    end
    transitions.each do |edge|
      conditions = edge.fetch("conditions")
      errors << "always_not_sole" if conditions.any? { |item| item.fetch("type") == "always" } && conditions.length != 1
      artifact_keys = conditions.filter_map do |condition|
        condition["artifact_type"] if %w[artifact-present artifact-state not-applicable].include?(condition.fetch("type"))
      end
      errors << "duplicate_artifact_condition" unless artifact_keys.uniq == artifact_keys
      decision_keys = conditions.select { |condition| condition.fetch("type") == "decision" }
        .map { |condition| condition.fetch("decision") }
      errors << "duplicate_edge_decision" unless decision_keys.uniq == decision_keys
      source = statuses.find { |status| status.fetch("id") == edge.fetch("from") }
      next unless source

      requirements = source.fetch("required_artifacts").to_h { |requirement| [ requirement.fetch("type"), requirement ] }
      artifact_conditions = edge.fetch("conditions").select do |condition|
        %w[artifact-present artifact-state not-applicable].include?(condition.fetch("type"))
      end
      errors << "artifact_evidence_missing" unless (requirements.keys - artifact_conditions.map { |item| item["artifact_type"] }).empty?
      edge.fetch("conditions").each do |condition|
        next unless %w[artifact-present artifact-state not-applicable].include?(condition.fetch("type"))

        errors << "artifact_condition" unless requirements.key?(condition.fetch("artifact_type"))
        requirement = requirements[condition.fetch("artifact_type")]
        if condition.fetch("type") == "artifact-state" && requirement &&
            !requirement.fetch("allowed_states").include?(condition.fetch("state"))
          errors << "artifact_state"
        end
      end
    end
    statuses.each do |status|
      outgoing = transitions.select { |edge| edge.fetch("from") == status.fetch("id") }
      decisions = outgoing.flat_map do |edge|
        edge.fetch("conditions").select { |condition| condition.fetch("type") == "decision" }
          .map { |condition| condition.values_at("decision", "value") }
      end
      errors << "ambiguous_decision" unless decisions.uniq == decisions
      status.fetch("required_artifacts").each do |requirement|
        routed_states = outgoing.flat_map do |edge|
          conditions = edge.fetch("conditions").select do |condition|
            condition["artifact_type"] == requirement.fetch("type")
          end
          states = conditions.select { |condition| condition.fetch("type") == "artifact-state" }
            .map { |condition| condition.fetch("state") }
          states.concat(requirement.fetch("allowed_states")) if conditions.any? do |condition|
            condition.fetch("type") == "artifact-present"
          end
          states
        end
        errors << "artifact_state_uncovered" unless (requirement.fetch("allowed_states") - routed_states).empty?
      end
    end
    errors.uniq
  end

  def mutated_workflow(kind)
    value = Marshal.load(Marshal.dump(workflow_definition))
    case kind
    when "duplicate_state"
      value.fetch("statuses") << value.fetch("statuses").first
    when "unknown_endpoint"
      value.fetch("transitions").first["to"] = "missing"
    when "inconsistent_artifact"
      value.fetch("transitions").first.fetch("conditions").first["artifact_type"] = "review"
    when "changes_without_worktree"
      value.fetch("statuses").first["worktree"] = "none"
    when "terminal_outgoing"
      value.fetch("transitions") << { "from" => "completed", "to" => "implementation-planning",
        "conditions" => [ { "type" => "always" } ] }
    when "duplicate_edge"
      value.fetch("transitions") << value.fetch("transitions").first
    when "unreachable_status"
      value.fetch("transitions").delete_if { |edge| edge.fetch("to") == "publication" }
    when "always_with_condition"
      value.fetch("transitions").first["conditions"] = [ { "type" => "always" },
        { "type" => "decision", "decision" => "ready", "value" => "yes" } ]
    when "duplicate_artifact_condition"
      value.fetch("transitions").first.fetch("conditions") << { "type" => "artifact-state",
        "artifact_type" => "document", "state" => "produced" }
    when "duplicate_edge_decision"
      value.fetch("transitions").first["conditions"] = [
        { "type" => "decision", "decision" => "ready", "value" => "yes" },
        { "type" => "decision", "decision" => "ready", "value" => "no" }
      ]
    end
    value
  end

  def retrospective_schema
    JSONSchemer.schema(JSON.parse(File.read(RUNTIME_SCHEMA_PATH)))
  end

  def schema_identity_contract
    identifiers = SCHEMAS.values.map { |schema| schema.fetch("$id") }
    references = SCHEMAS.values.flat_map { |schema| references(schema) }
    [ identifiers.uniq == identifiers, identifiers.all? { |id| id.include?("/schemas/cli/v1/") },
      references.all? { |ref| ref.start_with?("#") || ref.match?(/\A[a-z_]+\.json#/) } ]
  end

  def workflow_content_contract
    serialized = JSON.generate(workflow_definition)
    [ %w[instruction artifact_templates allowed_repository_effects].all? { |key| serialized.include?(key) },
      %w[.kos materials allowed_capabilities].none? { |key| serialized.include?(key) } ]
  end

  def document_artifact
    { "schema_version" => "1", "type" => "document", "state" => "produced", "producer" => "kos-workflow-step",
      "metadata" => { "kind" => "document", "path" => "tasks/KOS-000123/task.md", "commit_sha" => SHA,
        "content_digest" => DIGEST } }
  end

  def request_dispatch_commands
    definitions = SCHEMAS.fetch("commands.json").fetch("$defs")
    dispatched_commands(definitions.values_at("repository_registration_request", "global_read_request",
      "global_mutation_request", "scoped_read_request", "scoped_mutation_request")).uniq
  end

  def global_scope_contract
    schema = definition("commands.json", "request")
    global = request("workflow.publish")
    scoped = request("task.create")
    [ global.key?("repository_id"), scoped.key?("repository_id"),
      schema.valid?(global.merge("repository_id" => REPOSITORY_ID)), schema.valid?(scoped.except("repository_id")) ]
  end

  def task_pinning_contract
    value = task
    [ definition("resources.json", "task").valid?(value), value["workflow_version_id"],
      value.keys.grep(/bundle_digest|workflow_version\z/) ]
  end

  def terminal_attempt_contract
    schema = definition("resources.json", "attempt")
    succeeded = attempt("succeeded")
    [ succeeded, succeeded.except("input_context_digest"), succeeded.merge("state" => "failed") ]
      .map { |value| schema.valid?(value) }
  end

  def commit_boundary_contract
    effect = { "operation" => "commit", "reservation_id" => RESERVATION_ID, "expected_head_sha" => SHA,
      "expected_diff_digest" => DIGEST, "expected_index_digest" => DIGEST, "paths" => [ "app/models/task.rb" ],
      "message" => "Implement task", "task_number" => "KOS-000123" }
    schema = definition("workflow.json", "requested_effect")
    missing = %w[expected_diff_digest expected_index_digest paths message task_number]
    [ schema.valid?(effect), missing.map { |field| schema.valid?(effect.except(field)) } ]
  end

  def retrospective_examples
    no_action = { "schema_version" => "1", "session_id" => ATTEMPT_ID, "source" => "workflow_step",
      "primary_result_acknowledged" => true,
      "outcome" => "no_action", "proposals" => [] }
    proposal = { "schema_version" => "1", "session_id" => ATTEMPT_ID, "source" => "workflow_step",
      "primary_result_acknowledged" => true,
      "outcome" => "proposals", "proposals" => [
        { "category" => "workflow", "problem" => "Review instruction was ambiguous",
          "observed_impact" => "The reviewer repeated discovery work", "sanitized_evidence" => "The scope was unclear",
          "proposed_outcome" => "Clarify the shared review instruction", "workflow_version_id" => WORKFLOW_VERSION_ID,
          "suggested_task_type" => "quick-fix", "uncertainties" => [] }
      ] }
    [ no_action, proposal ]
  end

  def catalog_contract
    catalog = SCHEMAS.fetch("catalog.json").fetch("x-command-catalog")
    schema = definition("catalog.json", "command_entry")
    globals = catalog.select { |entry| entry.fetch("scope") == "global" }.map { |entry| entry.fetch("identifier") }
    [ catalog.map { |entry| entry.fetch("identifier") }.sort, catalog.all? { |entry| schema.valid?(entry) }, globals.sort ]
  end

  def error_catalog_contract
    catalog = SCHEMAS.fetch("catalog.json").fetch("x-error-catalog")
    branches = SCHEMAS.fetch("envelopes.json").dig("$defs", "error", "allOf", 1, "oneOf")
    pairs = branches.flat_map do |branch|
      category = branch.dig("properties", "category", "const")
      Array(branch.dig("properties", "code", "enum") || branch.dig("properties", "code", "const"))
        .map { |code| [ category, code ] }
    end
    [ catalog.map { |entry| entry.values_at("category", "code") }.sort, pairs.sort,
      catalog.map { |entry| entry.fetch("code") }.uniq.length == catalog.length ]
  end

  def nested_value(value, path)
    path.split(".").reduce(value) { |current, key| current.fetch(key) }
  end

  def workflow_resource_binding_errors(value, definition_name)
    schema = SCHEMAS.fetch("resources.json").dig("$defs", definition_name)
    errors = schema.fetch("x-field-equality").filter_map do |left, right|
      left unless nested_value(value, left) == nested_value(value, right)
    end
    if schema["x-content-digest-of"]
      expected = "sha256:#{Digest::SHA256.hexdigest(canonical_json(value.fetch(schema.fetch('x-content-digest-of'))))}"
      errors << "content_digest" unless value.fetch("content_digest") == expected
    end
    errors
  end

  def contains_key?(value, key)
    return value.any? { |child| contains_key?(child, key) } if value.is_a?(Array)
    return false unless value.is_a?(Hash)

    value.key?(key) || value.values.any? { |child| contains_key?(child, key) }
  end

  def catalog_precondition_contract
    SCHEMAS.fetch("catalog.json").fetch("x-command-catalog").map do |entry|
      body = request(entry.fetch("identifier")).fetch("body")
      actual = entry.fetch("mutation") ? [ "idempotency" ] : []
      if entry.fetch("mutation")
        actual << "lock" if contains_key?(body, "expected_lock_version")
        actual << "attempt" if contains_key?(body, "attempt_id")
        actual << "fencing" if contains_key?(body, "fencing_token")
      end
      [ entry.fetch("identifier"), entry.fetch("required_preconditions").sort, actual.sort ]
    end
  end

  def artifact_examples
    [
      [ "document", "produced", { "kind" => "document", "path" => "tasks/KOS-000123/task.md",
        "commit_sha" => SHA, "content_digest" => DIGEST } ],
      [ "candidate", "produced", artifact_input.fetch("metadata") ],
      [ "test", "passed", { "kind" => "test", "candidate_sha" => SHA, "command" => "bundle exec rspec",
        "exit_code" => 0, "log_digest" => DIGEST } ],
      [ "test", "failed", { "kind" => "test", "candidate_sha" => SHA, "command" => "bundle exec rspec",
        "exit_code" => 1, "log_digest" => DIGEST } ],
      [ "review", "approved", { "kind" => "review", "candidate_sha" => SHA, "verdict" => "approved",
        "review_attempt_id" => "88888888-8888-4888-8888-888888888888" } ],
      [ "review", "changes_requested", { "kind" => "review", "candidate_sha" => SHA,
        "verdict" => "changes_requested", "review_attempt_id" => "88888888-8888-4888-8888-888888888888" } ],
      [ "publication", "published", artifact_input("publication").fetch("metadata") ]
    ]
  end

  def artifact_example_validity
    schema = definition("artifacts.json", "artifact_input")
    artifact_examples.map do |type, state, metadata|
      schema.valid?({ "schema_version" => "1", "type" => type, "state" => state,
        "producer" => "kos-workflow-step", "metadata" => metadata })
    end
  end

  def artifact_mismatch_validity
    schema = definition("artifacts.json", "artifact_input")
    type, state, metadata = artifact_examples.find { |item| item.first(2) == %w[test passed] }
    values = [ { "schema_version" => "1", "type" => type, "state" => "approved",
      "producer" => "kos-workflow-step", "metadata" => metadata }, { "schema_version" => "1", "type" => type,
      "state" => state, "producer" => "kos-workflow-step", "metadata" => metadata.merge("exit_code" => 1) } ]
    values.map { |value| schema.valid?(value) }
  end

  def draft_import_binding_contract
    draft = workflow_draft
    import = request("workflow_draft.import").fetch("body")
    annotations = SCHEMAS.fetch("commands.json").dig("$defs", "workflow_draft_import_body", "x-field-equality")
    [ workflow_resource_binding_errors(draft, "workflow_draft"), annotations,
      import.fetch("workflow_id") == import.dig("definition", "workflow_id") ]
  end

  def effect_round_trip
    request = { "schema_version" => "1", "attempt_id" => ATTEMPT_ID, "input_context_digest" => DIGEST,
      "effect" => { "operation" => "commit", "reservation_id" => RESERVATION_ID, "expected_head_sha" => SHA,
        "expected_diff_digest" => DIGEST, "expected_index_digest" => DIGEST, "paths" => [ "app/models/task.rb" ],
        "message" => "Implement task", "task_number" => "KOS-000123" } }
    request_digest = "sha256:#{Digest::SHA256.hexdigest(canonical_json(request))}"
    result = { "schema_version" => "1", "effect_intent_id" => EFFECT_ID, "request_attempt_id" => ATTEMPT_ID,
      "owner_attempt_id" => ATTEMPT_ID,
      "input_context_digest" => DIGEST, "effect_request_digest" => request_digest,
      "result" => { "outcome" => "succeeded", "operation" => "commit", "commit_sha" => SHA,
        "evidence_digest" => DIGEST } }
    [ request, result ]
  end

  def repository_effect(state = "prepared")
    request, result = effect_round_trip
    value = { "schema_version" => "1", "id" => EFFECT_ID, "repository_id" => REPOSITORY_ID, "task_id" => TASK_ID,
      "prepared_attempt_id" => ATTEMPT_ID, "current_owner_attempt_id" => ATTEMPT_ID,
      "request_digest" => result.fetch("effect_request_digest"), "request" => request, "state" => state,
      "prepared_at" => "2026-09-09T12:00:00Z", "updated_at" => "2026-09-09T12:01:00Z" }
    if %w[failed unknown].include?(state)
      result = result.merge("result" => { "outcome" => state, "operation" => "commit",
        "error" => { "category" => "transient", "code" => "git_process_failed",
          "message" => "Git process failed", "retryable" => true } })
    end
    value.merge!("result" => result, "reconciled_at" => "2026-09-09T12:01:00Z") unless state == "prepared"
    value
  end

  def effect_round_trip_contract
    request, result = effect_round_trip
    failure = result.merge("result" => { "outcome" => "unknown", "operation" => "commit",
      "error" => { "category" => "transient", "code" => "git_process_failed",
        "message" => "Git process failed", "retryable" => true } })
    schema = definition("workflow.json", "effect_result")
    digest = "sha256:#{Digest::SHA256.hexdigest(canonical_json(request))}"
    [ definition("workflow.json", "effect_request").valid?(request), schema.valid?(result), schema.valid?(failure),
      result.fetch("effect_request_digest") == digest ]
  end

  def effect_binding_contract
    definitions = SCHEMAS.fetch("commands.json").fetch("$defs")
    prepare = definitions.fetch("effect_prepare_body")
    reconcile = definitions.fetch("effect_reconcile_body")
    [ prepare.fetch("x-field-equality"), prepare.fetch("x-context-bindings"),
      reconcile.fetch("x-field-equality"), reconcile.fetch("x-stored-effect-bindings") ]
  end

  def expected_effect_bindings
    [ [ [ "effect_request.attempt_id", "preconditions.attempt_id" ] ],
      [ [ "effect_request.input_context_digest", "stored_attempt.input_context_digest" ],
        [ "effect_request.effect.task_number", "task_number", "when-present" ],
        [ "effect_request.effect.operation", "stored_context.allowed_repository_effects", "member-of" ],
        [ "effect_request.effect.reservation_id", "stored_context.worktree.reservation_id", "when-present" ],
        [ "effect_request.effect.expected_head_sha", "stored_context.worktree.head_sha", "when-present" ] ],
      [ [ "effect_id", "effect_result.effect_intent_id" ],
        [ "effect_result.owner_attempt_id", "preconditions.attempt_id" ] ],
      [ [ "effect_result.request_attempt_id", "request.attempt_id" ],
        [ "effect_result.input_context_digest", "request.input_context_digest" ],
        [ "effect_result.effect_request_digest", "request_digest" ],
        [ "effect_result.result.operation", "request.effect.operation" ] ] ]
  end

  def repository_effect_validity
    schema = definition("resources.json", "repository_effect")
    succeeded = repository_effect("succeeded")
    invalid_state = succeeded.merge("state" => "failed")
    push = { "operation" => "push", "publication_id" => PUBLICATION_ID, "candidate_sha" => SHA,
      "remote" => "origin", "base_ref" => "refs/heads/main", "expected_remote_oid" => SHA }
    invalid_operation = repository_effect.merge("request" => effect_round_trip.first.merge("effect" => push))
    [ succeeded, repository_effect("unknown"), invalid_state, invalid_operation ].map { |value| schema.valid?(value) }
  end
end

RSpec.describe CliV1Contract do
  it "validates every CLI and runtime schema against its metaschema" do
    schemas = described_class::SCHEMAS.values + [ JSON.parse(File.read(described_class::RUNTIME_SCHEMA_PATH)) ]

    expect(schemas).to all(satisfy { |schema| JSONSchemer.valid_schema?(schema) })
  end

  it "uses unique versioned identifiers and local CLI references" do
    expect(described_class.schema_identity_contract).to eq([ true, true, true ])
  end

  it "resolves every CLI reference locally" do
    references = described_class::SCHEMAS.flat_map do |_name, schema|
      described_class.references(schema).map { |reference| [ schema, reference ] }
    end

    expect { references.each { |root, reference| described_class.resolve_reference(root, reference) } }.not_to raise_error
  end

  CliV1Contract::CLI_FIXTURES.each do |validity, fixtures|
    fixtures.each do |fixture|
      it "#{validity == 'valid' ? 'accepts' : 'rejects'} #{fixture.fetch('name')}" do
        schema = described_class.definition(fixture.fetch("schema"), fixture.fetch("definition"))

        expect(schema.valid?(fixture.fetch("instance"))).to eq(validity == "valid")
      end
    end
  end

  it "accepts the central quick-fix workflow definition" do
    validity = described_class.definition("workflow_definition.json", "definition")
      .valid?(described_class.workflow_definition)

    expect([ validity, described_class.graph_errors(described_class.workflow_definition) ]).to eq([ true, [] ])
  end

  CliV1Contract::INVALID_WORKFLOW_CASES.each do |name, fixture|
    it "rejects workflow graph fixture #{name}" do
      definition = described_class.mutated_workflow(fixture.fetch("mutation"))

      expect(described_class.graph_errors(definition)).to include(fixture.fetch("expected_error"))
    end
  end

  it "publishes inline instructions, templates, effects, and no project paths" do
    expect(described_class.workflow_content_contract).to eq([ true, true ])
  end

  it "computes one canonical workflow content digest" do
    expected = "sha256:#{Digest::SHA256.hexdigest(described_class.canonical_json(described_class.workflow_definition))}"

    expect(described_class.workflow_summary.fetch("content_digest")).to eq(expected)
  end

  it "publishes whole-graph, digest, and immutable-version annotations" do
    workflow = described_class::SCHEMAS.fetch("workflow_definition.json").dig("$defs", "definition")
    version = described_class::SCHEMAS.fetch("resources.json").dig("$defs", "workflow_version")

    expect([ workflow.fetch("x-graph-validation").length, workflow.fetch("x-content-digest"),
      version.fetch("x-immutable") ]).to eq([ 16, "sha256-rfc8785-canonical-definition", true ])
  end

  it "binds workflow resource identity and digest to embedded content" do
    valid = described_class.workflow_version
    wrong_identity, wrong_digest = valid.merge("workflow_id" => "other"), valid.merge("content_digest" => described_class::DIGEST)

    expect([ valid, wrong_identity, wrong_digest ].map do |value|
      described_class.workflow_resource_binding_errors(value, "workflow_version")
    end).to eq([ [], [ "workflow_id" ], [ "content_digest" ] ])
  end

  it "binds draft and import identities to their complete definitions" do
    expect(described_class.draft_import_binding_contract)
      .to eq([ [], [ [ "workflow_id", "definition.workflow_id" ] ], true ])
  end

  it "binds the complete attempt context to one canonical digest" do
    context = described_class.context
    digest = Digest::SHA256.hexdigest(described_class.canonical_json(context.except("input_context_digest")))

    expect([ context.fetch("input_context_digest"), context.keys.grep(/bundle_digest|materials|allowed_capabilities/) ])
      .to eq([ "sha256:#{digest}", [] ])
  end

  it "keeps artifact evidence type-specific" do
    schema = described_class.definition("artifacts.json", "artifact_input")
    candidate = described_class.artifact_input

    expect([ schema.valid?(candidate), schema.valid?(described_class.document_artifact), candidate.key?("evidence_digest") ])
      .to eq([ true, true, false ])
  end

  it "accepts every artifact discriminator with its compatible state" do
    expect(described_class.artifact_example_validity).to all(be(true))
  end

  it "rejects incompatible artifact states and state-specific metadata" do
    expect(described_class.artifact_mismatch_validity).to eq([ false, false ])
  end

  described_class::EXPECTED_COMMANDS.each do |command|
    it "validates the #{command} request and result" do
      validity = [ described_class.definition("commands.json", "request").valid?(described_class.request(command)),
        described_class.definition("commands.json", "result").valid?(described_class.result(command)) ]

      expect(validity).to eq([ true, true ])
    end
  end

  it "publishes exact request and result dispatch for every command" do
    definitions = described_class::SCHEMAS.fetch("commands.json").fetch("$defs")
    result_commands = described_class.dispatched_commands(definitions.fetch("result")).uniq

    expect([ described_class.request_dispatch_commands.sort, result_commands.sort ])
      .to eq([ described_class::EXPECTED_COMMANDS.sort, described_class::EXPECTED_COMMANDS.sort ])
  end

  it "keeps global catalog commands outside repository scope" do
    expect(described_class.global_scope_contract).to eq([ false, true, false, false ])
  end

  it "does not let task creation select a workflow version" do
    request = described_class.request("task.create")
    request.fetch("body")["workflow_version_id"] = described_class::WORKFLOW_VERSION_ID

    expect(described_class.definition("commands.json", "request")).not_to be_valid(request)
  end

  it "pins tasks by workflow version identifier without a bundle digest" do
    expect(described_class.task_pinning_contract).to eq([ true, described_class::WORKFLOW_VERSION_ID, [] ])
  end

  it "allows a task type to exist before workflow activation" do
    task_type = described_class.task_type.except("current_workflow_version_id")

    expect(described_class.definition("resources.json", "task_type")).to be_valid(task_type)
  end

  it "requires frozen context and matching results for terminal attempts" do
    expect(described_class.terminal_attempt_contract).to eq([ true, false, false ])
  end

  it "requires safe commit boundaries" do
    expect(described_class.commit_boundary_contract).to eq([ true, [ false, false, false, false, false ] ])
  end

  it "supports an attempt-bound typed effect round trip before final result" do
    expect(described_class.effect_round_trip_contract).to eq([ true, true, true, true ])
  end

  it "binds generic effect ownership and context at command boundaries" do
    expect(described_class.effect_binding_contract).to eq(described_class.expected_effect_bindings)
  end

  it "binds generic effect state to outcomes and excludes specialized protocols" do
    expect(described_class.repository_effect_validity).to eq([ true, true, false, false ])
  end

  it "requires prepared publication data in publication context" do
    value = described_class.context.merge("workflow_status" => "publication", "candidate_sha" => described_class::SHA,
      "publication" => { "publication_id" => described_class::PUBLICATION_ID, "candidate_sha" => described_class::SHA,
        "remote" => "origin", "base_ref" => "refs/heads/main", "expected_remote_oid" => described_class::SHA })
    schema = described_class.definition("workflow.json", "context")

    expect([ schema.valid?(value), schema.valid?(value.except("publication")) ]).to eq([ true, false ])
  end

  it "contracts the installation-wide retrospective setting" do
    schema = described_class.definition("resources.json", "runtime_config")

    expect([ schema.valid?(described_class.runtime_config),
      schema.valid?(described_class.runtime_config.except("retrospective_enabled")) ]).to eq([ true, false ])
  end

  it "accepts private sanitized retrospective outcomes" do
    schema = described_class.retrospective_schema.ref("#/$defs/result")

    expect(described_class.retrospective_examples.map { |value| schema.valid?(value) }).to eq([ true, true ])
  end

  it "rejects transcript fields and recursive empty proposal outcomes" do
    value = { "schema_version" => "1", "session_id" => described_class::ATTEMPT_ID,
      "source" => "orchestrator", "primary_result_acknowledged" => true,
      "outcome" => "proposals", "proposals" => [], "transcript" => "private" }

    expect(described_class.retrospective_schema.ref("#/$defs/result")).not_to be_valid(value)
  end

  it "publishes retrospective privacy and primary-result annotations" do
    result = JSON.parse(File.read(described_class::RUNTIME_SCHEMA_PATH)).dig("$defs", "result")

    expect(result.values_at("x-private-input", "x-persistence", "x-primary-result-independent",
      "x-recursion-suppressed")).to eq([ "invoking-agent-dialogue-only", "none", true, true ])
  end

  it "aligns the command catalog with the command enum and scope" do
    expected = [ described_class::EXPECTED_COMMANDS.sort, true, described_class::GLOBAL_COMMANDS.sort ]

    expect(described_class.catalog_contract).to eq(expected)
  end

  it "aligns every catalog precondition with its request body" do
    mismatches = described_class.catalog_precondition_contract.reject { |_command, expected, actual| expected == actual }

    expect(mismatches).to be_empty
  end

  it "aligns the error catalog with closed error pairs" do
    catalog_pairs, schema_pairs, unique = described_class.error_catalog_contract

    expect([ catalog_pairs == schema_pairs, unique ]).to eq([ true, true ])
  end

  it "rejects numeric prerelease identifiers with leading zeroes" do
    schema = described_class.definition("common.json", "semantic_version")

    expect([ schema.valid?("1.0.0-0"), schema.valid?("1.0.0-01"), schema.valid?("1.0.0-alpha.1"),
      schema.valid?("1.0.0-1alpha"), schema.valid?("1.0.0-01alpha") ]).to eq([ true, false, true, true, true ])
  end
end
