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
end
