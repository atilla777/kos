require "json"
require "net/http"
require "openssl"
require "optparse"
require "uri"
require_relative "version"

module Kos
  class CLI
    DEFAULT_API_URL = "http://127.0.0.1:3000"

    class Error < StandardError
      attr_reader :kind, :exit_status

      def initialize(kind, message, exit_status: 2)
        @kind = kind
        @exit_status = exit_status
        super(message)
      end
    end

    def initialize(arguments, environment: ENV, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      @arguments = arguments.dup
      @environment = environment
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
    end

    def run
      return print_version if @arguments == [ "--version" ] || @arguments == [ "-v" ]
      return print_help if @arguments.empty? || @arguments == [ "--help" ] || @arguments == [ "-h" ]

      method, path, payload = command
      response = request(method, path, payload)
      @stdout.write(response.body) unless response.body.to_s.empty?
      response.is_a?(Net::HTTPSuccess) ? 0 : 1
    rescue Error => error
      write_error(error.kind, error.message)
      error.exit_status
    rescue OptionParser::ParseError => error
      write_error("usage_error", error.message)
      2
    end

    private

    def print_version
      @stdout.puts("kos #{Kos::VERSION}")
      0
    end

    def print_help
      @stdout.puts <<~HELP
        Usage: kos <resource> <action> [options]

        KOS task coordination CLI

        Resources and actions:
          project create
          workflow create
          task-type create | update
          task create | update | show | claim-next | resume | report-attempt | cancel

        Options:
          -v, --version             Show the installed CLI version

        Run `kos <resource> <action> --help` for command options.
      HELP
      0
    end

    def command
      resource = @arguments.shift
      action = @arguments.shift

      case [ resource, action ]
      when [ "project", "create" ] then project_create
      when [ "workflow", "create" ] then workflow_create
      when [ "task-type", "create" ] then task_type_create
      when [ "task-type", "update" ] then task_type_update
      when [ "task", "create" ] then task_create
      when [ "task", "update" ] then task_update
      when [ "task", "show" ] then task_show
      when [ "task", "claim-next" ] then task_claim_next
      when [ "task", "resume" ] then task_resume
      when [ "task", "report-attempt" ] then task_report_attempt
      when [ "task", "cancel" ] then task_cancel
      else
        raise Error.new("usage_error", "unknown command #{[ resource, action ].compact.join(" ").inspect}")
      end
    end

    def project_create
      values = parse_options("kos project create", {
        "--name NAME" => [ :name, String, "Project name" ],
        "--remote-url URL" => [ :remote_url, String, "Git remote URL" ],
        "--default-branch BRANCH" => [ :default_branch, String, "Default Git branch" ]
      })
      require_values!(values, :name, :remote_url, :default_branch)
      [ :post, "/projects", values ]
    end

    def workflow_create
      values = parse_options("kos workflow create", {
        "--name NAME" => [ :name, String, "Workflow name" ],
        "--definition-file FILE" => [ :definition_file, String, "Workflow JSON file, or - for STDIN" ]
      })
      require_values!(values, :name, :definition_file)
      definition_file = values.delete(:definition_file)
      values[:definition_json] = read_json(definition_file)
      [ :post, "/workflows", values ]
    end

    def task_type_create
      values = parse_options("kos task-type create", {
        "--name NAME" => [ :name, String, "Task type name" ],
        "--workflow-id ID" => [ :workflow_id, Integer, "Workflow ID" ]
      })
      require_values!(values, :name, :workflow_id)
      [ :post, "/task_types", values ]
    end

    def task_type_update
      id = shift_id!("task type")
      values = parse_options("kos task-type update ID", {
        "--workflow-id ID" => [ :workflow_id, Integer, "Workflow ID" ]
      })
      require_values!(values, :workflow_id)
      [ :patch, "/task_types/#{id}", values ]
    end

    def task_create
      values = parse_task_definition_options("kos task create", update: false)
      require_values!(values, :project_id, :task_type_id, :title, :description_markdown)
      values[:blocker_ids] ||= []
      [ :post, "/tasks", values ]
    end

    def task_update
      id = shift_id!("task")
      values = parse_task_definition_options("kos task update ID", update: true)
      raise Error.new("usage_error", "provide at least one editable task field") if values.empty?

      [ :patch, "/tasks/#{id}", values ]
    end

    def task_show
      id = shift_id!("task")
      parse_options("kos task show ID", {})
      [ :get, "/tasks/#{id}", nil ]
    end

    def task_claim_next
      values = parse_options("kos task claim-next", owner_options.merge(
        "--project-id ID" => [ :project_id, Integer, "Project ID" ]
      ))
      require_values!(values, :project_id, :owner_id)
      [ :post, "/tasks/claim-next", values ]
    end

    def task_resume
      id = shift_id!("task")
      values = parse_options("kos task resume ID", owner_options.merge(
        "--takeover-confirmed" => [ :takeover_confirmed, true, "Confirm replacement of an active owner" ]
      ))
      require_values!(values, :owner_id)
      values[:takeover_confirmed] ||= false
      [ :post, "/tasks/#{id}/resume", values ]
    end

    def task_report_attempt
      id = shift_id!("task")
      values = parse_options("kos task report-attempt ID", owner_options.merge(
        "--claim-version VERSION" => [ :claim_version, Integer, "Current claim version" ],
        "--step STEP" => [ :step, String, "Current workflow step" ],
        "--outcome OUTCOME" => [ :outcome, String, "Reported step outcome" ]
      ))
      require_values!(values, :owner_id, :claim_version, :step, :outcome)
      [ :post, "/tasks/#{id}/report-attempt", values ]
    end

    def task_cancel
      id = shift_id!("task")
      parse_options("kos task cancel ID", {})
      [ :post, "/tasks/#{id}/cancel", {} ]
    end

    def parse_task_definition_options(usage, update:)
      values = {}
      parser = option_parser(usage)
      parser.on("--project-id ID", Integer, "Project ID") { |value| values[:project_id] = value } unless update
      parser.on("--task-type-id ID", Integer, "Task type ID") { |value| values[:task_type_id] = value } unless update
      parser.on("--title TITLE", String, "Task title") { |value| values[:title] = value } unless update
      parser.on("--description-file FILE", String, "Markdown file, or - for STDIN") do |value|
        values[:description_markdown] = read_file(value)
      end
      parser.on("--parent-id ID", Integer, "Parent task ID") do |value|
        reject_duplicate!(values, :parent_id, "--parent-id and --clear-parent are mutually exclusive")
        values[:parent_id] = value
      end
      parser.on("--clear-parent", "Remove the parent task") do
        reject_duplicate!(values, :parent_id, "--parent-id and --clear-parent are mutually exclusive")
        values[:parent_id] = nil
      end
      blocker_ids = []
      blockers_set = false
      parser.on("--blocker-id ID", Integer, "Blocking task ID; may be repeated") do |value|
        raise OptionParser::InvalidOption, "--blocker-id and --clear-blockers are mutually exclusive" if blockers_set == :clear

        blockers_set = true
        blocker_ids << value
      end
      parser.on("--clear-blockers", "Remove all blocking tasks") do
        raise OptionParser::InvalidOption, "--blocker-id and --clear-blockers are mutually exclusive" if blockers_set == true

        blockers_set = :clear
      end
      parse!(parser)
      values[:blocker_ids] = blocker_ids if blockers_set
      values
    end

    def parse_options(usage, definitions)
      values = {}
      parser = option_parser(usage)
      definitions.each do |switch, (name, type, description)|
        if type == true
          parser.on(switch, description) { values[name] = true }
        else
          parser.on(switch, type, description) { |value| values[name] = value }
        end
      end
      parse!(parser)
      values
    end

    def option_parser(usage)
      OptionParser.new do |parser|
        parser.banner = "Usage: #{usage} [options]"
        parser.on("-h", "--help", "Show this help") do
          @stdout.puts(parser)
          throw :help
        end
      end
    end

    def parse!(parser)
      helped = catch(:help) do
        parser.parse!(@arguments)
        false
      end
      throw :command_help if helped.nil?
      raise OptionParser::InvalidArgument, "unexpected arguments: #{@arguments.join(" ")}" if @arguments.any?
    rescue ArgumentError => error
      raise Error.new("usage_error", error.message)
    end

    def require_values!(values, *names)
      missing = names.reject { |name| values.key?(name) }
      return if missing.empty?

      switches = missing.map { |name| "--#{name.to_s.tr("_", "-")}" }
      raise Error.new("usage_error", "missing required options: #{switches.join(", ")}")
    end

    def shift_id!(label)
      return 0 if %w[-h --help].include?(@arguments.first)

      value = @arguments.shift
      Integer(value, 10)
    rescue ArgumentError, TypeError
      raise Error.new("usage_error", "#{label} ID must be an integer")
    end

    def owner_options
      { "--owner-id OWNER" => [ :owner_id, String, "Orchestrator session ID" ] }
    end

    def reject_duplicate!(values, name, message)
      raise OptionParser::InvalidOption, message if values.key?(name)
    end

    def read_json(path)
      JSON.parse(read_file(path))
    rescue JSON::ParserError => error
      raise Error.new("local_input_error", "invalid JSON in #{display_path(path)}: #{error.message}")
    end

    def read_file(path)
      contents = path == "-" ? @stdin.read : File.binread(path)
      normalize_utf8(contents, display_path(path))
    rescue SystemCallError => error
      raise Error.new("local_input_error", "cannot read #{display_path(path)}: #{error.message}")
    end

    def display_path(path)
      path == "-" ? "STDIN" : path
    end

    def request(method, path, payload)
      uri = endpoint(path)
      request_class = { get: Net::HTTP::Get, patch: Net::HTTP::Patch, post: Net::HTTP::Post }.fetch(method)
      http_request = request_class.new(uri)
      http_request["Accept"] = "application/json"
      http_request["Authorization"] = "Bearer #{api_token}"
      if payload
        http_request["Content-Type"] = "application/json"
        http_request.body = JSON.generate(normalize_payload(payload))
      end

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
        http.request(http_request)
      end
    rescue SocketError, SystemCallError, IOError, EOFError, Net::OpenTimeout, Net::ReadTimeout,
      Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError, OpenSSL::SSL::SSLError => error
      raise Error.new("transport_error", "request to #{uri&.host || "KOS"} failed: #{error.message}", exit_status: 3)
    end

    def endpoint(path)
      raw_url = @environment.fetch("KOS_API_URL", DEFAULT_API_URL)
      uri = URI.parse(raw_url)
      unless %w[http https].include?(uri.scheme) && uri.host && !uri.query && !uri.fragment
        raise Error.new("configuration_error", "KOS_API_URL must be an HTTP(S) base URL")
      end

      uri.path = [ uri.path.sub(%r{/+$}, ""), path ].join
      uri
    rescue URI::InvalidURIError
      raise Error.new("configuration_error", "KOS_API_URL must be an HTTP(S) base URL")
    end

    def api_token
      token = @environment["KOS_API_TOKEN"]
      token = normalize_utf8(token, "KOS_API_TOKEN", kind: "configuration_error") if token
      return token if token && !token.strip.empty? && !token.match?(/[\r\n]/)

      raise Error.new("configuration_error", "KOS_API_TOKEN must be a non-empty HTTP header value")
    end

    def normalize_payload(value)
      case value
      when Hash then value.transform_values { |item| normalize_payload(item) }
      when Array then value.map { |item| normalize_payload(item) }
      when String then normalize_utf8(value, "request data")
      else value
      end
    end

    def normalize_utf8(value, label, kind: "local_input_error")
      utf8 = value.b.dup.force_encoding(Encoding::UTF_8)
      return utf8 if utf8.valid_encoding?

      raise Error.new(kind, "#{label} must be valid UTF-8")
    end

    def write_error(kind, message)
      safe_message = message.to_s.b.force_encoding(Encoding::UTF_8).scrub
      @stderr.puts(JSON.generate(error: kind, message: safe_message))
    end
  end
end
