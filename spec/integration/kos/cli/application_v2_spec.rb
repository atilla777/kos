require "json"
require "socket"
require "stringio"
require "spec_helper"
require_relative "../../../../lib/kos/cli"

RSpec.describe Kos::Cli::Application, :aggregate_failures do
  def repository_id = "33333333-3333-4333-8333-333333333333"
  def preflight_id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  def publication_id = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"

  def publication_manifest
    { "schema_version" => "1", "attempt_id" => "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      "input_context_digest" => "sha256:#{'a' * 64}", "outcome" => "succeeded", "artifacts" => [
        { "schema_version" => "1", "type" => "publication", "state" => "published",
          "producer" => "workflow-step", "metadata" => { "kind" => "publication",
            "publication_id" => publication_id, "candidate_sha" => "a" * 40, "remote" => "origin",
            "base_ref" => "refs/heads/main", "observed_remote_tip" => "b" * 40, "reachable" => true,
            "observed_at" => "2026-09-15T12:00:00Z" } }
      ], "summary" => "Published candidate." }
  end

  def publication_result_record_body
    { "publication_id" => publication_id, "result_manifest" => publication_manifest, "preconditions" => {
      "expected_lock_version" => 4, "attempt_id" => "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      "fencing_token" => 5 } }
  end

  def preflight
    { "schema_version" => "2", "id" => preflight_id, "repository_id" => repository_id,
      "task_id" => "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      "prepared_attempt_id" => "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      "current_owner_attempt_id" => "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      "candidate_sha" => "a" * 40, "remote" => "origin", "base_ref" => "refs/heads/main",
      "state" => "prepared", "prepared_at" => "2026-09-15T12:00:00Z",
      "updated_at" => "2026-09-15T12:00:00Z" }
  end

  def with_server(document)
    server = TCPServer.new("127.0.0.1", 0)
    request_lines = nil
    body = nil
    thread = Thread.new do
      socket = server.accept
      request_lines = []
      request_lines << socket.gets until request_lines.last == "\r\n"
      length = request_lines.find { _1.downcase.start_with?("content-length:") }.to_s.split(":", 2).last.to_i
      body = socket.read(length) if length.positive?
      response = JSON.generate(document)
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" \
        "Content-Length: #{response.bytesize}\r\nConnection: close\r\n\r\n#{response}")
      socket.close
    end
    yield "http://127.0.0.1:#{server.local_address.ip_port}"
    thread.join
    [ request_lines, body ]
  ensure
    server&.close
  end

  def read_dispatch_summary
    response = { "schema_version" => "2", "request_id" => "99999999-9999-4999-8999-999999999999",
      "command" => "publication_preflight.get", "data" => preflight }
    captured = with_server(response) do |url|
      request = Kos::Cli::Parser.new.parse([ "publication-preflight", "get", "--repository", repository_id,
        "--preflight", preflight_id, "--json" ])
      result = Kos::Cli::Client.new(environment: { "KOS_API_URL" => url, "KOS_API_TOKEN" => "token" }).call(request)
      expect(result).to eq(response)
    end
    [ captured.first.first, Kos::Cli::Parser::COMMANDS.fetch(%w[publication prepare]).first ]
  end

  it "maps the v2 preflight read without changing the v1 publication command" do
    expect(read_dispatch_summary).to eq([
      "GET /api/v2/repositories/#{repository_id}/publication-preflights/#{preflight_id} HTTP/1.1\r\n",
      "publication.prepare"
    ])
  end

  def observed_request
    body = { "preflight_id" => preflight_id, "preconditions" => {
      "expected_lock_version" => 3, "attempt_id" => "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      "fencing_token" => 4 } }
    parser = Kos::Cli::Parser.new(input: StringIO.new(JSON.generate(body)))
    request = parser.parse([ "publication", "prepare-observed", "--repository", repository_id,
      "--input", "-", "--idempotency-key", "observed-key", "--json" ])
    [ request, body ]
  end

  def observed_dispatch_summary
    request, body = observed_request
    logical = request.slice("schema_version", "command", "repository_id", "body")
    expected = { "schema_version" => "2", "command" => "publication.prepare_observed",
      "repository_id" => repository_id, "body" => body }
    [ logical, Kos::Cli::Client::PATHS.fetch(request.fetch("command")), expected ]
  end

  it "forms the closed observed-publication mutation at the preflight path" do
    logical, path, expected = observed_dispatch_summary
    expect([ logical, path ]).to eq([ expected,
      "/api/v2/repositories/%<repository_id>s/publication-preflights/%<preflight_id>s/publication" ])
  end

  def recovery_dispatch_summary
    body = { "publication_id" => publication_id, "preconditions" => {
      "expected_lock_version" => 4, "attempt_id" => "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      "fencing_token" => 5 } }
    parser = Kos::Cli::Parser.new(input: StringIO.new(JSON.generate(body)))
    request = parser.parse([ "publication", "recover-base-moved", "--repository", repository_id,
      "--input", "-", "--idempotency-key", "recovery-key", "--json" ])
    [ request.slice("schema_version", "command", "repository_id", "body"),
      Kos::Cli::Client::PATHS.fetch(request.fetch("command")) ]
  end

  it "forms the closed base-moved recovery mutation at the publication path" do
    logical, path = recovery_dispatch_summary
    expect([ logical.fetch("schema_version"), logical.fetch("command"), logical.dig("body", "publication_id"),
      path ]).to eq([ "2", "publication.recover_base_moved", publication_id,
        "/api/v2/repositories/%<repository_id>s/publications/%<publication_id>s/recover-base-moved" ])
  end

  it "forms the atomic rebase reconciliation mutation at the effect path" do
    expect(rebase_reconciliation_dispatch).to eq([ "2", "effect.reconcile_rebase", publication_id,
      "/api/v2/repositories/%<repository_id>s/repository-effects/%<effect_id>s/reconcile-rebase" ])
  end

  def publication_result_read_dispatch
    request = Kos::Cli::Parser.new.parse([ "publication-result", "get", "--repository", repository_id,
      "--publication", publication_id, "--json" ])

    [ request.fetch("schema_version"), request.fetch("command"), request.fetch("body"),
      Kos::Cli::Client::PATHS.fetch(request.fetch("command")) ]
  end

  it "maps publication-result read by publication id" do
    expect(publication_result_read_dispatch).to eq([ "2", "publication_result.get",
      { "publication_id" => publication_id },
      "/api/v2/repositories/%<repository_id>s/publications/%<publication_id>s/result" ])
  end

  def publication_result_record_dispatch
    body = publication_result_record_body
    request = Kos::Cli::Parser.new(input: StringIO.new(JSON.generate(body))).parse(
      [ "publication-result", "record", "--repository", repository_id, "--input", "-",
        "--idempotency-key", "publication-result-key", "--json" ]
    )

    [ request.fetch("schema_version"), request.fetch("command"), request.fetch("body"),
      Kos::Cli::Client::PATHS.fetch(request.fetch("command")) ]
  end

  it "forms publication-result record with its path identity in the body" do
    expect(publication_result_record_dispatch).to eq([ "2", "publication_result.record",
      publication_result_record_body,
      "/api/v2/repositories/%<repository_id>s/publications/%<publication_id>s/result" ])
  end

  it "rejects a publication path option when recording" do
    parser = Kos::Cli::Parser.new(input: StringIO.new(JSON.generate(publication_result_record_body)))
    arguments = [ "publication-result", "record", "--repository", repository_id,
      "--publication", publication_id, "--input", "-", "--idempotency-key", "publication-result-key", "--json" ]

    expect { parser.parse(arguments) }.to raise_error(Kos::Cli::Error, "Arguments are malformed")
  end

  def rebase_reconciliation_dispatch
    body = { "effect_id" => publication_id, "head_sha" => "a" * 40,
      "rebase_evidence_digest" => "sha256:#{'a' * 64}",
      "worktree_evidence_digest" => "sha256:#{'b' * 64}", "preconditions" => {
        "expected_lock_version" => 4, "attempt_id" => "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
        "fencing_token" => 5 } }
    request = Kos::Cli::Parser.new(input: StringIO.new(JSON.generate(body))).parse(
      [ "effect", "reconcile-rebase", "--repository", repository_id, "--input", "-",
        "--idempotency-key", "rebase-reconcile-key", "--json" ]
    )

    [ request.fetch("schema_version"), request.fetch("command"), request.dig("body", "effect_id"),
      Kos::Cli::Client::PATHS.fetch(request.fetch("command")) ]
  end
end
