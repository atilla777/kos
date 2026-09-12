require "json"
require "json_schemer"
require "spec_helper"
require_relative "../../lib/kos/repository"

module RepositoryV1Contract
end

RSpec.describe RepositoryV1Contract do
  let(:schema) do
    path = File.expand_path("../../schemas/repository/v1/adapter.json", __dir__)
    JSONSchemer.schema(JSON.parse(File.read(path)))
  end
  let(:repository_id) { "33333333-3333-4333-8333-333333333333" }
  let(:reservation_id) { "55555555-5555-4555-8555-555555555555" }
  let(:sha) { "1" * 40 }
  let(:request) do
    { "schema_version" => "1", "operation" => "materialize",
      "repository" => { "id" => repository_id, "git_common_dir" => "/srv/project/.git",
        "base_ref" => "refs/heads/main" },
      "reservation" => { "id" => reservation_id, "repository_id" => repository_id, "state" => "reserved",
        "path" => "/srv/worktrees/KOS-000123", "branch" => "kos/task-KOS-000123", "fencing_token" => 8 },
      "expected_head_sha" => sha }
  end

  def commit_request
    request.merge("operation" => "commit", "reservation" => request.fetch("reservation").merge("state" => "confirmed"),
      "expected_diff_digest" => "sha256:#{'a' * 64}", "expected_index_digest" => "sha256:#{'b' * 64}",
      "paths" => [ "README.md" ], "message" => "Implement exact commit", "task_number" => "KOS-000123")
  end

  def fetch_request
    durable_request = { "schema_version" => "1", "attempt_id" => attempt_id,
      "input_context_digest" => "sha256:#{'a' * 64}",
      "effect" => { "operation" => "fetch", "remote" => "origin", "ref" => "refs/heads/main" } }
    { "schema_version" => "1", "operation" => "fetch",
      "repository" => { "id" => repository_id, "git_common_dir" => "/srv/project/.git",
        "trusted_remote" => "origin", "trusted_remote_url" => "file:///srv/remote.git",
        "base_ref" => "refs/heads/main" },
      "effect" => { "id" => effect_id, "repository_id" => repository_id,
        "current_owner_attempt_id" => attempt_id, "fencing_token" => 9,
        "request_digest" => "sha256:#{Digest::SHA256.hexdigest(canonical_json(durable_request))}",
        "request" => durable_request } }
  end

  def rebase_request
    durable_request = { "schema_version" => "1", "attempt_id" => attempt_id,
      "input_context_digest" => "sha256:#{'c' * 64}",
      "effect" => { "operation" => "rebase", "reservation_id" => reservation_id,
        "expected_head_sha" => sha, "onto_sha" => "2" * 40 } }
    { "schema_version" => "1", "operation" => "rebase", "repository" => fetch_request.fetch("repository"),
      "reservation" => request.fetch("reservation").merge("state" => "confirmed", "fencing_token" => 9),
      "effect" => { "id" => "99999999-9999-4999-8999-999999999999", "repository_id" => repository_id,
        "current_owner_attempt_id" => attempt_id, "fencing_token" => 9,
        "request_digest" => "sha256:#{Digest::SHA256.hexdigest(canonical_json(durable_request))}",
        "request" => durable_request },
      "fetch" => { "request" => fetch_request, "result" => fetch_success } }
  end

  it "accepts a materialize request" do
    expect(schema.ref("#/$defs/request")).to be_valid(request)
  end

  it "accepts an observe request" do
    expect(schema.ref("#/$defs/request")).to be_valid(request.merge("operation" => "observe"))
  end

  it "accepts a remove request" do
    expect(schema.ref("#/$defs/request")).to be_valid(request.merge("operation" => "remove",
      "reservation" => request.fetch("reservation").merge("state" => "release_pending")))
  end

  it "accepts a closed confirmed commit request", :aggregate_failures do
    expect(schema.ref("#/$defs/request")).to be_valid(commit_request)
    expect(schema.ref("#/$defs/request")).not_to be_valid(commit_request.merge("stderr" => "unsafe"))
  end

  it "accepts only a closed effect-bound fetch request", :aggregate_failures do
    expect(schema.ref("#/$defs/request")).to be_valid(fetch_request)
    expect(schema.ref("#/$defs/request")).not_to be_valid(fetch_request.merge("destination" => "refs/heads/main"))
    expect(schema.ref("#/$defs/request")).not_to be_valid(fetch_request.merge("remote" => "origin"))
    expect(schema.ref("#/$defs/request")).not_to be_valid(fetch_request.merge(
      "effect" => fetch_request.fetch("effect").except("fencing_token")))
  end

  it "accepts only a closed rebase request with confirmed reservation and fetch evidence", :aggregate_failures do
    expect(schema.ref("#/$defs/request")).to be_valid(rebase_request)
    expect(schema.ref("#/$defs/request")).not_to be_valid(rebase_request.merge("onto_sha" => "2" * 40))
    expect(schema.ref("#/$defs/request")).not_to be_valid(rebase_request.merge(
      "reservation" => rebase_request.fetch("reservation").merge("state" => "reserved")))
    expect(schema.ref("#/$defs/request")).not_to be_valid(rebase_request.merge("fetch" => {}))
  end

  it "accepts only registered fetch URL schemes without raw passwords, queries, or fragments" do
    expect(fetch_url_contract_results).to eq([ true, true, true, true, false, false, false, false, false ])
  end

  it "rejects a commit for any other reservation lifecycle" do
    invalid = commit_request.merge("reservation" => commit_request.fetch("reservation").merge("state" => "reserved"))

    expect(schema.ref("#/$defs/request")).not_to be_valid(invalid)
  end

  it "rejects lexically ambiguous commit paths" do
    %w[/README.md ./README.md lib/../README.md :/README.md].each do |path|
      expect(schema.ref("#/$defs/request")).not_to be_valid(commit_request.merge("paths" => [ path ]))
    end
  end

  it "rejects operation and lifecycle mismatches" do
    invalid = request.merge("operation" => "remove")

    expect(schema.ref("#/$defs/request")).not_to be_valid(invalid)
  end

  it "keeps request objects closed" do
    expect(schema.ref("#/$defs/request")).not_to be_valid(request.merge("token" => "secret"))
  end

  it "accepts a clean success result" do
    success = { "schema_version" => "1", "operation" => "materialize", "outcome" => "succeeded",
      "repository_id" => repository_id, "reservation_id" => reservation_id, "fencing_token" => 8,
      "observation" => { "state" => "clean", "head_sha" => sha,
        "git_common_dir_digest" => "sha256:#{'a' * 64}", "evidence_digest" => "sha256:#{'b' * 64}" } }

    expect(schema.ref("#/$defs/success")).to be_valid(success)
  end

  it "keeps result objects closed" do
    success = { "schema_version" => "1", "operation" => "remove", "outcome" => "succeeded",
      "repository_id" => repository_id, "reservation_id" => reservation_id, "fencing_token" => 8,
      "observation" => { "state" => "absent", "evidence_digest" => "sha256:#{'b' * 64}" } }

    expect(schema.ref("#/$defs/success")).not_to be_valid(success.merge("stderr" => "unsafe"))
  end

  it "accepts only the operation-specific commit success", :aggregate_failures do
    success = { "schema_version" => "1", "operation" => "commit", "outcome" => "succeeded",
      "repository_id" => repository_id, "reservation_id" => reservation_id, "fencing_token" => 8,
      "commit_sha" => sha, "evidence_digest" => "sha256:#{'b' * 64}" }

    expect(schema.ref("#/$defs/success")).to be_valid(success)
    expect(schema.ref("#/$defs/success")).not_to be_valid(success.merge("observation" => { "state" => "clean" }))
  end

  it "accepts only the closed effect-bound fetch success", :aggregate_failures do
    expect(schema.ref("#/$defs/success")).to be_valid(fetch_success)
    expect(schema.ref("#/$defs/success")).not_to be_valid(fetch_success.merge("stderr" => "unsafe"))
  end

  it "accepts only the closed effect-bound rebase success", :aggregate_failures do
    expect(schema.ref("#/$defs/success")).to be_valid(rebase_success)
    expect(schema.ref("#/$defs/success")).not_to be_valid(rebase_success.merge("onto_sha" => "2" * 40))
  end

  it "requires identity evidence for a present worktree" do
    observation = schema.ref("#/$defs/observation")

    expect(observation).not_to be_valid({ "state" => "clean", "evidence_digest" => "sha256:#{'a' * 64}" })
  end

  it "allows an absent observation without Git identity" do
    observation = schema.ref("#/$defs/observation")

    expect(observation).to be_valid({ "state" => "absent", "evidence_digest" => "sha256:#{'a' * 64}" })
  end

  it "rejects unknown error codes" do
    error = { "category" => "internal", "code" => "new_unversioned_error", "message" => "Failed",
      "retryable" => false }

    expect(schema.ref("#/$defs/error")).not_to be_valid(error)
  end

  it "rejects contradictory error retry semantics" do
    error = { "category" => "transient", "code" => "git_timeout", "message" => "Timed out",
      "retryable" => false }

    expect(schema.ref("#/$defs/error")).not_to be_valid(error)
  end

  it "accepts a commit-specific failure" do
    base = { "schema_version" => "1", "outcome" => "failed", "operation" => "commit" }
    commit_error = { "category" => "conflict", "code" => "index_mismatch", "message" => "Mismatch",
      "retryable" => false }
    expect(schema.ref("#/$defs/failure")).to be_valid(base.merge("error" => commit_error))
  end

  it "accepts only closed fetch failures with fixed retry semantics", :aggregate_failures do
    expect(schema.ref("#/$defs/failure")).to be_valid(fetch_failure)
    expect(schema.ref("#/$defs/failure")).not_to be_valid(fetch_failure.tap { |value| value["error"]["retryable"] = false })
    expect(schema.ref("#/$defs/failure")).not_to be_valid(fetch_failure.merge("error" => commit_only_error))
  end

  it "accepts only rebase failures with fixed recovery semantics", :aggregate_failures do
    expect(rebase_failure_contract_results).to eq([ true, true, false ])
  end

  it "rejects a worktree-only failure for commit" do
    base = { "schema_version" => "1", "outcome" => "failed", "operation" => "commit" }
    worktree_error = { "category" => "conflict", "code" => "branch_exists", "message" => "Conflict",
      "retryable" => false }
    expect(schema.ref("#/$defs/failure")).not_to be_valid(base.merge("error" => worktree_error))
  end

  it "keeps each worktree and unknown failure set closed" do
    invalid = { "materialize" => "worktree_removal_failed", "observe" => "branch_exists",
      "remove" => "worktree_materialization_failed", "unknown" => "internal_error" }

    expect(invalid).to all(satisfy { |operation, code| !schema.ref("#/$defs/failure").valid?(failure(operation, code)) })
  end

  def failure(operation, code)
    category = code == "internal_error" ? "internal" : "conflict"
    { "schema_version" => "1", "operation" => operation, "outcome" => "failed",
      "error" => { "category" => category, "code" => code, "message" => "Failed", "retryable" => false } }
  end

  def fetch_success
    { "schema_version" => "1", "operation" => "fetch", "outcome" => "succeeded",
      "repository_id" => repository_id, "effect_id" => effect_id, "current_owner_attempt_id" => attempt_id,
      "fencing_token" => 9, "effect_request_digest" => fetch_request.dig("effect", "request_digest"), "remote" => "origin",
      "ref" => "refs/heads/main", "observed_oid" => sha, "evidence_digest" => "sha256:#{'d' * 64}" }
  end

  def rebase_success
    { "schema_version" => "1", "operation" => "rebase", "outcome" => "succeeded",
      "repository_id" => repository_id, "reservation_id" => reservation_id,
      "effect_id" => rebase_request.dig("effect", "id"), "current_owner_attempt_id" => attempt_id,
      "fencing_token" => 9, "effect_request_digest" => rebase_request.dig("effect", "request_digest"),
      "head_sha" => "2" * 40, "evidence_digest" => "sha256:#{'d' * 64}" }
  end

  def rebase_failure_contract_results
    contract = schema.ref("#/$defs/failure")
    conflict = failure("rebase", "rebase_conflict")
    uncertain = conflict.merge("error" => { "category" => "transient", "code" => "rebase_state_uncertain",
      "message" => "Uncertain", "retryable" => true })
    [ contract.valid?(conflict), contract.valid?(uncertain), contract.valid?(conflict.merge("error" => commit_only_error)) ]
  end

  def fetch_request_with_url(url)
    fetch_request.merge("repository" => fetch_request.fetch("repository").merge("trusted_remote_url" => url))
  end

  def fetch_url_contract_results
    valid = [ "file:///srv/remote.git", "file://mirror.example.test/srv/remote.git",
      "https://example.test/repo.git", "ssh://git@example.test/repo.git" ]
    invalid = [ "http://example.test/repo.git", "https://user:secret@example.test/repo.git",
      "https://example.test/repo.git?mirror=other", "git://example.test/repo.git#other",
      "file://mirror.example.test" ]
    (valid + invalid).map { |url| schema.ref("#/$defs/request").valid?(fetch_request_with_url(url)) }
  end

  def fetch_failure
    { "schema_version" => "1", "outcome" => "failed", "operation" => "fetch",
      "error" => { "category" => "transient", "code" => "fetch_failed", "message" => "Fetch failed",
        "retryable" => true } }
  end

  def commit_only_error
    { "category" => "conflict", "code" => "index_mismatch", "message" => "Mismatch", "retryable" => false }
  end

  def canonical_json(value)
    case value
    when Hash
      "{#{value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(',')}}"
    when Array then "[#{value.map { |item| canonical_json(item) }.join(',')}]"
    else JSON.generate(value)
    end
  end

  def effect_id
    "66666666-6666-4666-8666-666666666666"
  end

  def attempt_id
    "77777777-7777-4777-8777-777777777777"
  end
end
