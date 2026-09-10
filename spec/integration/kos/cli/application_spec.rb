require "json"
require "open3"
require "socket"
require "spec_helper"
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

  def run_cli(url, *arguments, environment: {})
    Open3.capture3({ "KOS_API_URL" => url, "KOS_API_TOKEN" => token,
      "KOS_API_TIMEOUT_SECONDS" => "2" }.merge(environment), bin, *arguments)
  end

  def with_server(responses)
    server = TCPServer.new("127.0.0.1", 0)
    requests = []
    thread = Thread.new do
      responses.each do |response|
        socket = server.accept
        lines = []
        lines << socket.gets until lines.last == "\r\n"
        requests << lines
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
      [ %w[workflow-draft get --workflow quick-fix --json], "workflow_draft.get",
        "/api/v1/workflow-drafts/quick-fix" ],
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
    code = { "workflow.get" => "workflow_version_not_found", "workflow_draft.get" => "workflow_draft_not_found",
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

  it "validates arguments before transport with a stable exit" do
    stdout, stderr, status = Open3.capture3({ "KOS_API_TOKEN" => token }, bin, "task", "get", "--json")
    document = JSON.parse(stdout)
    expect([ status.exitstatus, document.dig("error", "code") ]).to eq([ 2, "malformed_input" ])
    expect(stderr).not_to be_empty
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
