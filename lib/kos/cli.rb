require "json"
require "net/http"
require "openssl"
require "securerandom"
require "timeout"
require "uri"

require_relative "cli/schema_registry"
require_relative "json_parser"

module Kos
  module Cli
    class Error < StandardError
      attr_reader :category, :code

      def initialize(category, code, message)
        @category = category
        @code = code
        super(message)
      end
    end

    class Parser
      IDEMPOTENCY_KEY_FORMAT = /\A[A-Za-z0-9._:-]{8,255}\z/
      COMMANDS = {
        %w[task-type list] => [ "task_type.list", nil, { "limit" => "--limit", "cursor" => "--cursor" } ],
        %w[workflow list] => [ "workflow.list", nil, { "limit" => "--limit", "cursor" => "--cursor" } ],
        %w[workflow get] => [ "workflow.get", nil, { "workflow_version_id" => "--workflow-version" } ],
        %w[workflow export] => [ "workflow.export", nil, { "workflow_version_id" => "--workflow-version" } ],
        %w[workflow publish] => [ "workflow.publish", nil, {}, true ],
        %w[workflow activate] => [ "workflow.activate", nil, {}, true ],
        %w[workflow-draft get] => [ "workflow_draft.get", nil, { "workflow_id" => "--workflow" } ],
        %w[workflow-draft import] => [ "workflow_draft.import", nil, {}, true ],
        %w[workflow-draft validate] => [ "workflow_draft.validate", nil, { "workflow_id" => "--workflow" } ],
        %w[task create] => [ "task.create", "repository", {}, true ],
        %w[task get] => [ "task.get", "repository", { "task_number" => "--task" } ],
        %w[attempt get] => [ "attempt.get", "repository", { "attempt_id" => "--attempt" } ],
        %w[attempt claim] => [ "attempt.claim", "repository", {}, true ],
        %w[attempt renew] => [ "attempt.renew", "repository", {}, true ],
        %w[attempt fail] => [ "attempt.fail", "repository", {}, true ],
        %w[attempt needs-human] => [ "attempt.needs_human", "repository", {}, true ],
        %w[attempt reconcile] => [ "attempt.reconcile", "repository", {}, true ],
        %w[step context] => [ "step.context", "repository", {}, true ],
        %w[step complete] => [ "step.complete", "repository", {}, true ],
        %w[worktree get] => [ "worktree.get", "repository", { "reservation_id" => "--reservation" } ],
        %w[worktree reserve] => [ "worktree.reserve", "repository", {}, true ],
        %w[worktree confirm] => [ "worktree.confirm", "repository", {}, true ],
        %w[worktree reconcile] => [ "worktree.reconcile", "repository", {}, true ],
        %w[worktree release] => [ "worktree.release", "repository", {}, true ],
        %w[effect get] => [ "effect.get", "repository", { "effect_id" => "--effect" } ],
        %w[effect prepare] => [ "effect.prepare", "repository", {}, true ],
        %w[effect reconcile] => [ "effect.reconcile", "repository", {}, true ],
        %w[publication get] => [ "publication.get", "repository", { "publication_id" => "--publication" } ],
        %w[publication prepare] => [ "publication.prepare", "repository", {}, true ],
        %w[publication reconcile] => [ "publication.reconcile", "repository", {}, true ],
        %w[artifact list] => [ "artifact.list", "repository",
          { "task_number" => "--task", "limit" => "--limit", "cursor" => "--cursor" } ]
      }.freeze

      def initialize(schema_registry: SchemaRegistry.new, input: $stdin)
        @schema_registry = schema_registry
        @input = input
      end

      def parse(arguments)
        key = arguments.first(2)
        definition = COMMANDS[key]
        raise Error.new("validation", "unknown_command", "Command is not implemented") unless definition

        command, scope, option_definitions, mutation = definition
        extra_options = mutation ? %w[--input --idempotency-key] : []
        options = parse_options(arguments.drop(2), option_definitions.values + [ "--repository", *extra_options ])
        raise Error.new("validation", "malformed_input", "--json is required") unless options.delete("--json")

        body = mutation ? mutation_body(options) : read_body(options, option_definitions)
        idempotency_key = options.delete("--idempotency-key") if mutation
        repository_id = options.delete("--repository")
        if scope == "repository" && !repository_id
          raise Error.new("validation", "malformed_input", "--repository is required")
        end
        if scope.nil? && repository_id
          raise Error.new("validation", "malformed_input", "--repository is not allowed")
        end
        raise Error.new("validation", "malformed_input", "Arguments are malformed") unless options.empty?

        request = { "schema_version" => "1", "command" => command, "body" => body }
        request["repository_id"] = repository_id if repository_id
        unless @schema_registry.valid?("commands.json", "request", request)
          raise Error.new("validation", "malformed_input", "Arguments are malformed")
        end

        if mutation
          request["_mutation"] = true
          request["_idempotency_key"] = idempotency_key
        end
        request
      end

      private

      def parse_options(arguments, allowed)
        options = {}
        until arguments.empty?
          option = arguments.shift
          if option == "--json"
            raise Error.new("validation", "malformed_input", "Duplicate option: --json") if options.key?(option)

            options[option] = true
            next
          end
          unless allowed.include?(option) && arguments.first && !arguments.first.start_with?("--") &&
              !options.key?(option)
            raise Error.new("validation", "malformed_input", "Arguments are malformed")
          end

          options[option] = arguments.shift
        end
        options
      end

      def integer(value)
        Integer(value, 10)
      rescue ArgumentError
        value
      end

      def read_body(options, definitions)
        definitions.to_h do |field, option|
          value = options.delete(option)
          value = integer(value) if field == "limit" && value
          [ field, value ]
        end.compact
      end

      def mutation_body(options)
        path = options.delete("--input")
        key = options["--idempotency-key"]
        unless path && key&.match?(IDEMPOTENCY_KEY_FORMAT)
          raise Error.new("validation", "malformed_input", "--input and a valid --idempotency-key are required")
        end

        content = path == "-" ? @input.read : File.binread(path)
        value = Kos::JsonParser.parse(content)
        raise JSON::ParserError unless value.is_a?(Hash)

        value
      rescue JSON::ParserError, SystemCallError
        raise Error.new("validation", "malformed_input", "Mutation input must be a readable JSON object")
      end
    end

    class Client
      TRANSIENT_ERRORS = [ SocketError, SystemCallError, EOFError, IOError, Net::HTTPBadResponse,
        Net::HTTPHeaderSyntaxError, Net::ProtocolError, Net::OpenTimeout, OpenSSL::SSL::SSLError ].freeze

      PATHS = {
        "task_type.list" => "/api/v1/task-types",
        "workflow.list" => "/api/v1/workflow-versions",
        "workflow.get" => "/api/v1/workflow-versions/%<workflow_version_id>s",
        "workflow.export" => "/api/v1/workflow-versions/%<workflow_version_id>s/export",
        "workflow.publish" => "/api/v1/workflow-drafts/%<workflow_id>s/publication",
        "workflow.activate" => "/api/v1/task-types/%<task_type>s/current-workflow",
        "workflow_draft.get" => "/api/v1/workflow-drafts/%<workflow_id>s",
        "workflow_draft.import" => "/api/v1/workflow-drafts/%<workflow_id>s",
        "workflow_draft.validate" => "/api/v1/workflow-drafts/%<workflow_id>s/validation",
        "task.create" => "/api/v1/repositories/%<repository_id>s/tasks",
        "task.get" => "/api/v1/repositories/%<repository_id>s/tasks/%<task_number>s",
        "attempt.get" => "/api/v1/repositories/%<repository_id>s/attempts/%<attempt_id>s",
        "attempt.claim" => "/api/v1/repositories/%<repository_id>s/tasks/%<task_number>s/attempts/claim",
        "attempt.renew" => "/api/v1/repositories/%<repository_id>s/attempts/%<attempt_id>s/renew",
        "attempt.fail" => "/api/v1/repositories/%<repository_id>s/attempts/%<attempt_id>s/fail",
        "attempt.needs_human" => "/api/v1/repositories/%<repository_id>s/attempts/%<attempt_id>s/needs-human",
        "attempt.reconcile" => "/api/v1/repositories/%<repository_id>s/attempts/%<attempt_id>s/reconcile",
        "step.context" => "/api/v1/repositories/%<repository_id>s/attempts/%<attempt_id>s/step-context",
        "step.complete" => "/api/v1/repositories/%<repository_id>s/tasks/%<task_number>s/steps/complete",
        "worktree.get" => "/api/v1/repositories/%<repository_id>s/worktree-reservations/%<reservation_id>s",
        "worktree.reserve" => "/api/v1/repositories/%<repository_id>s/tasks/%<task_number>s/worktree-reservations",
        "worktree.confirm" => "/api/v1/repositories/%<repository_id>s/worktree-reservations/%<reservation_id>s/confirm",
        "worktree.reconcile" => "/api/v1/repositories/%<repository_id>s/worktree-reservations/%<reservation_id>s/reconcile",
        "worktree.release" => "/api/v1/repositories/%<repository_id>s/worktree-reservations/%<reservation_id>s/release",
        "effect.get" => "/api/v1/repositories/%<repository_id>s/repository-effects/%<effect_id>s",
        "effect.prepare" => "/api/v1/repositories/%<repository_id>s/tasks/%<task_number>s/repository-effects",
        "effect.reconcile" => "/api/v1/repositories/%<repository_id>s/repository-effects/%<effect_id>s/reconcile",
        "publication.get" => "/api/v1/repositories/%<repository_id>s/publications/%<publication_id>s",
        "publication.prepare" => "/api/v1/repositories/%<repository_id>s/tasks/%<task_number>s/publications",
        "publication.reconcile" => "/api/v1/repositories/%<repository_id>s/publications/%<publication_id>s/reconcile",
        "artifact.list" => "/api/v1/repositories/%<repository_id>s/tasks/%<task_number>s/artifacts"
      }.freeze

      def initialize(environment:, schema_registry: SchemaRegistry.new, sleeper: Kernel, random: Random)
        @environment = environment
        @schema_registry = schema_registry
        @sleeper = sleeper
        @random = random
      end

      def call(logical_request)
        token = @environment["KOS_API_TOKEN"].to_s
        raise Error.new("authentication", "authentication_required", "KOS_API_TOKEN is required") if token.empty?

        uri = request_uri(logical_request)
        timeout = request_timeout
        response = nil
        3.times do |attempt|
          response = perform(uri, token, timeout, logical_request)
          return response unless transient?(response) && attempt < 2

          delay(attempt, response, timeout)
        rescue Net::ReadTimeout, Timeout::Error
          response = local_failure(logical_request.fetch("command"), "transient", "request_timeout",
            "API request timed out")
          return response if attempt == 2

          delay(attempt, response, timeout)
        rescue *TRANSIENT_ERRORS
          response = local_failure(logical_request.fetch("command"), "transient", "transport_unavailable",
            "API transport is unavailable")
          return response if attempt == 2

          delay(attempt, response, timeout)
        end
        response
      end

      private

      def request_uri(logical_request)
        base = @environment.fetch("KOS_API_URL", "http://127.0.0.1:3000")
        base_uri = URI.parse(base)
        unless %w[http https].include?(base_uri.scheme) && base_uri.host && !base_uri.userinfo &&
            !base_uri.query && !base_uri.fragment
          raise Error.new("validation", "malformed_input", "KOS_API_URL is invalid")
        end

        body = logical_request.fetch("body")
        values = body.merge(body.fetch("preconditions", {}), "repository_id" => logical_request["repository_id"])
        path = format(PATHS.fetch(logical_request.fetch("command")), **values.transform_keys(&:to_sym))
        uri = URI.parse(base.delete_suffix("/") + path)
        query = logical_request.fetch("body").slice("limit", "cursor")
        uri.query = URI.encode_www_form(query) unless query.empty?
        uri
      rescue URI::InvalidURIError, KeyError
        raise Error.new("validation", "malformed_input", "KOS_API_URL is invalid")
      end

      def request_timeout
        value = @environment.fetch("KOS_API_TIMEOUT_SECONDS", "30")
        timeout = Integer(value, 10)
        raise ArgumentError unless timeout.positive?

        timeout
      rescue ArgumentError
        raise Error.new("validation", "malformed_input", "KOS_API_TIMEOUT_SECONDS must be a positive integer")
      end

      def perform(uri, token, timeout, logical_request)
        command = logical_request.fetch("command")
        request = if logical_request["_mutation"]
          Net::HTTP::Post.new(uri).tap do |post|
            post["Content-Type"] = "application/json"
            post["Idempotency-Key"] = logical_request.fetch("_idempotency_key")
            post.body = JSON.generate(logical_request.slice("schema_version", "command", "repository_id", "body"))
          end
        else
          Net::HTTP::Get.new(uri)
        end
        request["Authorization"] = "Bearer #{token}"
        request["Accept"] = "application/json"
        raw = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: timeout,
          read_timeout: timeout) { |http| http.request(request) }
        document = JSON.parse(raw.body)
        valid = @schema_registry.valid?("commands.json", "result", document) ||
          @schema_registry.valid?("envelopes.json", "failure", document)
        raise Error.new("internal", "internal_error", "API response failed schema validation") unless valid
        unless document.fetch("command") == command && raw.code.to_i == expected_status(document, command)
          raise Error.new("internal", "internal_error", "API response does not match the request")
        end

        document
      rescue JSON::ParserError
        raise Error.new("internal", "internal_error", "API response is not valid JSON")
      end

      def transient?(document)
        document.dig("error", "category") == "transient"
      end

      def expected_status(document, command)
        if document["data"]
          @schema_registry.success_status(command)
        else
          @schema_registry.error_status(document.dig("error", "code"))
        end
      end

      def delay(attempt, document, timeout)
        jitter = @random.rand * (attempt + 1) * 0.25
        retry_after = document.dig("error", "details", "retry_after_seconds")
        seconds = retry_after ? [ retry_after, jitter ].max : jitter
        @sleeper.sleep([ seconds, timeout ].min)
      end

      def local_failure(command, category, code, message)
        { "schema_version" => "1", "request_id" => SecureRandom.uuid, "command" => command,
          "error" => { "category" => category, "code" => code, "message" => message, "retryable" => true } }
      end
    end

    class Application
      EXIT_BY_CATEGORY = { "internal" => 1, "validation" => 2, "authentication" => 3,
        "authorization" => 4, "not_found" => 5, "conflict" => 6, "lease_lost" => 7, "transient" => 8 }.freeze

      def initialize(arguments, environment: ENV, stdout: $stdout, stderr: $stderr)
        @arguments = arguments
        @environment = environment
        @stdout = stdout
        @stderr = stderr
      end

      def run
        request = Parser.new.parse(@arguments.dup)
        document = Client.new(environment: @environment).call(request)
        write(document)
      rescue Error => error
        command = command_for_error(error)
        @stderr.puts(error.message)
        write({ "schema_version" => "1", "request_id" => SecureRandom.uuid, "command" => command,
          "error" => { "category" => error.category, "code" => error.code, "message" => error.message,
            "retryable" => false } })
      end

      private

      def command_for_error(error)
        return "unknown" if error.code == "unknown_command"

        Parser::COMMANDS.fetch(@arguments.first(2)).first
      end

      def write(document)
        @stdout.puts(JSON.generate(document))
        document["error"] ? EXIT_BY_CATEGORY.fetch(document.dig("error", "category")) : 0
      end
    end
  end
end
