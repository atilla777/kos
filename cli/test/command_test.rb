require "minitest/autorun"
require "stringio"
require "tempfile"
require_relative "../lib/kos_cli"

class CommandTest < Minitest::Test
  class FakeClient
    class << self
      attr_accessor :requests, :response
    end

    def initialize(url)
      self.class.requests = [ [ :url, url ] ]
    end

    def request(method, path, body: nil, query: nil)
      self.class.requests << [ method, path, body, query ]
      self.class.response || [ 200, { "data" => {} } ]
    end
  end

  class ConnectionFailureClient
    def initialize(_url); end

    def request(*)
      raise KosCli::ConnectionError, "Unable to receive a valid response from KOS API."
    end
  end

  class AmbiguousFailureClient
    def initialize(_url); end

    def request(*)
      raise KosCli::AmbiguousResultError.new(
        "The request may have completed.",
        verification_command: "kos task current"
      )
    end
  end

  def setup
    @stdout = StringIO.new
    @stderr = StringIO.new
    FakeClient.response = nil
  end

  def test_creates_workflow_and_routes_subagent_to_a_step_packet
    definition = '{"name":"Feature","steps":[{"name":"Plan","instructions":"Plan it.","executor":"subagent","model_tier":"advanced","inputs":[],"outputs":["plan"]}]}'
    command_with_input = KosCli::Command.new(
      stdin: StringIO.new(definition), stdout: @stdout, stderr: @stderr, client_class: FakeClient
    )
    assert_equal 0, command_with_input.run(%w[--project github.com/owner/project workflow create --file -])
    assert_equal [ :post, "/workflows", {
      project: "github.com/owner/project", name: "Feature",
      steps: [ { "name" => "Plan", "instructions" => "Plan it.", "executor" => "subagent",
        "model_tier" => "advanced", "inputs" => [], "outputs" => [ "plan" ] } ]
    }, nil ], FakeClient.requests.last

    assert_equal 0, command.run(%w[--project github.com/owner/project --session agent task claim 42 --route])
    assert_equal "route", FakeClient.requests.last[2][:context]

    assert_equal 0, command.run(%w[--project github.com/owner/project task step show 42])
    assert_equal [ :get, "/tasks/42/step", nil, { project: "github.com/owner/project" } ], FakeClient.requests.last

    assert_equal 0, command.run(%w[--project github.com/owner/project --claim secret task advance 42 --expected-step 0])
    assert_equal 0, FakeClient.requests.last[2][:expected_step]
    assert_equal "secret", FakeClient.requests.last[2][:claim_id]
  end

  def test_creates_project_from_explicit_repository
    exit_code = command.run(%w[
      --project git@github.com:Owner/Project.git
      project create --name Project
    ])

    assert_equal 0, exit_code
    assert_equal [
      :post,
      "/projects",
      { project: { name: "Project", repository: "github.com/owner/project" } },
      nil
    ], FakeClient.requests.last
    assert_equal "", @stderr.string
  end

  def test_writes_api_errors_as_json_to_stdout
    FakeClient.response = [ 409, { "error" => { "code" => "repository_taken" } } ]

    exit_code = command.run(%w[--project github.com/owner/project project create])

    assert_equal KosCli::Command::CONFLICT_EXIT, exit_code
    assert_equal "repository_taken", JSON.parse(@stdout.string).dig("error", "code")
    assert_equal "", @stderr.string
  end

  def test_reports_usage_errors_as_json_without_echoing_credentials
    exit_code = command.run(%w[--project file:///secret/project.git project show])

    assert_equal 2, exit_code
    error = JSON.parse(@stdout.string)
    assert_equal "invalid_usage", error.dig("error", "code")
    refute_includes error.dig("error", "message"), "secret"
    assert_equal "", @stderr.string
  end

  def test_uses_stable_exit_codes_for_api_connection_and_ambiguous_errors
    FakeClient.response = [ 422, { "error" => { "code" => "validation_failed" } } ]
    assert_equal KosCli::Command::API_ERROR_EXIT,
      command.run(%w[--project github.com/owner/project project create])

    setup
    connection_command = KosCli::Command.new(
      stdout: @stdout, stderr: @stderr, client_class: ConnectionFailureClient
    )
    assert_equal KosCli::Command::CONNECTION_ERROR_EXIT,
      connection_command.run(%w[project list])
    assert_equal "connection_error", JSON.parse(@stdout.string).dig("error", "code")

    setup
    ambiguous_command = KosCli::Command.new(
      stdout: @stdout, stderr: @stderr, client_class: AmbiguousFailureClient
    )
    assert_equal KosCli::Command::AMBIGUOUS_RESULT_EXIT,
      ambiguous_command.run(%w[project list])
    result = JSON.parse(@stdout.string)
    assert_equal "ambiguous_result", result.dig("error", "code")
    assert_equal "kos task current", result.dig("error", "details", "verification_command")
  end

  def test_successful_no_ready_tasks_is_json_and_exits_zero
    FakeClient.response = [ 200, { "data" => { "task" => nil, "reason" => "no_ready_tasks" } } ]

    exit_code = command.run(%w[--project github.com/owner/project task ready])

    assert_equal 0, exit_code
    assert_nil JSON.parse(@stdout.string).dig("data", "task")
    assert_equal "", @stderr.string
  end

  def test_explicit_global_options_override_environment
    with_environment("KOS_API_URL", "not a URL") do
      with_environment("KOS_PROJECT", "file:///secret/project.git") do
        with_environment("KOS_SESSION_ID", "environment-session") do
          with_environment("KOS_CLAIM_ID", "environment-claim") do
            exit_code = command.run(%w[
              --url http://explicit.example:4000
              --project github.com/explicit/project
              --session explicit-session
              --claim explicit-claim
              task update 42 --work-summary Progress
            ])

            assert_equal 0, exit_code
            assert_equal [ :url, "http://explicit.example:4000" ], FakeClient.requests.first
            assert_equal "github.com/explicit/project", FakeClient.requests.last[2][:project]
            assert_equal "explicit-claim", FakeClient.requests.last[2][:claim_id]
          end
        end
      end
    end
  end

  def test_uses_project_from_environment
    with_environment("KOS_PROJECT", "git@github.com:Owner/Project.git") do
      assert_equal 0, command.run(%w[task list])
    end

    assert_equal "github.com/owner/project", FakeClient.requests.last[3][:project]
  end

  def test_redacts_claim_from_api_error_output
    FakeClient.response = [
      409,
      { "error" => { "code" => "claim_mismatch", "message" => "Rejected secret-claim-value" } }
    ]

    exit_code = command.run(%w[
      --project github.com/owner/project --claim secret-claim-value
      task renew 42
    ])

    assert_equal KosCli::Command::CONFLICT_EXIT, exit_code
    refute_includes @stdout.string, "secret-claim-value"
    assert_includes @stdout.string, "[REDACTED]"
    assert_equal "", @stderr.string
  end

  def test_does_not_redact_claim_from_success_output
    FakeClient.response = [ 200, { "data" => { "task" => { "claim_id" => "current-claim" } } } ]

    exit_code = command.run(%w[
      --project github.com/owner/project --claim current-claim
      task renew 42
    ])

    assert_equal 0, exit_code
    assert_equal "current-claim", JSON.parse(@stdout.string).dig("data", "task", "claim_id")
  end

  def test_creates_task_with_flat_body_and_explicit_project
    exit_code = command.run([
      "--project", "git@github.com:Owner/Project.git",
      "task", "create",
      "--kind", "feature",
      "--title", "Create tasks",
      "--description", "Implement task CRUD",
      "--work-summary", "Started",
      "--group-id", "7", "--workflow-id", "3"
    ])

    assert_equal 0, exit_code
    assert_equal [
      :post,
      "/tasks",
      {
        project: "github.com/owner/project",
        kind: "feature",
        title: "Create tasks",
        description: "Implement task CRUD",
        work_summary: "Started",
        task_group_id: 7,
        workflow_id: 3
      },
      nil
    ], FakeClient.requests.last
    assert_equal "", @stderr.string
  end

  def test_creates_task_with_blockers
    exit_code = command.run(%w[
      --project github.com/owner/project task create
      --kind feature --title Work --description Implement --workflow-id 3
      --blocked-by-ids 7,9
    ])

    assert_equal 0, exit_code
    assert_equal [ 7, 9 ], FakeClient.requests.last[2][:blocked_by_ids]
  end

  def test_group_crud_uses_project_scoped_api
    exit_code = command.run([
      "--project", "github.com/owner/project", "group", "create",
      "--kind", "epic", "--title", "Groups", "--description", "Implement groups"
    ])
    assert_equal 0, exit_code
    assert_equal [
      :post,
      "/task-groups",
      { project: "github.com/owner/project", kind: "epic", title: "Groups", description: "Implement groups" },
      nil
    ], FakeClient.requests.last

    command.run(%w[--project github.com/owner/project group list --limit 12 --after-id 4])
    assert_equal [ :get, "/task-groups", nil, { project: "github.com/owner/project", limit: 12, after_id: 4 } ], FakeClient.requests.last

    command.run(%w[--project github.com/owner/project group show 7])
    assert_equal [ :get, "/task-groups/7", nil, { project: "github.com/owner/project" } ], FakeClient.requests.last

    command.run(%w[--project github.com/owner/project group update 7 --title Updated])
    assert_equal [ :patch, "/task-groups/7", { project: "github.com/owner/project", title: "Updated" }, nil ], FakeClient.requests.last

    command.run(%w[--project github.com/owner/project group delete 7])
    assert_equal [ :delete, "/task-groups/7", nil, { project: "github.com/owner/project" } ], FakeClient.requests.last
  end

  def test_group_create_requires_all_fields
    exit_code = command.run(%w[
      --project github.com/owner/project group create --kind epic --title Groups
    ])

    assert_usage_error(exit_code)
    assert_equal 1, FakeClient.requests.length
  end

  def test_creates_task_using_current_git_repository
    with_current_repository("git.example.com/Team/Project") do
      exit_code = command.run(%w[
        task create --kind bug --title Broken --description Fix --workflow-id 3
      ])

      assert_equal 0, exit_code
    end

    assert_equal "git.example.com/Team/Project", FakeClient.requests.last[2][:project]
    assert_equal 2, FakeClient.requests.length
  end

  def test_lists_tasks_with_default_pagination
    exit_code = command.run(%w[
      --project github.com/owner/project task list
    ])

    assert_equal 0, exit_code
    assert_equal [
      :get,
      "/tasks",
      nil,
      { project: "github.com/owner/project", limit: 50 }
    ], FakeClient.requests.last
  end

  def test_lists_tasks_with_explicit_pagination
    exit_code = command.run(%w[
      --project github.com/owner/project task list --limit 12 --after-id 41
    ])

    assert_equal 0, exit_code
    assert_equal [
      :get,
      "/tasks",
      nil,
      { project: "github.com/owner/project", limit: 12, after_id: 41 }
    ], FakeClient.requests.last
  end

  def test_lists_ready_tasks_with_server_side_filters
    exit_code = command.run(%w[
      --project github.com/owner/project task ready
      --kind feature --group-id 7 --limit 12 --after-id 41
    ])

    assert_equal 0, exit_code
    assert_equal [
      :get,
      "/tasks/ready",
      nil,
      { project: "github.com/owner/project", limit: 12, kind: "feature", task_group_id: 7, after_id: 41 }
    ], FakeClient.requests.last
  end

  def test_claim_next_sends_one_mutating_request_with_session_and_filters
    exit_code = command.run(%w[
      --project github.com/owner/project --session agent-1
      task claim-next --kind feature --group-id 7
    ])

    assert_equal 0, exit_code
    assert_equal [
      :post,
      "/tasks/claim-next",
      {
        project: "github.com/owner/project",
        session_id: "agent-1",
        kind: "feature",
        task_group_id: 7
      },
      nil
    ], FakeClient.requests.last
  end

  def test_claim_and_current_use_the_session_from_the_environment
    with_environment("KOS_SESSION_ID", "agent-from-env") do
      assert_equal 0, command.run(%w[--project github.com/owner/project task claim 42])
      assert_equal [
        :post,
        "/tasks/42/claim",
        { project: "github.com/owner/project", session_id: "agent-from-env" },
        nil
      ], FakeClient.requests.last

      assert_equal 0, command.run(%w[--project github.com/owner/project task current])
      assert_equal [
        :get,
        "/tasks/current",
        nil,
        { project: "github.com/owner/project", session_id: "agent-from-env" }
      ], FakeClient.requests.last
    end
  end

  def test_explicit_session_overrides_environment_and_claim_requires_a_session
    with_environment("KOS_SESSION_ID", "agent-from-env") do
      exit_code = command.run(%w[
        --project github.com/owner/project --session explicit-agent task claim 42
      ])
      assert_equal 0, exit_code
      assert_equal "explicit-agent", FakeClient.requests.last[2][:session_id]
    end

    setup
    exit_code = command.run(%w[--project github.com/owner/project task claim 42])
    assert_usage_error(exit_code)
    assert_equal 1, FakeClient.requests.length
  end

  def test_claim_protected_transitions_use_the_claim_from_the_environment
    with_environment("KOS_CLAIM_ID", "current-claim") do
      %w[renew release complete].each do |operation|
        setup
        arguments = %W[--project github.com/owner/project task #{operation} 42]
        arguments.concat([ "--work-summary", "Result" ]) unless operation == "renew"

        assert_equal 0, command.run(arguments)
        assert_equal :post, FakeClient.requests.last[0]
        assert_equal "/tasks/42/#{operation}", FakeClient.requests.last[1]
        assert_equal "current-claim", FakeClient.requests.last[2][:claim_id]
        assert_equal "Result", FakeClient.requests.last[2][:work_summary] unless operation == "renew"
      end
    end
  end

  def test_explicit_claim_overrides_environment_and_is_required_for_protected_transitions
    with_environment("KOS_CLAIM_ID", "environment-claim") do
      exit_code = command.run(%w[
        --project github.com/owner/project --claim explicit-claim task renew 42
      ])
      assert_equal 0, exit_code
      assert_equal "explicit-claim", FakeClient.requests.last[2][:claim_id]
    end

    setup
    exit_code = command.run(%w[--project github.com/owner/project task renew 42])
    assert_usage_error(exit_code)
    assert_equal 1, FakeClient.requests.length
  end

  def test_reopen_does_not_require_a_claim
    exit_code = command.run(%w[--project github.com/owner/project task reopen 42])

    assert_equal 0, exit_code
    assert_equal [
      :post,
      "/tasks/42/reopen",
      { project: "github.com/owner/project" },
      nil
    ], FakeClient.requests.last
  end

  def test_shows_task_with_project_query_without_project_lookup
    exit_code = command.run(%w[
      --project github.com/owner/project task show 42
    ])

    assert_equal 0, exit_code
    assert_equal [
      [ :url, ENV.fetch("KOS_API_URL", KosCli::Command::DEFAULT_URL) ],
      [ :get, "/tasks/42", nil, { project: "github.com/owner/project" } ]
    ], FakeClient.requests
  end

  def test_task_context_commands_forward_independent_continuation_cursors
    context_options = %w[
      --context-limit 10
      --artifact-after-id 11
      --blocked-by-after-id 12
      --dependency-artifact-after-id 13
      --blocks-after-id 14
    ]
    expected = {
      context_limit: 10,
      artifact_after_id: 11,
      blocked_by_after_id: 12,
      dependency_artifact_after_id: 13,
      blocks_after_id: 14
    }

    command.run([ "--project", "github.com/owner/project", "task", "show", "42", *context_options ])
    assert_equal({ project: "github.com/owner/project", **expected }, FakeClient.requests.last[3])

    command.run([
      "--project", "github.com/owner/project", "--session", "agent-1",
      "task", "current", *context_options
    ])
    assert_equal({ project: "github.com/owner/project", session_id: "agent-1", **expected }, FakeClient.requests.last[3])

    command.run([
      "--project", "github.com/owner/project", "--session", "agent-1",
      "task", "claim", "42", *context_options
    ])
    assert_equal({ project: "github.com/owner/project", session_id: "agent-1", **expected }, FakeClient.requests.last[2])
  end

  def test_updates_task_with_only_mutable_fields_and_flat_body
    exit_code = command.run([
      "--project", "github.com/owner/project",
      "task", "update", "42",
      "--title", "Updated title",
      "--description", "Updated description",
      "--work-summary", "In progress",
      "--kind", "bug"
    ])

    assert_equal 0, exit_code
    assert_equal [
      :patch,
      "/tasks/42",
      {
        project: "github.com/owner/project",
        title: "Updated title",
        description: "Updated description",
        work_summary: "In progress",
        kind: "bug"
      },
      nil
    ], FakeClient.requests.last
  end

  def test_task_update_sends_an_optional_claim_for_in_progress_work
    exit_code = command.run(%w[
      --project github.com/owner/project --claim current-claim
      task update 42 --work-summary Progress
    ])

    assert_equal 0, exit_code
    assert_equal "current-claim", FakeClient.requests.last[2][:claim_id]
    assert_equal "Progress", FakeClient.requests.last[2][:work_summary]
  end

  def test_task_update_can_change_or_remove_group
    exit_code = command.run(%w[
      --project github.com/owner/project task update 42 --group-id 7
    ])
    assert_equal 0, exit_code
    assert_equal 7, FakeClient.requests.last[2][:task_group_id]

    exit_code = command.run(%w[
      --project github.com/owner/project task update 42 --no-group
    ])
    assert_equal 0, exit_code
    assert_nil FakeClient.requests.last[2][:task_group_id]
  end

  def test_task_update_can_replace_or_clear_blockers
    exit_code = command.run(%w[
      --project github.com/owner/project task update 42 --blocked-by-ids 7,9
    ])
    assert_equal 0, exit_code
    assert_equal [ 7, 9 ], FakeClient.requests.last[2][:blocked_by_ids]

    exit_code = command.run([
      "--project", "github.com/owner/project", "task", "update", "42", "--blocked-by-ids", ""
    ])
    assert_equal 0, exit_code
    assert_equal [], FakeClient.requests.last[2][:blocked_by_ids]
  end

  def test_deletes_task_with_project_query
    exit_code = command.run(%w[
      --project github.com/owner/project task delete 42
    ])

    assert_equal 0, exit_code
    assert_equal [
      :delete,
      "/tasks/42",
      nil,
      { project: "github.com/owner/project" }
    ], FakeClient.requests.last
  end

  def test_lists_and_gets_task_artifacts
    command.run(%w[--project github.com/owner/project task artifact list 42])
    assert_equal [ :get, "/tasks/42/artifacts", nil, { project: "github.com/owner/project" } ], FakeClient.requests.last

    command.run([ "--project", "github.com/owner/project", "task", "artifact", "get", "42", "review report" ])
    assert_equal [
      :get,
      "/tasks/42/artifacts/review%20report",
      nil,
      { project: "github.com/owner/project" }
    ], FakeClient.requests.last
  end

  def test_puts_a_new_artifact_from_stdin_with_an_explicit_null_version
    stdin = StringIO.new("# Спецификация\n")
    artifact_command = KosCli::Command.new(
      stdout: @stdout, stderr: @stderr, stdin: stdin, client_class: FakeClient
    )

    exit_code = artifact_command.run(%w[
      --project github.com/owner/project --claim claim-1
      task artifact put 42 specification --file -
    ])

    assert_equal 0, exit_code
    assert_equal [
      :put,
      "/tasks/42/artifacts/specification",
      {
        project: "github.com/owner/project",
        claim_id: "claim-1",
        content: "# Спецификация\n",
        lock_version: nil
      },
      nil
    ], FakeClient.requests.last
  end

  def test_updates_an_artifact_from_a_utf8_file
    Tempfile.create("kos-artifact") do |file|
      file.binmode
      file.write("# Report\n")
      file.flush

      exit_code = command.run([
        "--project", "github.com/owner/project", "--claim", "claim-1",
        "task", "artifact", "put", "42", "report",
        "--file", file.path, "--version", "3"
      ])

      assert_equal 0, exit_code
      assert_equal "# Report\n", FakeClient.requests.last[2][:content]
      assert_equal 3, FakeClient.requests.last[2][:lock_version]
    end
  end

  def test_deletes_an_artifact_with_the_expected_version
    exit_code = command.run(%w[
      --project github.com/owner/project --claim claim-1
      task artifact delete 42 report --version 4
    ])

    assert_equal 0, exit_code
    assert_equal [
      :delete,
      "/tasks/42/artifacts/report",
      { project: "github.com/owner/project", claim_id: "claim-1", lock_version: 4 },
      nil
    ], FakeClient.requests.last
  end

  def test_artifact_writes_require_claim_source_and_valid_version
    cases = [
      %w[--project github.com/owner/project task artifact put 42 report --file -],
      %w[--project github.com/owner/project --claim claim task artifact put 42 report],
      %w[--project github.com/owner/project --claim claim task artifact put 42 report --file - --version -1],
      %w[--project github.com/owner/project --claim claim task artifact delete 42 report]
    ]

    cases.each do |argv|
      setup
      exit_code = command.run(argv)
      assert_usage_error(exit_code)
      assert_equal 1, FakeClient.requests.length
    end
  end

  def test_rejects_invalid_utf8_artifact_content
    stdin = StringIO.new("\xFF".b)
    artifact_command = KosCli::Command.new(
      stdout: @stdout, stderr: @stderr, stdin: stdin, client_class: FakeClient
    )

    exit_code = artifact_command.run(%w[
      --project github.com/owner/project --claim claim
      task artifact put 42 report --file -
    ])

    assert_usage_error(exit_code)
    assert_equal 1, FakeClient.requests.length
  end

  def test_task_create_requires_kind_title_and_description
    exit_code = command.run(%w[
      --project github.com/owner/project task create --kind feature --title Title
    ])

    assert_usage_error(exit_code)
    assert_equal 1, FakeClient.requests.length
  end

  def test_task_commands_that_address_a_record_require_an_id
    %w[show update delete renew release complete reopen].each do |operation|
      setup
      exit_code = command.run([
        "--project", "github.com/owner/project", "task", operation
      ])

      assert_usage_error(exit_code)
      assert_equal 1, FakeClient.requests.length
    end
  end

  def test_task_update_requires_a_mutable_field
    exit_code = command.run(%w[
      --project github.com/owner/project task update 42
    ])

    assert_usage_error(exit_code)
    assert_equal 1, FakeClient.requests.length
  end

  def test_task_update_rejects_protected_field_options
    %w[--status --session-id --claim-id --claimed-at --lease-expires-at].each do |option|
      setup
      exit_code = command.run([
        "--project", "github.com/owner/project", "task", "update", "42", option, "value"
      ])

      assert_usage_error(exit_code)
      assert_equal 1, FakeClient.requests.length
    end
  end

  def test_project_commands_remain_compatible
    exit_code = command.run(%w[
      --project github.com/owner/project project update 7 --name Renamed
    ])

    assert_equal 0, exit_code
    assert_equal [
      :patch,
      "/projects/7",
      { project: { name: "Renamed" } },
      nil
    ], FakeClient.requests.last
  end

  private

  def command
    KosCli::Command.new(stdout: @stdout, stderr: @stderr, client_class: FakeClient)
  end

  def assert_usage_error(exit_code)
    assert_equal 2, exit_code
    assert_equal "invalid_usage", JSON.parse(@stdout.string).dig("error", "code")
    assert_equal "", @stderr.string
  end

  def with_current_repository(repository)
    singleton_class = KosCli::Repository.singleton_class
    original = KosCli::Repository.method(:current)
    singleton_class.define_method(:current) { repository }
    yield
  ensure
    singleton_class.define_method(:current, original)
  end

  def with_environment(name, value)
    original = ENV[name]
    ENV[name] = value
    yield
  ensure
    original.nil? ? ENV.delete(name) : ENV[name] = original
  end
end
