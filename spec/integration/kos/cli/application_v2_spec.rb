require "json"
require "socket"
require "stringio"
require "spec_helper"
require_relative "../../../../lib/kos/cli"

RSpec.describe Kos::Cli::Application, :aggregate_failures do
  def repository_id = "33333333-3333-4333-8333-333333333333"
  def preflight_id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

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
end
