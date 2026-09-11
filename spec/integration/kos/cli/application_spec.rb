require "json"
require "open3"
require "socket"
require "spec_helper"
require "tempfile"
require_relative "../../../../lib/kos/cli"

RSpec.describe Kos::Cli::Application, :aggregate_failures do
  def bin
    File.expand_path("../../../../bin/kos", __dir__)
  end

  def token
    "cli-test-token"
  end

  def request_id
    "99999999-9999-4999-8999-999999999999"
  end

  def repository_id
    "33333333-3333-4333-8333-333333333333"
  end

  def resource_id
    "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  end

  def success(command, data)
    { "schema_version" => "1", "request_id" => request_id, "command" => command, "data" => data }
  end

  def failure(command, category: "not_found", code: "task_not_found")
    { "schema_version" => "1", "request_id" => request_id, "command" => command,
      "error" => { "category" => category, "code" => code, "message" => "Resource not found", "retryable" => false } }
  end

  def transient(command)
    value = failure(command, category: "transient", code: "transport_unavailable")
    value.fetch("error")["retryable"] = true
    value
  end

  def run_cli(url, *arguments, environment: {}, stdin_data: "")
    Open3.capture3({ "KOS_API_URL" => url, "KOS_API_TOKEN" => token,
      "KOS_API_TIMEOUT_SECONDS" => "2" }.merge(environment), bin, *arguments, stdin_data: stdin_data)
  end

  def with_server(responses, request_bodies: nil)
    server = TCPServer.new("127.0.0.1", 0)
    requests = []
    thread = Thread.new do
      responses.each do |response|
        socket = server.accept
        lines = []
        lines << socket.gets until lines.last == "\r\n"
        requests << lines
        if request_bodies
          length = lines.find { |line| line.downcase.start_with?("content-length:") }.to_s.split(":", 2).last.to_i
          request_bodies << socket.read(length)
        end
        if response == :close
          socket.close
          next
        end
        status, document = response
        body = document.is_a?(String) ? document : JSON.generate(document)
        socket.write("HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n" \
          "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        socket.close
      end
    end
    yield "http://127.0.0.1:#{server.local_address.ip_port}", requests
  ensure
    server&.close
    thread&.join(2)
  end

  it "uses environment transport settings and reserves stdout for one JSON result" do
    expect_successful_transport
  end

  it "maps every approved command to its exact GET endpoint" do
    command_cases.each { |arguments, command, path| expect_command_case(arguments, command, path) }
  end

  def command_cases
    [
      [ %w[task-type list --limit 1 --json], "task_type.list", "/api/v1/task-types?limit=1" ],
      [ %w[workflow list --limit 1 --json], "workflow.list", "/api/v1/workflow-versions?limit=1" ],
      [ [ "workflow", "get", "--workflow-version", resource_id, "--json" ], "workflow.get",
        "/api/v1/workflow-versions/#{resource_id}" ],
      [ [ "workflow", "export", "--workflow-version", resource_id, "--json" ], "workflow.export",
        "/api/v1/workflow-versions/#{resource_id}/export" ],
      [ %w[workflow-draft get --workflow quick-fix --json], "workflow_draft.get",
        "/api/v1/workflow-drafts/quick-fix" ],
      [ %w[workflow-draft validate --workflow quick-fix --json], "workflow_draft.validate",
        "/api/v1/workflow-drafts/quick-fix/validation" ],
      [ [ "task", "get", "--repository", repository_id, "--task", "KOS-000001", "--json" ], "task.get",
        "/api/v1/repositories/#{repository_id}/tasks/KOS-000001" ],
      [ [ "attempt", "get", "--repository", repository_id, "--attempt", resource_id, "--json" ], "attempt.get",
        "/api/v1/repositories/#{repository_id}/attempts/#{resource_id}" ],
      [ [ "worktree", "get", "--repository", repository_id, "--reservation", resource_id, "--json" ],
        "worktree.get", "/api/v1/repositories/#{repository_id}/worktree-reservations/#{resource_id}" ],
      [ [ "artifact", "list", "--repository", repository_id, "--task", "KOS-000001", "--limit", "1",
        "--json" ], "artifact.list", "/api/v1/repositories/#{repository_id}/tasks/KOS-000001/artifacts?limit=1" ]
    ]
  end

  def expect_command_case(arguments, command, path)
    code = { "workflow.get" => "workflow_version_not_found", "workflow.export" => "workflow_version_not_found",
      "workflow_draft.get" => "workflow_draft_not_found", "workflow_draft.validate" => "workflow_draft_not_found",
      "attempt.get" => "attempt_not_found", "worktree.get" => "reservation_not_found",
      "artifact.list" => "task_not_found" }.fetch(command, "task_not_found")
    with_server([ [ "404 Not Found", failure(command, code:) ] ]) do |url, requests|
      stdout, _stderr, status = run_cli(url, *arguments)
      expect(status.exitstatus).to eq(5)
      expect(JSON.parse(stdout).dig("error", "code")).to eq(code)
      expect(requests.first.first).to start_with("GET #{path} ")
    end
  end

  def expect_successful_transport
    response = success("task_type.list", "task_types" => [])
    with_server([ [ "200 OK", response ] ]) do |url, requests|
      stdout, stderr, status = run_cli(url, "task-type", "list", "--limit", "20", "--json")
      expect(status.exitstatus).to eq(0)
      expect(stderr).to be_empty
      expect(JSON.parse(stdout)).to eq(response)
      expect(stdout.lines.length).to eq(1)
      expect(requests.first.first).to start_with("GET /api/v1/task-types?limit=20 ")
      expect(requests.first.join).to include("Authorization: Bearer #{token}\r\n", "Accept: application/json\r\n")
    end
  end

  def expect_malformed_http_retries
    sleeper = class_double(Kernel, sleep: nil)
    client = Kos::Cli::Client.new(environment: { "KOS_API_TOKEN" => token }, sleeper:, random: Random.new(1))
    request = Kos::Cli::Parser.new.parse(%w[task-type list --limit 1 --json])
    allow(client).to receive(:perform).exactly(3).times.and_raise(Net::HTTPBadResponse.new("malformed"))

    expect(client.call(request).dig("error", "code")).to eq("transport_unavailable")
    expect(sleeper).to have_received(:sleep).twice
  end

  it "retries transport and transient read failures no more than three total attempts" do
    final = success("task_type.list", "task_types" => [])
    with_server([ :close, [ "503 Service Unavailable", transient("task_type.list") ], [ "200 OK", final ] ]) do |url, requests|
      stdout, _stderr, status = run_cli(url, "task-type", "list", "--limit", "1", "--json")

      expect([ status.exitstatus, requests.length, JSON.parse(stdout) ]).to eq([ 0, 3, final ])
    end
  end

  it "does not retry non-transient failures" do
    expect_no_retry
  end

  it "maps catalog mutations to POST with the complete request and idempotency headers" do
    mutation_cases.each { |arguments, command, path, body| expect_mutation_case(arguments, command, path, body) }
  end

  it "reads mutation input from stdin" do
    expect_stdin_mutation
  end

  it "reads mutation input from a file" do
    expect_file_mutation
  end

  def expect_stdin_mutation
    body = { "workflow_id" => "quick-fix", "expected_lock_version" => 0 }
    response = failure("workflow.publish", category: "conflict", code: "stale_lock_version")
    with_server([ [ "409 Conflict", response ] ]) do |url, requests|
      stdout, _stderr, status = run_cli(url, "workflow", "publish", "--input", "-", "--idempotency-key",
        "publish-key-1", "--json", stdin_data: JSON.generate(body))
      expect([ status.exitstatus, requests.first.first, JSON.parse(stdout) ])
        .to eq([ 6, "POST /api/v1/workflow-drafts/quick-fix/publication HTTP/1.1\r\n", response ])
    end
  end

  def expect_file_mutation
    body = { "workflow_id" => "quick-fix", "expected_lock_version" => 0 }
    Tempfile.create([ "workflow", ".json" ]) do |file|
      file.write(JSON.generate(body))
      file.flush
      response = failure("workflow.publish", category: "conflict", code: "stale_lock_version")
      with_server([ [ "409 Conflict", response ] ]) do |url, _requests|
        stdout, = run_cli(url, "workflow", "publish", "--input", file.path, "--idempotency-key",
          "publish-key-1", "--json")
        expect(JSON.parse(stdout)).to eq(response)
      end
    end
  end

  it "retries a repository mutation with the same key and body" do
    expect_mutation_retry
  end

  it "returns transport_unavailable after three malformed HTTP responses" do
    expect_malformed_http_retries
  end

  def expect_no_retry
    response = failure("task.get")
    with_server([ [ "404 Not Found", response ] ]) do |url, requests|
      stdout, _stderr, status = run_cli(url, "task", "get", "--repository", repository_id,
        "--task", "KOS-000001", "--json")
      expect([ status.exitstatus, requests.length, JSON.parse(stdout) ]).to eq([ 5, 1, response ])
    end
  end

  def mutation_cases
    definition = JSON.parse(File.read(File.expand_path("../../../fixtures/workflow_definitions/v1/valid/quick-fix.json",
      __dir__)))
    [
      [ %w[workflow-draft import], "workflow_draft.import", "/api/v1/workflow-drafts/quick-fix",
        { "workflow_id" => "quick-fix", "definition" => definition, "expected_lock_version" => 0 } ],
      [ %w[workflow publish], "workflow.publish", "/api/v1/workflow-drafts/quick-fix/publication",
        { "workflow_id" => "quick-fix", "expected_lock_version" => 0 } ],
      [ %w[workflow activate], "workflow.activate", "/api/v1/task-types/quick-fix/current-workflow",
        { "task_type" => "quick-fix", "workflow_version_id" => resource_id, "expected_lock_version" => 0 } ],
      [ [ "task", "create", "--repository", repository_id ], "task.create",
        "/api/v1/repositories/#{repository_id}/tasks",
        { "title" => "Repair timeout", "task_type" => "quick-fix" } ]
    ]
  end

  def expect_mutation_case(arguments, command, path, body)
    response = failure(command, category: "conflict", code: "stale_lock_version")
    bodies = []
    with_server([ [ "409 Conflict", response ] ], request_bodies: bodies) do |url, requests|
      stdout, _stderr, status = run_cli(url, *arguments, "--input", "-", "--idempotency-key", "catalog-key-1",
        "--json", stdin_data: JSON.generate(body))
      expected = { "schema_version" => "1", "command" => command, "body" => body }
      expected["repository_id"] = repository_id if command == "task.create"
      expect([ status.exitstatus, requests.first.first, JSON.parse(bodies.first), JSON.parse(stdout) ])
        .to eq([ 6, "POST #{path} HTTP/1.1\r\n", expected, response ])
      expect(requests.first.join).to include("Content-Type: application/json", "Idempotency-Key: catalog-key-1")
    end
  end

  def expect_mutation_retry
    body = { "title" => "Repair timeout", "task_type" => "quick-fix" }
    final = failure("task.create", category: "conflict", code: "task_type_unavailable")
    bodies = []
    with_server([ [ "503 Service Unavailable", transient("task.create") ],
      [ "503 Service Unavailable", transient("task.create") ], [ "409 Conflict", final ] ],
      request_bodies: bodies) do |url, requests|
      _stdout, _stderr, status = run_cli(url, "task", "create", "--repository", repository_id,
        "--input", "-", "--idempotency-key", "task-create-key-1", "--json", stdin_data: JSON.generate(body))
      expect([ status.exitstatus, requests.length, bodies.uniq.length,
        requests.map { |lines| lines.join.scan(/Idempotency-Key: task-create-key-1/).length } ])
        .to eq([ 6, 3, 1, [ 1, 1, 1 ] ])
    end
  end

  it "validates arguments before transport with a stable exit" do
    stdout, stderr, status = Open3.capture3({ "KOS_API_TOKEN" => token }, bin, "task", "get", "--json")
    document = JSON.parse(stdout)
    expect([ status.exitstatus, document.dig("error", "code") ]).to eq([ 2, "malformed_input" ])
    expect(stderr).not_to be_empty
  end

  it "rejects duplicate mutation input members before transport" do
    stdout, _stderr, status = run_cli("http://127.0.0.1:1", "workflow", "publish", "--input", "-",
      "--idempotency-key", "publish-key-1", "--json", stdin_data: '{"expected_lock_version":0,"expected_lock_version":1}')
    expect([ status.exitstatus, JSON.parse(stdout).dig("error", "code") ]).to eq([ 2, "malformed_input" ])
  end

  it "requires the token environment variable with a stable exit" do
    stdout, _stderr, status = Open3.capture3({}, bin, "task-type", "list", "--limit", "1", "--json")
    expect([ status.exitstatus, JSON.parse(stdout).dig("error", "code") ])
      .to eq([ 3, "authentication_required" ])
  end

  it "rejects a response outside the versioned schemas as an internal failure" do
    with_server([ [ "200 OK", "{\"unexpected\":true}" ] ]) do |url, _requests|
      stdout, stderr, status = run_cli(url, "task-type", "list", "--limit", "1", "--json")

      expect([ status.exitstatus, JSON.parse(stdout).dig("error", "code") ]).to eq([ 1, "internal_error" ])
      expect(stderr).to include("schema validation")
    end
  end
end
