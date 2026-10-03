require "json"
require "digest"
require "optparse"
require "securerandom"
require "uri"

module KosCli
  class ApiError < StandardError
    attr_reader :status, :response

    def initialize(status, response)
      @status = status
      @response = response
      super()
    end
  end

  class Command
    DEFAULT_URL = "http://127.0.0.1:3137"
    API_ERROR_EXIT = 1
    USAGE_ERROR_EXIT = 2
    CONNECTION_ERROR_EXIT = 3
    CONFLICT_EXIT = 4
    AMBIGUOUS_RESULT_EXIT = 5
    COMMANDS = {
      "session" => %w[new], "project" => %w[create list show update delete],
      "group" => %w[create list show update delete], "workflow" => %w[create list show delete],
      "task" => %w[create list ready claim-next claim current renew release complete reopen show update delete step advance artifact plan],
      "task step" => %w[show], "task artifact" => %w[list get put delete], "task plan" => %w[create show]
    }.freeze
    HELP_OPTIONS = {
      "session new" => "",
      "project create" => "[--name NAME] [--repository REPOSITORY]", "project list" => "[--limit N] [--after-id ID]",
      "project show" => "[ID|REPOSITORY]", "project update" => "[ID|REPOSITORY] [--name NAME] [--repository REPOSITORY]",
      "project delete" => "[ID|REPOSITORY]",
      "group create" => "--kind KIND --title TITLE --description TEXT", "group list" => "[--limit N] [--after-id ID]",
      "group show" => "GROUP_ID", "group update" => "GROUP_ID [--kind KIND] [--title TITLE] [--description TEXT]", "group delete" => "GROUP_ID",
      "workflow create" => "--file PATH [--global]",
      "workflow list" => "[--limit N] [--after-id ID] [--brief]",
      "workflow show" => "WORKFLOW_ID", "workflow delete" => "WORKFLOW_ID",
      "task create" => "--kind KIND --title TITLE --description TEXT --workflow-id ID [OPTIONS]",
      "task list" => "[--limit N] [--after-id ID] [--filter done|unfinished|blocked]", "task ready" => "[--limit N] [--after-id ID] [--kind KIND] [--group-id ID]",
      "task claim-next" => "[--kind KIND] [--group-id ID] [--route|--fingerprint] [--context-limit N]",
      "task claim" => "TASK_ID [--route|--fingerprint] [--context-limit N]",
      "task current" => "[--route|--fingerprint] [--context-limit N]", "task renew" => "TASK_ID",
      "task release" => "TASK_ID [--work-summary TEXT]", "task complete" => "TASK_ID [--work-summary TEXT]",
      "task reopen" => "TASK_ID",
      "task show" => "TASK_ID [--brief | --state] [--context-limit N] [--artifact-after-id ID] [--blocked-by-after-id ID] [--dependency-artifact-after-id ID] [--blocks-after-id ID]",
      "task update" => "TASK_ID [--kind KIND] [--title TITLE] [--description TEXT] [--work-summary SUMMARY] [--group-id ID|--no-group] [--blocked-by-ids IDS]",
      "task delete" => "TASK_ID", "task advance" => "TASK_ID --expected-step N",
      "task step show" => "TASK_ID [--brief]",
      "task artifact list" => "TASK_ID [--limit N] [--after-id ID]",
      "task artifact get" => "TASK_ID KEY",
      "task artifact put" => "TASK_ID KEY --file PATH|- [--version N] [--expected-step N] [--brief]",
      "task artifact delete" => "TASK_ID KEY --version N",
      "task plan create" => "BRIEF_ID --key KEY --file PATH|- --expected-step N",
      "task plan show" => "BRIEF_ID KEY"
    }.freeze

    def initialize(stdout: $stdout, stderr: $stderr, stdin: $stdin, client_class: Client)
      @stdout = stdout
      @stderr = stderr
      @stdin = stdin
      @client_class = client_class
      @secrets = []
    end

    def run(argv)
      return show_help(argv) if argv.include?("--help") || argv.include?("-h")

      @fingerprint_route = false
      options = {
        url: ENV.fetch("KOS_API_URL", DEFAULT_URL),
        project: ENV["KOS_PROJECT"],
        session: ENV["KOS_SESSION_ID"],
        claim: ENV["KOS_CLAIM_ID"],
        claim_fingerprint: nil
      }
      parse_global_options(argv, options)
      @secrets = sensitive_values(options)
      if argv.first == "session"
        argv.shift
        raise OptionParser::ParseError, "Expected session new." unless argv.shift == "new"

        ensure_empty!(argv)
        write_json({ data: { session_id: SecureRandom.uuid } })
        return 0
      end
      options[:project] = Repository.normalize(options[:project]) if options[:project]

      client = @client_class.new(options[:url])
      status, response = case argv.shift
      when "project" then run_project(client, argv, options)
      when "group" then run_group(client, argv, options)
      when "workflow" then run_workflow(client, argv, options)
      when "task" then run_task(client, argv, options)
      else raise OptionParser::ParseError, "Expected: kos #{COMMANDS.keys.take(5).join('|')} COMMAND"
      end
      success = status.between?(200, 299)
      response = with_claim_fingerprint(response) if success && (@fingerprint_route || options[:claim_fingerprint])
      write_json(response, redact_secrets: !success)
      success ? 0 : api_exit_code(status)
    rescue OptionParser::ParseError, ArgumentError, RepositoryError => error
      write_error("invalid_usage", error.message)
      USAGE_ERROR_EXIT
    rescue ApiError => error
      write_json(error.response)
      api_exit_code(error.status)
    rescue ConnectionError => error
      write_error("connection_error", error.message)
      CONNECTION_ERROR_EXIT
    rescue AmbiguousResultError => error
      write_error(
        "ambiguous_result",
        error.message,
        verification_command: error.verification_command
      )
      AMBIGUOUS_RESULT_EXIT
    end

    private

    def show_help(argv)
      words = argv.take_while { |word| word != "--help" && word != "-h" }
      index = 0
      index += 2 while %w[--url --project --session --claim --claim-fingerprint].include?(words[index])
      words = words.drop(index)
      section = words.first
      path = if COMMANDS.key?(section)
        parts = [ section ]
        parts << words[1] if COMMANDS.fetch(section).include?(words[1])
        parts << words[2] if COMMANDS.key?(parts.join(" ")) && COMMANDS.fetch(parts.join(" ")).include?(words[2])
        parts.join(" ")
      end
      lines = if path.nil?
        [ "Usage: kos [--url URL] [--project REPOSITORY] [--session SESSION] [--claim CLAIM | --claim-fingerprint SHA256] COMMAND",
          "Commands: #{COMMANDS.keys.take(5).join(', ')}", "Use kos COMMAND --help for details." ]
      elsif COMMANDS.key?(path)
        [ "Usage: kos #{path} COMMAND", "Commands: #{COMMANDS.fetch(path).join(', ')}",
          "Use kos #{path} COMMAND --help for details." ]
      else
        [ "Usage: kos #{path} #{HELP_OPTIONS.fetch(path, '[OPTIONS]')}",
          "Global options: --url URL, --project REPOSITORY, --session SESSION, --claim CLAIM, --claim-fingerprint SHA256" ]
      end
      write_json({ data: { help: lines.join("\n") } })
      0
    end

    def parse_global_options(argv, options)
      OptionParser.new do |parser|
        parser.on("--url URL") { |value| options[:url] = value }
        parser.on("--project REPOSITORY") { |value| options[:project] = value }
        parser.on("--session SESSION") { |value| options[:session] = value }
        parser.on("--claim CLAIM") { |value| options[:claim] = value }
        parser.on("--claim-fingerprint SHA256") do |value|
          raise OptionParser::ParseError, "Claim fingerprint must be 64 lowercase hex characters." unless value.match?(/\A[0-9a-f]{64}\z/)

          options[:claim_fingerprint] = value
          options[:claim] = nil
        end
      end.order!(argv)
    end

    def run_project(client, argv, global)
      command = argv.shift
      case command
      when "create" then create_project(client, argv, global)
      when "list" then list_projects(client, argv)
      when "show" then show_project(client, argv, global)
      when "update" then update_project(client, argv, global)
      when "delete" then delete_project(client, argv, global)
      else raise OptionParser::ParseError, "Expected project create, list, show, update, or delete."
      end
    end

    def create_project(client, argv, global)
      values = {}
      OptionParser.new do |parser|
        parser.on("--name NAME") { |value| values[:name] = value }
        parser.on("--repository REPOSITORY") { |value| values[:repository] = Repository.normalize(value) }
      end.parse!(argv)
      ensure_empty!(argv)
      repository = values[:repository] || global[:project] || Repository.current
      name = values[:name] || repository.split("/").last
      client.request(:post, "/projects", body: { project: { name: name, repository: repository } })
    end

    def list_projects(client, argv)
      values = { limit: 50 }
      OptionParser.new do |parser|
        parser.on("--limit LIMIT", Integer) { |value| values[:limit] = value }
        parser.on("--after-id ID", Integer) { |value| values[:after_id] = value }
      end.parse!(argv)
      ensure_empty!(argv)
      client.request(:get, "/projects", query: values.compact)
    end

    def show_project(client, argv, global)
      id = resolve_id(client, argv.shift, global)
      ensure_empty!(argv)
      client.request(:get, "/projects/#{id}")
    end

    def update_project(client, argv, global)
      target = argv.first&.start_with?("-") ? nil : argv.shift
      values = {}
      OptionParser.new do |parser|
        parser.on("--name NAME") { |value| values[:name] = value }
        parser.on("--repository REPOSITORY") { |value| values[:repository] = Repository.normalize(value) }
      end.parse!(argv)
      ensure_empty!(argv)
      raise OptionParser::ParseError, "Provide --name or --repository." if values.empty?

      id = resolve_id(client, target, global)
      client.request(:patch, "/projects/#{id}", body: { project: values })
    end

    def delete_project(client, argv, global)
      id = resolve_id(client, argv.shift, global)
      ensure_empty!(argv)
      client.request(:delete, "/projects/#{id}")
    end

    def run_task(client, argv, global)
      command = argv.shift
      case command
      when "create" then create_task(client, argv, global)
      when "list" then list_tasks(client, argv, global)
      when "ready" then ready_tasks(client, argv, global)
      when "claim-next" then claim_next_task(client, argv, global)
      when "claim" then claim_task(client, argv, global)
      when "current" then current_task(client, argv, global)
      when "renew" then transition_task(client, argv, global, "renew")
      when "release" then finish_task(client, argv, global, "release")
      when "complete" then finish_task(client, argv, global, "complete")
      when "reopen" then reopen_task(client, argv, global)
      when "show" then show_task(client, argv, global)
      when "update" then update_task(client, argv, global)
      when "delete" then delete_task(client, argv, global)
      when "artifact" then run_task_artifact(client, argv, global)
      when "step" then run_task_step(client, argv, global)
      when "advance" then advance_task(client, argv, global)
      when "plan" then run_task_plan(client, argv, global)
      else raise OptionParser::ParseError, "Expected task #{COMMANDS.fetch('task').join(', ')}."
      end
    end

    def run_workflow(client, argv, global)
      case argv.shift
      when "create"
        values = {}
        OptionParser.new do |parser|
          parser.on("--file PATH") { |path| values[:file] = path }
          parser.on("--global") { values[:global] = true }
        end.parse!(argv)
        ensure_empty!(argv)
        raise OptionParser::ParseError, "Provide --file PATH." unless values[:file]

        definition = JSON.parse(read_utf8(values[:file]))
        unless definition.is_a?(Hash) && definition.keys.sort == %w[name steps]
          raise OptionParser::ParseError, "Workflow file must contain only name and steps."
        end

        body = { name: definition.fetch("name"), steps: definition.fetch("steps") }
        body[:global] = true if values[:global]
        body[:project] = resolve_project(global) unless values[:global]
        client.request(:post, "/workflows", body: body)
      when "list"
        values = { limit: 50 }
        OptionParser.new do |parser|
          parser.on("--limit LIMIT", Integer) { |value| values[:limit] = value }
          parser.on("--after-id ID", Integer) { |value| values[:after_id] = value }
          parser.on("--brief") { values[:view] = "brief" }
        end.parse!(argv)
        ensure_empty!(argv)
        client.request(:get, "/workflows", query: { project: resolve_project(global), **values })
      when "show"
        id = task_id!(argv.shift)
        ensure_empty!(argv)
        client.request(:get, "/workflows/#{id}", query: { project: resolve_project(global) })
      when "delete"
        id = task_id!(argv.shift)
        ensure_empty!(argv)
        client.request(:delete, "/workflows/#{id}", query: { project: resolve_project(global) })
      else
        raise OptionParser::ParseError, "Expected workflow create, list, show, or delete."
      end
    rescue JSON::ParserError
      raise OptionParser::ParseError, "Workflow file must contain valid JSON."
    end

    def run_task_step(client, argv, global)
      raise OptionParser::ParseError, "Expected task step show." unless argv.shift == "show"

      id = task_id!(argv.shift)
      values = {}
      OptionParser.new { |parser| parser.on("--brief") { values[:view] = "brief" } }.parse!(argv)
      ensure_empty!(argv)
      client.request(:get, "/tasks/#{id}/step", query: { project: resolve_project(global), **values })
    end

    def run_task_plan(client, argv, global)
      operation = argv.shift
      id = task_id!(argv.shift)
      case operation
      when "show"
        key = artifact_key!(argv.shift)
        ensure_empty!(argv)
        client.request(:get, "/tasks/#{id}/brief-plan/#{URI.encode_uri_component(key)}", query: { project: resolve_project(global) })
      when "create"
        values = {}
        OptionParser.new do |parser|
          parser.on("--key KEY") { |value| values[:key] = value }
          parser.on("--file PATH") { |value| values[:file] = value }
          parser.on("--expected-step N", Integer) { |value| values[:expected_step] = nonnegative_version!(value) }
        end.parse!(argv)
        ensure_empty!(argv)
        raise OptionParser::ParseError, "Provide --key KEY, --file PATH, and --expected-step N." unless %i[key file expected_step].all? { |field| values.key?(field) }

        entries = JSON.parse(read_utf8(values.fetch(:file)))
        raise OptionParser::ParseError, "Plan file must contain a JSON array of tasks." unless entries.is_a?(Array)

        client.request(:post, "/tasks/#{id}/brief-plan", body: {
          project: resolve_project(global), claim_id: resolve_claim_for_task(client, global, id, expected_step: values[:expected_step]),
          expected_step: values[:expected_step], key: values[:key], tasks: entries
        })
      else
        raise OptionParser::ParseError, "Expected task plan create or show."
      end
    rescue JSON::ParserError
      raise OptionParser::ParseError, "Plan file must contain valid JSON."
    end

    def advance_task(client, argv, global)
      id = task_id!(argv.shift)
      values = {}
      OptionParser.new do |parser|
        parser.on("--expected-step N", Integer) { |value| values[:expected_step] = nonnegative_version!(value) }
      end.parse!(argv)
      ensure_empty!(argv)
      raise OptionParser::ParseError, "Provide --expected-step N." unless values.key?(:expected_step)

      client.request(:post, "/tasks/#{id}/advance", body: {
        project: resolve_project(global), claim_id: resolve_claim_for_task(client, global, id, expected_step: values[:expected_step]), **values
      })
    end

    def run_task_artifact(client, argv, global)
      command = argv.shift
      case command
      when "list" then list_task_artifacts(client, argv, global)
      when "get" then get_task_artifact(client, argv, global)
      when "put" then put_task_artifact(client, argv, global)
      when "delete" then delete_task_artifact(client, argv, global)
      else raise OptionParser::ParseError, "Expected task artifact list, get, put, or delete."
      end
    end

    def run_group(client, argv, global)
      command = argv.shift
      case command
      when "create" then create_group(client, argv, global)
      when "list" then list_groups(client, argv, global)
      when "show" then show_group(client, argv, global)
      when "update" then update_group(client, argv, global)
      when "delete" then delete_group(client, argv, global)
      else raise OptionParser::ParseError, "Expected group create, list, show, update, or delete."
      end
    end

    def create_group(client, argv, global)
      values = {}
      OptionParser.new do |parser|
        parser.on("--kind KIND") { |value| values[:kind] = value }
        parser.on("--title TITLE") { |value| values[:title] = value }
        parser.on("--description DESCRIPTION") { |value| values[:description] = value }
      end.parse!(argv)
      ensure_empty!(argv)
      missing = %i[kind title description].reject { |field| values.key?(field) }
      raise OptionParser::ParseError, "Provide --#{missing.first.to_s.tr("_", "-")}." if missing.any?

      client.request(:post, "/task-groups", body: { project: resolve_project(global), **values })
    end

    def list_groups(client, argv, global)
      values = { limit: 50 }
      OptionParser.new do |parser|
        parser.on("--limit LIMIT", Integer) { |value| values[:limit] = value }
        parser.on("--after-id ID", Integer) { |value| values[:after_id] = value }
      end.parse!(argv)
      ensure_empty!(argv)
      client.request(:get, "/task-groups", query: { project: resolve_project(global), **values.compact })
    end

    def show_group(client, argv, global)
      id = group_id!(argv.shift)
      ensure_empty!(argv)
      client.request(:get, "/task-groups/#{id}", query: { project: resolve_project(global) })
    end

    def update_group(client, argv, global)
      id = group_id!(argv.shift)
      values = {}
      OptionParser.new do |parser|
        parser.on("--kind KIND") { |value| values[:kind] = value }
        parser.on("--title TITLE") { |value| values[:title] = value }
        parser.on("--description DESCRIPTION") { |value| values[:description] = value }
      end.parse!(argv)
      ensure_empty!(argv)
      raise OptionParser::ParseError, "Provide --kind, --title, or --description." if values.empty?

      client.request(:patch, "/task-groups/#{id}", body: { project: resolve_project(global), **values })
    end

    def delete_group(client, argv, global)
      id = group_id!(argv.shift)
      ensure_empty!(argv)
      client.request(:delete, "/task-groups/#{id}", query: { project: resolve_project(global) })
    end

    def create_task(client, argv, global)
      values = {}
      OptionParser.new do |parser|
        parser.on("--kind KIND") { |value| values[:kind] = value }
        parser.on("--title TITLE") { |value| values[:title] = value }
        parser.on("--description DESCRIPTION") { |value| values[:description] = value }
        parser.on("--work-summary SUMMARY") { |value| values[:work_summary] = value }
        parser.on("--group-id ID", Integer) { |value| values[:task_group_id] = value }
        parser.on("--workflow-id ID", Integer) { |value| values[:workflow_id] = value }
        parser.on("--blocked-by-ids IDS") { |value| values[:blocked_by_ids] = id_list(value) }
      end.parse!(argv)
      ensure_empty!(argv)
      missing = %i[kind title description workflow_id].reject { |field| values.key?(field) }
      raise OptionParser::ParseError, "Provide --#{missing.first.to_s.tr("_", "-")}." if missing.any?

      client.request(:post, "/tasks", body: { project: resolve_project(global), **values })
    end

    def list_tasks(client, argv, global)
      values = { limit: 50 }
      OptionParser.new do |parser|
        parser.on("--limit LIMIT", Integer) { |value| values[:limit] = value }
        parser.on("--after-id ID", Integer) { |value| values[:after_id] = value }
        parser.on("--filter FILTER", %w[done unfinished blocked]) { |value| values[:filter] = value }
      end.parse!(argv)
      ensure_empty!(argv)
      client.request(:get, "/tasks", query: { project: resolve_project(global), **values.compact })
    end

    def ready_tasks(client, argv, global)
      values = { limit: 50 }
      OptionParser.new do |parser|
        parser.on("--kind KIND") { |value| values[:kind] = value }
        parser.on("--group-id ID", Integer) { |value| values[:task_group_id] = value }
        parser.on("--limit LIMIT", Integer) { |value| values[:limit] = value }
        parser.on("--after-id ID", Integer) { |value| values[:after_id] = value }
      end.parse!(argv)
      ensure_empty!(argv)
      client.request(:get, "/tasks/ready", query: { project: resolve_project(global), **values.compact })
    end

    def claim_next_task(client, argv, global)
      values = {}
      OptionParser.new do |parser|
        parser.on("--kind KIND") { |value| values[:kind] = value }
        parser.on("--group-id ID", Integer) { |value| values[:task_group_id] = value }
        parse_route_option(parser, values)
        parse_context_options(parser, values)
      end.parse!(argv)
      ensure_empty!(argv)
      client.request(:post, "/tasks/claim-next", body: {
        project: resolve_project(global),
        session_id: resolve_session(global),
        **values
      })
    end

    def claim_task(client, argv, global)
      id = task_id!(argv.shift)
      values = {}
      OptionParser.new do |parser|
        parse_route_option(parser, values)
        parse_context_options(parser, values)
      end.parse!(argv)
      ensure_empty!(argv)
      client.request(:post, "/tasks/#{id}/claim", body: {
        project: resolve_project(global),
        session_id: resolve_session(global),
        **values
      })
    end

    def current_task(client, argv, global)
      values = {}
      OptionParser.new do |parser|
        parse_route_option(parser, values)
        parse_context_options(parser, values)
      end.parse!(argv)
      ensure_empty!(argv)
      client.request(:get, "/tasks/current", query: {
        project: resolve_project(global),
        session_id: resolve_session(global),
        **values
      })
    end

    def transition_task(client, argv, global, operation)
      id = task_id!(argv.shift)
      ensure_empty!(argv)
      client.request(:post, "/tasks/#{id}/#{operation}", body: {
        project: resolve_project(global),
        claim_id: resolve_claim_for_task(client, global, id)
      })
    end

    def finish_task(client, argv, global, operation)
      id = task_id!(argv.shift)
      values = {}
      OptionParser.new do |parser|
        parser.on("--work-summary SUMMARY") { |value| values[:work_summary] = value }
      end.parse!(argv)
      ensure_empty!(argv)
      client.request(:post, "/tasks/#{id}/#{operation}", body: {
        project: resolve_project(global),
        claim_id: resolve_claim_for_task(client, global, id),
        **values
      })
    end

    def reopen_task(client, argv, global)
      id = task_id!(argv.shift)
      ensure_empty!(argv)
      client.request(:post, "/tasks/#{id}/reopen", body: { project: resolve_project(global) })
    end

    def show_task(client, argv, global)
      id = task_id!(argv.shift)
      values = {}
      views = []
      OptionParser.new do |parser|
        parse_context_options(parser, values)
        parser.on("--brief") { views << "brief" }
        parser.on("--state") { views << "state" }
      end.parse!(argv)
      ensure_empty!(argv)
      raise OptionParser::ParseError, "Choose either --brief or --state." if views.uniq.length > 1

      values[:view] = views.first if views.any?
      client.request(:get, "/tasks/#{id}", query: { project: resolve_project(global), **values })
    end

    def update_task(client, argv, global)
      id = task_id!(argv.shift)
      values = {}
      OptionParser.new do |parser|
        parser.on("--kind KIND") { |value| values[:kind] = value }
        parser.on("--title TITLE") { |value| values[:title] = value }
        parser.on("--description DESCRIPTION") { |value| values[:description] = value }
        parser.on("--work-summary SUMMARY") { |value| values[:work_summary] = value }
        parser.on("--group-id ID", Integer) { |value| values[:task_group_id] = value }
        parser.on("--no-group") { values[:task_group_id] = nil }
        parser.on("--blocked-by-ids IDS") { |value| values[:blocked_by_ids] = id_list(value) }
      end.parse!(argv)
      ensure_empty!(argv)
      raise OptionParser::ParseError, "Provide a mutable task field." if values.empty?

      values[:claim_id] = resolve_claim_for_task(client, global, id) if global[:claim_fingerprint]
      values[:claim_id] ||= global[:claim] if global[:claim]&.strip&.length&.positive?
      client.request(:patch, "/tasks/#{id}", body: { project: resolve_project(global), **values })
    end

    def delete_task(client, argv, global)
      id = task_id!(argv.shift)
      ensure_empty!(argv)
      client.request(:delete, "/tasks/#{id}", query: { project: resolve_project(global) })
    end

    def list_task_artifacts(client, argv, global)
      id = task_id!(argv.shift)
      values = { limit: 50 }
      OptionParser.new do |parser|
        parser.on("--limit LIMIT", Integer) { |value| values[:limit] = value }
        parser.on("--after-id ID", Integer) { |value| values[:after_id] = value }
      end.parse!(argv)
      ensure_empty!(argv)
      client.request(:get, "/tasks/#{id}/artifacts", query: { project: resolve_project(global), **values.compact })
    end

    def get_task_artifact(client, argv, global)
      id = task_id!(argv.shift)
      key = artifact_key!(argv.shift)
      ensure_empty!(argv)
      client.request(:get, artifact_path(id, key), query: { project: resolve_project(global) })
    end

    def put_task_artifact(client, argv, global)
      id = task_id!(argv.shift)
      key = artifact_key!(argv.shift)
      values = {}
      OptionParser.new do |parser|
        parser.on("--file PATH") { |value| values[:file] = value }
        parser.on("--version VERSION", Integer) { |value| values[:lock_version] = nonnegative_version!(value) }
        parser.on("--expected-step N", Integer) { |value| values[:expected_step] = nonnegative_version!(value) }
        parser.on("--brief") { values[:view] = "brief" }
      end.parse!(argv)
      ensure_empty!(argv)
      raise OptionParser::ParseError, "Provide --file PATH or --file -." unless values.key?(:file)
      if global[:claim_fingerprint] && !values.key?(:expected_step)
        raise OptionParser::ParseError, "Provide --expected-step N with --claim-fingerprint."
      end
      if values.key?(:expected_step) && !global[:claim_fingerprint]
        raise OptionParser::ParseError, "--expected-step requires --claim-fingerprint."
      end

      client.request(:put, artifact_path(id, key), query: values[:view] ? { view: values[:view] } : nil, body: {
        project: resolve_project(global),
        claim_id: resolve_claim_for_task(client, global, id, expected_step: values[:expected_step]),
        content: read_utf8(values.fetch(:file)),
        lock_version: values[:lock_version],
        **(global[:claim_fingerprint] ? { expected_step: values[:expected_step] } : {})
      })
    end

    def delete_task_artifact(client, argv, global)
      id = task_id!(argv.shift)
      key = artifact_key!(argv.shift)
      values = {}
      OptionParser.new do |parser|
        parser.on("--version VERSION", Integer) { |value| values[:lock_version] = nonnegative_version!(value) }
      end.parse!(argv)
      ensure_empty!(argv)
      raise OptionParser::ParseError, "Provide --version VERSION." unless values.key?(:lock_version)

      client.request(:delete, artifact_path(id, key), body: {
        project: resolve_project(global),
        claim_id: resolve_claim_for_task(client, global, id),
        lock_version: values.fetch(:lock_version)
      })
    end

    def resolve_project(global)
      global[:project] || Repository.current
    end

    def resolve_session(global)
      session = global[:session]
      raise OptionParser::ParseError, "Provide --session or KOS_SESSION_ID." unless session&.strip&.length&.positive?

      session
    end

    def resolve_claim(global)
      claim = global[:claim]
      raise OptionParser::ParseError, "Provide --claim or KOS_CLAIM_ID." unless claim&.strip&.length&.positive?

      claim
    end

    def resolve_claim_for_task(client, global, task_id, expected_step: nil)
      return resolve_claim(global) unless global[:claim_fingerprint]

      status, response = client.request(:get, "/tasks/current", query: {
        project: resolve_project(global), session_id: resolve_session(global), context: "route"
      })
      raise ApiError.new(status, response) unless status.between?(200, 299)

      task = response.dig("data", "task")
      claim = task && task["claim_id"]
      unless task && task["id"] == task_id && claim.is_a?(String) &&
          Digest::SHA256.hexdigest(claim) == global[:claim_fingerprint]
        raise ApiError.new(409, { error: { code: "claim_mismatch", message: "Current claim differs from the delegated claim." } })
      end
      if !expected_step.nil? && task["current_step"] != expected_step
        raise ApiError.new(409, { error: { code: "step_conflict", message: "Task has moved to another step." } })
      end

      @secrets << claim
      claim
    end

    def with_claim_fingerprint(response)
      task = response.dig("data", "task")
      return response unless task.is_a?(Hash) && task["claim_id"].is_a?(String)

      claim = task.fetch("claim_id")
      @secrets << claim
      response.merge("data" => response.fetch("data").merge("task" => task.except("claim_id").merge(
        "claim_fingerprint" => Digest::SHA256.hexdigest(claim)
      )))
    end

    def task_id!(value)
      raise OptionParser::ParseError, "Task ID is required." unless value&.match?(/\A[1-9][0-9]*\z/)

      Integer(value, 10)
    end

    def group_id!(value)
      raise OptionParser::ParseError, "Group ID is required." unless value&.match?(/\A[1-9][0-9]*\z/)

      Integer(value, 10)
    end

    def artifact_key!(value)
      raise OptionParser::ParseError, "Artifact key is required." unless value&.strip&.length&.positive?

      value
    end

    def artifact_path(task_id, key)
      "/tasks/#{task_id}/artifacts/#{URI.encode_uri_component(key)}"
    end

    def nonnegative_version!(value)
      raise OptionParser::ParseError, "Artifact version must be a nonnegative integer." if value.negative?

      value
    end

    def read_utf8(path)
      content = path == "-" ? @stdin.read : File.binread(path)
      content = content.dup.force_encoding(Encoding::UTF_8)
      raise OptionParser::ParseError, "Artifact content must be valid UTF-8." unless content.valid_encoding?

      content
    rescue SystemCallError
      raise OptionParser::ParseError, "Unable to read artifact file."
    end

    def id_list(value)
      return [] if value.empty?

      value.split(",").map do |id|
        raise OptionParser::ParseError, "Blocked task IDs must be positive integers." unless id.match?(/\A[1-9][0-9]*\z/)

        Integer(id, 10)
      end
    end

    def parse_context_options(parser, values)
      parser.on("--context-limit LIMIT", Integer) { |value| values[:context_limit] = value }
      parser.on("--artifact-after-id ID", Integer) { |value| values[:artifact_after_id] = value }
      parser.on("--blocked-by-after-id ID", Integer) { |value| values[:blocked_by_after_id] = value }
      parser.on("--dependency-artifact-after-id ID", Integer) do |value|
        values[:dependency_artifact_after_id] = value
      end
      parser.on("--blocks-after-id ID", Integer) { |value| values[:blocks_after_id] = value }
    end

    def parse_route_option(parser, values)
      parser.on("--route") { values[:context] = "route" }
      parser.on("--fingerprint") do
        values[:context] = "route"
        @fingerprint_route = true
      end
    end

    def resolve_id(client, target, global)
      return Integer(target, 10) if target&.match?(/\A[0-9]+\z/)

      repository = target ? Repository.normalize(target) : (global[:project] || Repository.current)
      status, response = client.request(:get, "/projects", query: { repository: repository, limit: 1 })
      raise ApiError.new(status, response) unless status.between?(200, 299)

      project = response.dig("data", "projects", 0)
      raise RepositoryError, "Project is not registered." unless project

      project.fetch("id")
    end

    def ensure_empty!(argv)
      raise OptionParser::ParseError, "Unexpected arguments." unless argv.empty?
    end

    def api_exit_code(status)
      status == 409 ? CONFLICT_EXIT : API_ERROR_EXIT
    end

    def write_error(code, message, details = nil)
      error = { code: code, message: message }
      error[:details] = details if details
      write_json({ error: error })
    end

    def write_json(value, redact_secrets: true)
      @stdout.puts(JSON.generate(redact_secrets ? redact(value) : value))
    end

    def redact(value)
      case value
      when Hash then value.to_h { |key, item| [ key, redact(item) ] }
      when Array then value.map { |item| redact(item) }
      when String
        @secrets.reduce(value.dup) { |text, secret| text.gsub(secret, "[REDACTED]") }
      else value
      end
    end

    def sensitive_values(options)
      values = [ options[:claim] ]
      uri = URI(options[:url])
      values.concat([ uri.user, uri.password ])
      values.compact.reject(&:empty?).uniq
    rescue URI::InvalidURIError
      values.compact.reject(&:empty?).uniq
    end
  end
end
