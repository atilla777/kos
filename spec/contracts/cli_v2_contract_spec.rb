require "json"
require "json_schemer"
require "spec_helper"

module CliV2Contract
  SCHEMA_DIRECTORY = File.expand_path("../../schemas/cli/v2", __dir__)
  SCHEMAS = Dir[File.join(SCHEMA_DIRECTORY, "*.json")].sort.to_h do |path|
    [ File.basename(path), JSON.parse(File.read(path)) ]
  end.freeze
  REGISTRY = SCHEMAS.values.to_h { |schema| [ URI(schema.fetch("$id")), schema ] }.freeze
  COMMANDS = %w[
    publication_preflight.get
    publication_preflight.prepare
    publication_preflight.reconcile
    publication.prepare_observed
  ].freeze
  REQUEST_ID = "99999999-9999-4999-8999-999999999999"
  REPOSITORY_ID = "33333333-3333-4333-8333-333333333333"
  TASK_ID = "11111111-1111-4111-8111-111111111111"
  ATTEMPT_ID = "22222222-2222-4222-8222-222222222222"
  PREFLIGHT_ID = "77777777-7777-4777-8777-777777777777"
  PUBLICATION_ID = "44444444-4444-4444-8444-444444444444"
  SHA = "1111111111111111111111111111111111111111"
  DIGEST = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  TIMESTAMP = "2026-09-15T12:00:00Z"

  module_function

  def definition(schema_name, definition_name)
    JSONSchemer.schema(SCHEMAS.fetch(schema_name), ref_resolver: REGISTRY.to_proc).ref("#/$defs/#{definition_name}")
  end

  def preconditions
    { "expected_lock_version" => 3, "attempt_id" => ATTEMPT_ID, "fencing_token" => 8 }
  end

  def safe_error
    { "category" => "transient", "code" => "publication_preflight_state_uncertain",
      "message" => "Remote observation is unavailable", "retryable" => true }
  end

  def preflight(state = "prepared")
    value = { "schema_version" => "2", "id" => PREFLIGHT_ID, "repository_id" => REPOSITORY_ID,
      "task_id" => TASK_ID, "prepared_attempt_id" => ATTEMPT_ID,
      "current_owner_attempt_id" => ATTEMPT_ID, "candidate_sha" => SHA, "remote" => "origin",
      "base_ref" => "refs/heads/main", "state" => state, "prepared_at" => TIMESTAMP,
      "updated_at" => TIMESTAMP }
    value.merge!("error" => safe_error, "reconciled_at" => TIMESTAMP) if state == "unknown"
    if %w[reconciled consumed].include?(state)
      value.merge!("observed_remote_oid" => SHA, "observation_digest" => DIGEST,
        "observed_at" => TIMESTAMP, "reconciled_at" => TIMESTAMP)
    end
    value.merge!("publication_id" => PUBLICATION_ID, "consumed_at" => TIMESTAMP) if state == "consumed"
    value
  end

  def publication
    { "schema_version" => "2", "id" => PUBLICATION_ID, "repository_id" => REPOSITORY_ID,
      "task_id" => TASK_ID, "prepared_attempt_id" => ATTEMPT_ID, "current_owner_attempt_id" => ATTEMPT_ID,
      "candidate_sha" => SHA, "remote" => "origin", "base_ref" => "refs/heads/main",
      "expected_remote_oid" => SHA, "state" => "prepared", "prepared_at" => TIMESTAMP,
      "updated_at" => TIMESTAMP }
  end

  def body(command)
    case command
    when "publication_preflight.get"
      { "preflight_id" => PREFLIGHT_ID }
    when "publication_preflight.prepare"
      { "task_number" => "KOS-000123", "candidate_sha" => SHA, "remote" => "origin",
        "base_ref" => "refs/heads/main", "preconditions" => preconditions }
    when "publication_preflight.reconcile"
      { "preflight_id" => PREFLIGHT_ID, "observed_remote_oid" => SHA, "observed_at" => TIMESTAMP,
        "evidence_digest" => DIGEST, "preconditions" => preconditions }
    when "publication.prepare_observed"
      { "preflight_id" => PREFLIGHT_ID, "preconditions" => preconditions }
    end
  end

  def request(command)
    { "schema_version" => "2", "command" => command, "repository_id" => REPOSITORY_ID,
      "body" => body(command) }
  end

  def result(command)
    data = case command
    when "publication.prepare_observed" then publication
    when "publication_preflight.reconcile" then preflight("reconciled")
    else preflight
    end
    { "schema_version" => "2", "request_id" => REQUEST_ID, "command" => command, "data" => data }
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

  def schema_identity_contract
    identifiers = SCHEMAS.values.map { |schema| schema.fetch("$id") }
    references = SCHEMAS.flat_map do |_name, schema|
      references(schema).map { |reference| [ schema, reference ] }
    end
    resolved = begin
      references.each { |root, reference| resolve_reference(root, reference) }
      true
    end
    [ identifiers.all? { |id| id.include?("/schemas/cli/v2/") }, identifiers.uniq == identifiers, resolved ]
  end

  def preflight_state_contract
    schema = definition("resources.json", "publication_preflight")
    valid_states = %w[prepared unknown reconciled consumed].map { |state| schema.valid?(preflight(state)) }
    malformed = [ preflight.merge("unexpected" => true),
      preflight("unknown").merge("observed_remote_oid" => SHA),
      preflight("reconciled").except("observation_digest") ]
    [ valid_states, malformed.map { |value| schema.valid?(value) } ]
  end

  def reconciliation_contract
    schema = definition("commands.json", "publication_preflight_reconcile_body")
    concrete = body("publication_preflight.reconcile")
    unknown = { "preflight_id" => PREFLIGHT_ID, "unknown" => safe_error, "preconditions" => preconditions }
    [ concrete, unknown, concrete.except("evidence_digest"),
      unknown.merge("unknown" => safe_error.merge("stderr" => "secret")) ].map { |value| schema.valid?(value) }
  end

  def failure_contract
    schema = definition("envelopes.json", "failure")
    failure = { "schema_version" => "2", "request_id" => REQUEST_ID,
      "command" => "publication_preflight.get", "error" => { "category" => "authentication",
        "code" => "authentication_required", "message" => "Authentication required", "retryable" => false } }
    [ failure, failure.merge("debug" => true), failure.merge("schema_version" => "1") ]
      .map { |value| schema.valid?(value) }
  end

  def catalog_contract
    catalog = SCHEMAS.fetch("catalog.json").fetch("x-command-catalog")
    schema = definition("catalog.json", "command_entry")
    scoped = catalog.all? do |entry|
      entry.fetch("scope") == "repository" &&
        entry.fetch("http_path").start_with?("/api/v2/repositories/{repository_id}/")
    end
    [ catalog.map { |entry| entry.fetch("identifier") }.sort, catalog.all? { |entry| schema.valid?(entry) }, scoped ]
  end

  def mutation_catalog_contract
    catalog = SCHEMAS.fetch("catalog.json").fetch("x-command-catalog")
    mutations = catalog.select { |entry| entry.fetch("mutation") }
    [ mutations.map { |entry| entry.fetch("required_preconditions") }.uniq,
      catalog.map { |entry| entry.fetch("cli_suffix") }.sort ]
  end
end

RSpec.describe CliV2Contract do
  it "validates every schema against its metaschema" do
    expect(described_class::SCHEMAS.values).to all(satisfy { |schema| JSONSchemer.valid_schema?(schema) })
  end

  it "uses unique v2 identifiers and resolves every reference locally" do
    expect(described_class.schema_identity_contract).to eq([ true, true, true ])
  end

  CliV2Contract::COMMANDS.each do |command|
    it "validates the #{command} request and result" do
      expect([ described_class.definition("commands.json", "request").valid?(described_class.request(command)),
        described_class.definition("commands.json", "result").valid?(described_class.result(command)) ])
        .to eq([ true, true ])
    end
  end

  it "accepts every closed preflight state with only its state-specific evidence" do
    expect(described_class.preflight_state_contract).to eq([ [ true, true, true, true ], [ false, false, false ] ])
  end

  it "accepts concrete or closed unknown reconciliation and rejects partial evidence" do
    expect(described_class.reconciliation_contract).to eq([ true, true, false, false ])
  end

  it "keeps general failures closed without narrowing authentication errors to adapter errors" do
    expect(described_class.failure_contract).to eq([ true, false, false ])
  end

  it "never accepts a caller OID for observed publication preparation" do
    schema = described_class.definition("commands.json", "publication_prepare_observed_body")
    body = described_class.body("publication.prepare_observed")

    expect([ schema.valid?(body), schema.valid?(body.merge("expected_remote_oid" => described_class::SHA)),
      schema.valid?(body.except("preconditions")) ]).to eq([ true, false, false ])
  end

  it "requires schema version 2 and repository scope on every request" do
    schema = described_class.definition("commands.json", "request")
    request = described_class.request("publication_preflight.get")

    expect([ schema.valid?(request), schema.valid?(request.merge("schema_version" => "1")),
      schema.valid?(request.except("repository_id")) ]).to eq([ true, false, false ])
  end

  it "catalogs only the four repository-scoped api v2 commands" do
    expect(described_class.catalog_contract).to eq([ described_class::COMMANDS.sort, true, true ])
  end

  it "requires complete leased mutation preconditions and exact cli syntax" do
    expected_syntax = [ "publication prepare-observed", "publication-preflight get",
      "publication-preflight prepare", "publication-preflight reconcile" ]

    expect(described_class.mutation_catalog_contract)
      .to eq([ [ %w[idempotency lock attempt fencing] ], expected_syntax ])
  end

  it "keeps the observed OID server-derived from the consumed preflight" do
    definition = described_class::SCHEMAS.fetch("commands.json")
      .dig("$defs", "publication_prepare_observed_body")

    expect(definition.fetch("x-copies-expected-remote-oid-from"))
      .to eq("publication_preflight.observed_remote_oid")
  end
end
