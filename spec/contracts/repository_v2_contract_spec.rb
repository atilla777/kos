require "json"
require "json_schemer"
require "spec_helper"
require_relative "../../lib/kos/publication_preflight_evidence"

module RepositoryV2Contract
end

RSpec.describe RepositoryV2Contract do
  let(:schema) do
    path = File.expand_path("../../schemas/repository/v2/adapter.json", __dir__)
    JSONSchemer.schema(JSON.parse(File.read(path)))
  end
  let(:repository) do
    { "id" => "33333333-3333-4333-8333-333333333333", "git_common_dir" => "/srv/project/.git",
      "trusted_remote" => "origin", "trusted_remote_url" => "file:///srv/remote.git",
      "base_ref" => "refs/heads/main" }
  end
  let(:publication_preflight) do
    { "id" => "44444444-4444-4444-8444-444444444444", "repository_id" => repository.fetch("id"),
      "task_id" => "55555555-5555-4555-8555-555555555555", "candidate_sha" => "1" * 40,
      "current_owner_attempt_id" => "66666666-6666-4666-8666-666666666666", "fencing_token" => 9,
      "remote" => "origin", "base_ref" => "refs/heads/main", "state" => "prepared" }
  end
  let(:request) do
    { "schema_version" => "2", "operation" => "publication_preflight", "repository" => repository,
      "publication_preflight" => publication_preflight }
  end

  it "accepts only a closed complete publication preflight request", :aggregate_failures do
    expect(request_contract_results).to eq([ true, true, false, false ])
  end

  it "accepts a closed evidence-bound success", :aggregate_failures do
    expect(success_contract_results).to eq([ true, false, true ])
  end

  it "reserves unknown for retryable uncertain transport", :aggregate_failures do
    expect(unknown_contract_results).to eq([ true, false, false ])
  end

  def request_contract_results
    contract = schema.ref("#/$defs/request")
    unknown_state = request.merge("publication_preflight" => publication_preflight.merge("state" => "unknown"))
    [ contract.valid?(request), contract.valid?(unknown_state),
      contract.valid?(request.merge("expected_remote_oid" => "2" * 40)),
      contract.valid?(request.merge("publication_preflight" => publication_preflight.except("task_id"))) ]
  end

  def success_contract_results
    result = success
    expected_digest = Kos::PublicationPreflightEvidence.digest(repository: repository,
      publication_preflight: publication_preflight, observed_remote_oid: result.fetch("observed_remote_oid"),
      observed_at: result.fetch("observed_at"))
    [ schema.ref("#/$defs/success").valid?(result),
      schema.ref("#/$defs/success").valid?(result.merge("stderr" => "unsafe")),
      result.fetch("evidence_digest") == expected_digest ]
  end

  def unknown_contract_results
    unknown = { "schema_version" => "2", "operation" => "publication_preflight", "outcome" => "unknown",
      "error" => { "category" => "transient", "code" => "publication_preflight_state_uncertain",
        "message" => "Remote state is uncertain", "retryable" => true } }
    contract = schema.ref("#/$defs/failure")
    [ contract.valid?(unknown), contract.valid?(unknown.merge("outcome" => "failed")),
      contract.valid?(unknown.merge("error" => unknown.fetch("error").merge("retryable" => false))) ]
  end

  def success
    observed_at = "2026-09-15T12:00:00.000000Z"
    observed_remote_oid = "2" * 40
    { "schema_version" => "2", "operation" => "publication_preflight", "outcome" => "succeeded",
      "repository_id" => repository.fetch("id"), "publication_preflight_id" => publication_preflight.fetch("id"),
      "task_id" => publication_preflight.fetch("task_id"), "candidate_sha" => publication_preflight.fetch("candidate_sha"),
      "current_owner_attempt_id" => publication_preflight.fetch("current_owner_attempt_id"),
      "fencing_token" => publication_preflight.fetch("fencing_token"), "remote" => "origin",
      "base_ref" => "refs/heads/main", "observed_remote_oid" => observed_remote_oid, "observed_at" => observed_at,
      "evidence_digest" => Kos::PublicationPreflightEvidence.digest(repository: repository,
        publication_preflight: publication_preflight, observed_remote_oid: observed_remote_oid,
        observed_at: observed_at) }
  end
end
