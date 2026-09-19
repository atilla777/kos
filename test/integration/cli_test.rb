require "test_helper"
require "json"
require "open3"
require "rbconfig"
require "socket"
require "tempfile"

class CliTest < ActiveSupport::TestCase
  test "prints top-level and command help without configuration" do
    output, error, status = run_cli("--help", environment: {})

    assert_predicate status, :success?
    assert_includes output, "Usage: kos <resource> <action> [options]"
    assert_empty error

    output, error, status = run_cli("task", "report-attempt", "--help", environment: {})

    assert_predicate status, :success?
    assert_includes output, "--claim-version VERSION"
    assert_empty error
  end

  test "maps every API operation to its HTTP request" do
    Tempfile.create([ "workflow", ".json" ]) do |workflow_file|
      workflow_file.write(JSON.generate(steps: [ { id: "develop" } ]))
      workflow_file.flush

      Tempfile.create([ "description", ".md" ]) do |description_file|
        description_file.write("# Task\n\nMultiline description.\n")
        description_file.flush

        cases = [
          [ [ "project", "create", "--name", "KOS", "--remote-url", "git@example.test:kos.git",
            "--default-branch", "main" ], "POST", "/projects",
            { "name" => "KOS", "remote_url" => "git@example.test:kos.git", "default_branch" => "main" } ],
          [ [ "workflow", "create", "--name", "Default", "--definition-file", workflow_file.path ],
            "POST", "/workflows", { "name" => "Default", "definition_json" => { "steps" => [ { "id" => "develop" } ] } } ],
          [ [ "task-type", "create", "--name", "Feature", "--workflow-id", "4" ],
            "POST", "/task_types", { "name" => "Feature", "workflow_id" => 4 } ],
          [ [ "task-type", "update", "7", "--workflow-id", "5" ],
            "PATCH", "/task_types/7", { "workflow_id" => 5 } ],
          [ [ "task", "create", "--project-id", "1", "--task-type-id", "2", "--title", "CLI task",
            "--description-file", description_file.path, "--parent-id", "3", "--blocker-id", "4", "--blocker-id", "5" ],
            "POST", "/tasks", { "project_id" => 1, "task_type_id" => 2, "title" => "CLI task",
              "description_markdown" => "# Task\n\nMultiline description.\n", "parent_id" => 3, "blocker_ids" => [ 4, 5 ] } ],
          [ [ "task", "update", "9", "--description-file", "-", "--clear-parent", "--clear-blockers" ],
            "PATCH", "/tasks/9", { "description_markdown" => "Updated through STDIN\n", "parent_id" => nil, "blocker_ids" => [] },
            "Updated through STDIN\n" ],
          [ [ "task", "show", "9" ], "GET", "/tasks/9", nil ],
          [ [ "task", "claim-next", "--project-id", "1", "--owner-id", "session-1" ],
            "POST", "/tasks/claim-next", { "project_id" => 1, "owner_id" => "session-1" } ],
          [ [ "task", "resume", "9", "--owner-id", "session-2", "--takeover-confirmed" ],
            "POST", "/tasks/9/resume", { "owner_id" => "session-2", "takeover_confirmed" => true } ],
          [ [ "task", "report-attempt", "9", "--owner-id", "session-2", "--claim-version", "6",
            "--step", "develop", "--outcome", "ready" ],
            "POST", "/tasks/9/report-attempt", { "owner_id" => "session-2", "claim_version" => 6,
              "step" => "develop", "outcome" => "ready" } ],
          [ [ "task", "cancel", "9" ], "POST", "/tasks/9/cancel", {} ]
        ]

        cases.each do |arguments, expected_method, expected_path, expected_payload, stdin_data|
          output, error, status, request = run_cli_with_server(*arguments, stdin_data: stdin_data.to_s)

          assert_predicate status, :success?, arguments.join(" ")
          assert_equal "{\"task\":{\"id\":9}}", output
          assert_empty error
          assert_equal expected_method, request.fetch(:method)
          assert_equal "/api#{expected_path}", request.fetch(:path)
          assert_equal "Bearer test-secret", request.fetch(:headers).fetch("authorization")
          expected_payload.nil? ? assert_nil(request.fetch(:body)) : assert_equal(expected_payload, request.fetch(:body))
        end
      end
    end
  end

  test "treats no content as an empty successful response" do
    output, error, status, = run_cli_with_server("task", "claim-next", "--project-id", "1", "--owner-id", "session",
      response_status: 204, response_body: "")

    assert_predicate status, :success?
    assert_empty output
    assert_empty error
  end

  test "preserves server error JSON and returns failure" do
    response_body = "{\"error\":\"conflict\",\"message\":\"stale owner\"}"
    output, error, status, = run_cli_with_server("task", "show", "9", response_status: 409,
      response_body:)

    assert_equal 1, status.exitstatus
    assert_equal response_body, output
    assert_empty error
  end

  test "reports configuration usage local input and transport errors as JSON without secrets" do
    _output, error, status = run_cli("task", "show", "1", environment: {})
    assert_equal 2, status.exitstatus
    assert_equal "configuration_error", JSON.parse(error).fetch("error")

    _output, error, status = run_cli("task", "create", "--project-id", "not-an-id",
      environment: { "KOS_API_TOKEN" => "hidden-secret" })
    assert_equal 2, status.exitstatus
    assert_equal "usage_error", JSON.parse(error).fetch("error")
    assert_not_includes error, "hidden-secret"

    Tempfile.create([ "invalid-workflow", ".json" ]) do |file|
      file.write("{")
      file.flush
      _output, error, status = run_cli("workflow", "create", "--name", "Invalid", "--definition-file", file.path,
        environment: { "KOS_API_TOKEN" => "hidden-secret" })
      assert_equal 2, status.exitstatus
      assert_equal "local_input_error", JSON.parse(error).fetch("error")
      assert_not_includes error, "hidden-secret"
    end

    unavailable_server = TCPServer.new("127.0.0.1", 0)
    port = unavailable_server.local_address.ip_port
    unavailable_server.close
    _output, error, status = run_cli("task", "show", "1", environment: {
      "KOS_API_URL" => "http://127.0.0.1:#{port}", "KOS_API_TOKEN" => "hidden-secret"
    })
    assert_equal 3, status.exitstatus
    assert_equal "transport_error", JSON.parse(error).fetch("error")
    assert_not_includes error, "hidden-secret"
  end

  test "normalizes UTF-8 input and rejects invalid bytes without a stack trace" do
    output, error, status, request = run_cli_with_server("task", "update", "9", "--description-file", "-",
      stdin_data: "Привет\n", cli_environment: { "LANG" => "C", "LC_ALL" => "C" })

    assert_predicate status, :success?
    assert_equal "Привет\n", request.dig(:body, "description_markdown")
    assert_equal "{\"task\":{\"id\":9}}", output
    assert_empty error

    Tempfile.create("invalid-markdown") do |file|
      file.binmode
      file.write("\xFF".b)
      file.flush
      _output, error, status = run_cli("task", "update", "9", "--description-file", file.path,
        environment: { "KOS_API_TOKEN" => "test-secret" })

      assert_equal 2, status.exitstatus
      assert_equal "local_input_error", JSON.parse(error).fetch("error")
      assert_not_includes error, "cli.rb:"
    end

    _output, error, status = run_cli("task", "show", "9", environment: { "KOS_API_TOKEN" => "\xFF".b })
    assert_equal 2, status.exitstatus
    assert_equal "configuration_error", JSON.parse(error).fetch("error")
    assert_not_includes error, "cli.rb:"

    _output, error, status = run_cli("task", "show", "9", "--\xFF".b,
      environment: { "KOS_API_TOKEN" => "test-secret" })
    assert_equal 2, status.exitstatus
    assert_equal "usage_error", JSON.parse(error).fetch("error")
    assert_not_includes error, "cli.rb:"

    _output, error, status = run_cli("task", "update", "9", "--description-file", "/tmp/\xFF".b,
      environment: { "KOS_API_TOKEN" => "test-secret" })
    assert_equal 2, status.exitstatus
    assert_equal "usage_error", JSON.parse(error).fetch("error")
    assert_not_includes error, "cli.rb:"
  end

  private

  def run_cli_with_server(*arguments, response_status: 200, response_body: "{\"task\":{\"id\":9}}", stdin_data: "",
    cli_environment: {})
    server = TCPServer.new("127.0.0.1", 0)
    requests = Queue.new
    thread = Thread.new do
      socket = server.accept
      request_line = socket.gets
      headers = {}
      while (line = socket.gets) && line != "\r\n"
        name, value = line.split(":", 2)
        headers[name.downcase] = value.strip
      end
      raw_body = socket.read(headers.fetch("content-length", "0").to_i)
      requests << {
        method: request_line.split.fetch(0),
        path: request_line.split.fetch(1),
        headers:,
        body: raw_body.empty? ? nil : JSON.parse(raw_body)
      }
      reason = { 200 => "OK", 204 => "No Content", 409 => "Conflict" }.fetch(response_status)
      socket.write("HTTP/1.1 #{response_status} #{reason}\r\nContent-Type: application/json\r\n" \
        "Content-Length: #{response_body.bytesize}\r\nConnection: close\r\n\r\n#{response_body}")
      socket.close
    ensure
      server.close
    end
    thread.report_on_exception = false

    environment = cli_environment.merge(
      "KOS_API_URL" => "http://127.0.0.1:#{server.local_address.ip_port}/api/",
      "KOS_API_TOKEN" => "test-secret"
    )
    output, error, status = run_cli(*arguments, environment:, stdin_data:)
    unless thread.join(2)
      server.close
      thread.kill
      flunk("CLI did not send a request: #{arguments.join(" ")} (stderr: #{error.inspect})")
    end
    [ output, error, status, requests.pop ]
  end

  def run_cli(*arguments, environment:, stdin_data: "")
    isolated_environment = { "RUBYOPT" => nil, "RUBYLIB" => nil }.merge(environment)
    Open3.capture3(isolated_environment, RbConfig.ruby, "--disable-gems", Rails.root.join("bin/kos").to_s, *arguments,
      stdin_data:)
  end
end
