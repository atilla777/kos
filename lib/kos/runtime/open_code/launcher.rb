require "json"
require "digest"
require "json_schemer"
require "open3"
require "pathname"
require "securerandom"
require "tmpdir"

require_relative "../../json_parser"
require_relative "../../cli/schema_registry"
require_relative "transport"

module Kos
  module Runtime
    module OpenCode
      class Launcher
        RUNTIME_VERSION = "1.18.26"
        RETROSPECTIVE_TIMEOUT = 30
        CONFIG_TIMEOUT = 5
        SOURCE_NODE_LIMIT = 10_000
        SOURCE_BYTE_LIMIT = 4 * 1024 * 1024
        MANIFEST_PATH = ".opencode/kos-runtime-manifest.json"
        MANAGED_RUNTIME_FILES = {
          ".opencode/skills/kos-cli/SKILL.md" => "skills/kos-cli/SKILL.md",
          ".opencode/skills/kos-initialize/SKILL.md" => "skills/kos-initialize/SKILL.md",
          ".opencode/skills/kos-orchestrate/SKILL.md" => "skills/kos-orchestrate/SKILL.md",
          ".opencode/skills/kos-repository/SKILL.md" => "skills/kos-repository/SKILL.md",
          ".opencode/skills/kos-retrospective/SKILL.md" => "skills/kos-retrospective/SKILL.md",
          ".opencode/skills/kos-workflow-step/SKILL.md" => "skills/kos-workflow-step/SKILL.md",
          ".opencode/plugins/kos-session-guard.js" => "runtime/opencode/plugins/kos-session-guard.js",
          ".opencode/agents/kos-orchestrate.md" => "runtime/opencode/agents/kos-orchestrate.md",
          ".opencode/agents/kos-retrospective.md" => "runtime/opencode/agents/kos-retrospective.md",
          ".opencode/agents/kos-workflow-step.md" => "runtime/opencode/agents/kos-workflow-step.md"
        }.freeze
        CAPABILITY_REPORT_DIGEST =
          "sha256:7c89e36d7d333e217b8f08f5d772efae415224a88dc757808158100d956f1762".freeze
        RELEASE_DIGESTS = {
          ".opencode/skills/kos-cli/SKILL.md" =>
            "sha256:42694b7dd4fa28485a4de5261bee35f1e8e327f6cade3b0b44c2727baa732214",
          ".opencode/skills/kos-initialize/SKILL.md" =>
            "sha256:b03e1f66dccf03ae2832c80e7616cb84d9b766b597cf6ac9fbe31abfcb5d2aba",
          ".opencode/skills/kos-orchestrate/SKILL.md" =>
            "sha256:5c7a28e9d3a3739521c5f59677c7a9e7133a70fa54d2cc1d4e3b5f40dd3677a1",
          ".opencode/skills/kos-repository/SKILL.md" =>
            "sha256:3e5d0ef4ea009ef25291768af4deacb89dd9ed6ee5377d55f6d3d132fa6afa19",
          ".opencode/skills/kos-retrospective/SKILL.md" =>
            "sha256:95194b6808b48f1ac693d5bd3ea470aa162faf8d3daed069e73668dd633cb245",
          ".opencode/skills/kos-workflow-step/SKILL.md" =>
            "sha256:aedbc44db0301d4da1d7d24ee49944ba12613900603f12ec716c5453d1d1a05e",
          ".opencode/plugins/kos-session-guard.js" =>
            "sha256:0a3efc7723e07c46e88072fc24d1ea8d6196bb6d10b0eae16859e0b0685c4df8",
          ".opencode/agents/kos-orchestrate.md" =>
            "sha256:9eed6799ce455422256949b7341128506f9a5ffcae53418a8be3d0623bbddb3f",
          ".opencode/agents/kos-retrospective.md" =>
            "sha256:fb95396919699af62e812ffe2f4e49700846081ec0bb1cafd50f6bd73ea34bf6",
          ".opencode/agents/kos-workflow-step.md" =>
            "sha256:b218cbf2a1ad27c0e3fccb09f86749fa9e599df06c0b46af64eb230a91c0d6bb"
        }.freeze
        CRITICAL_RELEASE_PATHS = %w[
          .opencode/plugins/kos-session-guard.js
          .opencode/agents/kos-retrospective.md
          .opencode/skills/kos-retrospective/SKILL.md
        ].freeze
        RETROSPECTIVE_ENVIRONMENT_KEYS = %w[
          HOME USER LOGNAME PATH SHELL TMPDIR LANG LC_ALL LC_CTYPE TZ
          XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME XDG_RUNTIME_DIR
          OPENCODE_DISABLE_AUTOUPDATE OPENCODE_DISABLE_DEFAULT_PLUGINS OPENCODE_DISABLE_MODELS_FETCH
          OPENCODE_DISABLE_CLAUDE_CODE OPENCODE_LOG_LEVEL NO_PROXY
        ].freeze
        # Ambient credentials are retained only when an explicit model selects their known provider.
        PROVIDER_CREDENTIAL_KEYS = {
          "anthropic" => %w[ANTHROPIC_API_KEY], "openai" => %w[OPENAI_API_KEY],
          "google" => %w[GOOGLE_GENERATIVE_AI_API_KEY GOOGLE_API_KEY], "groq" => %w[GROQ_API_KEY],
          "openrouter" => %w[OPENROUTER_API_KEY], "xai" => %w[XAI_API_KEY],
          "mistral" => %w[MISTRAL_API_KEY], "deepseek" => %w[DEEPSEEK_API_KEY],
          "amazon-bedrock" => %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION AWS_DEFAULT_REGION]
        }.freeze
        MODEL_FORMAT = %r{\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}/[A-Za-z0-9][A-Za-z0-9._/-]{0,254}\z}
        SENSITIVE_TEXT = [ /(?:api[_-]?key|token|secret|password)\s*[:=]\s*\S+/i,
          /\b[A-Z][A-Z0-9_]{2,}\s*=\s*\S+/, %r{(?:\A|\s)/(?:home|Users|root)/\S+},
          /[A-Za-z]:\\Users\\\S+/ ].freeze
        Result = Data.define(:stdout, :stderr, :status, :timed_out, :stdout_truncated, :stderr_truncated)

        class ProcessRunner
          CAPTURE_LIMIT = 16 * 1024 * 1024

          def call(command, chdir:, environment: {}, timeout: nil, stdout: nil, stderr: nil, unsetenv_others: false)
            Open3.popen3(environment, *command, chdir: chdir, pgroup: true,
              unsetenv_others: unsetenv_others) do |input, out, err, wait|
              input.close
              out_reader = read_stream(out, stdout)
              err_reader = read_stream(err, stderr)
              timed_out = !join(wait, timeout)
              terminate(wait.pid, wait) if timed_out
              finish_reader(out_reader, out)
              finish_reader(err_reader, err)
              Result.new(stdout: out_reader[:bytes], stderr: err_reader[:bytes], status: wait.value,
                timed_out: timed_out, stdout_truncated: out_reader[:truncated] == true,
                stderr_truncated: err_reader[:truncated] == true)
            end
          end

          private

          def read_stream(stream, destination)
            Thread.new do
              bytes = +""
              bytes.force_encoding(Encoding::BINARY)
              Thread.current[:bytes] = bytes
              while (chunk = stream.read(16 * 1024))
                destination&.write(chunk)
                destination&.flush
                remaining = CAPTURE_LIMIT - bytes.bytesize
                bytes << chunk.byteslice(0, remaining) if remaining.positive?
                Thread.current[:truncated] = true if chunk.bytesize > remaining
              end
            end
          end

          def join(wait, seconds)
            seconds ? wait.join(seconds) : wait.join
          end

          def terminate(pid, wait)
            Process.kill("TERM", -pid)
            return if wait.join(0.1)

            Process.kill("KILL", -pid)
            raise IOError, "timed-out process did not terminate" unless wait.join(1)
          rescue Errno::ESRCH
            nil
          end

          def finish_reader(reader, stream)
            return if reader.join(1)

            stream.close
            raise IOError, "process output did not close" unless reader.join(0.1)
          rescue IOError
            raise if reader.alive?
          end
        end

        def initialize(environment: ENV, stdout: $stdout, stderr: $stderr, runner: ProcessRunner.new,
          retrospective_output: nil, schema_registry: Kos::Cli::SchemaRegistry.new,
          retrospective_wait_timeout: RETROSPECTIVE_TIMEOUT)
          @environment = environment
          @stdout = stdout
          @stderr = stderr
          @runner = runner
          @retrospective_output = retrospective_output || output_from_environment
          @schema_registry = schema_registry
          @retrospective_wait_timeout = retrospective_wait_timeout
        end

        def run(arguments)
          worktree, model, prompt = parse(arguments)
          return 2 unless worktree
          return 1 unless pinned_runtime?(worktree)

          enabled = sample_retrospective_enabled(worktree)
          integrity = runtime_integrity_snapshot(worktree) if enabled
          enabled &&= !integrity.nil?
          primary = @runner.call(primary_command(worktree, model, prompt), chdir: worktree,
            environment: primary_environment(enabled), stdout: @stdout, stderr: @stderr)
          status = process_exit_status(primary)
          best_effort_retrospective(worktree, model, prompt, primary, integrity) if enabled && graceful?(primary)
          status
        rescue SystemCallError, ArgumentError => error
          @stderr.puts("kos-opencode: #{error.message}")
          1
        end

        private

        def parse(arguments)
          separator = arguments.index("--")
          return invalid_arguments unless separator

          options = parse_options(arguments.take(separator))
          prompt = arguments.drop(separator + 1)
          return invalid_arguments unless options && !prompt.empty? && prompt.none? { |value| value.include?("\0") }

          worktree = canonical_directory(options.fetch("--worktree"))
          model = options["--model"]
          return invalid_arguments unless worktree && (!model || model.match?(MODEL_FORMAT))

          [ worktree, model, prompt ]
        end

        def parse_options(values)
          result = {}
          until values.empty?
            name = values.shift
            return unless %w[--worktree --model].include?(name) && !result.key?(name)
            return if values.empty? || values.first.start_with?("--")

            result[name] = values.shift
          end
          result if result.key?("--worktree")
        end

        def invalid_arguments
          @stderr.puts("usage: kos-opencode --worktree ABSOLUTE_PATH [--model PROVIDER/MODEL] -- PROMPT")
          nil
        end

        def canonical_directory(value)
          path = Pathname.new(value)
          return unless path.absolute? && path.cleanpath.to_s == value && File.directory?(value) && !File.symlink?(value)

          path.realpath.to_s if path.realpath.to_s == value
        rescue SystemCallError, ArgumentError
          nil
        end

        def pinned_runtime?(worktree)
          result = @runner.call([ opencode, "--version" ], chdir: worktree, timeout: CONFIG_TIMEOUT)
          return true if !result.timed_out && result.status.success? && result.stdout.strip == RUNTIME_VERSION

          @stderr.puts("kos-opencode: OpenCode #{RUNTIME_VERSION} is required")
          false
        end

        def sample_retrospective_enabled(worktree)
          result = @runner.call([ kos, "runtime-config", "get", "--json" ], chdir: worktree,
            timeout: CONFIG_TIMEOUT)
          return false if result.timed_out || !result.status.success?

          document = Kos::JsonParser.parse(result.stdout)
          valid = @schema_registry.valid?("commands.json", "result", document) &&
            document["schema_version"] == "1" && document["command"] == "runtime_config.get"
          valid && document.dig("data", "retrospective_enabled") == true
        rescue StandardError
          false
        end

        def primary_command(worktree, model, prompt)
          command = [ opencode, "run", "--format", "json", "--agent", "kos-orchestrate", "--dir", worktree,
            "--title", "KOS orchestration" ]
          command.concat([ "--model", model ]) if model
          command << "--"
          command.concat(prompt)
        end

        def primary_environment(enabled)
          { "KOS_RETROSPECTIVE_ENABLED" => enabled ? "1" : "0" }
        end

        def best_effort_retrospective(worktree, model, prompt, primary, integrity)
          runtime_session_id = root_session_id(primary.stdout)
          return unless runtime_session_id

          invocation = invocation_document
          unless !primary.stdout_truncated && !primary.stderr_truncated && runtime_integrity_unchanged?(worktree, integrity)
            return write_delivery(no_result_delivery(runtime_session_id, invocation, "transport_failure"))
          end

          command = [ opencode, "--pure", "run", "--format", "json", "--agent", "kos-retrospective",
            "--dir", worktree, "--session", runtime_session_id ]
          command.concat([ "--model", model ]) if model
          command.concat([ "--", JSON.generate(invocation) ])
          result = Dir.mktmpdir("kos-opencode-retrospective-") do |config_home|
            environment = retrospective_environment(model).merge("XDG_CONFIG_HOME" => config_home)
            @runner.call(command, chdir: worktree, environment: environment,
              timeout: @retrospective_wait_timeout, unsetenv_others: true)
          end
          write_delivery(retrospective_delivery(runtime_session_id, invocation, result,
            primary.stdout, prompt))
        rescue StandardError
          write_delivery(no_result_delivery(runtime_session_id, invocation, "transport_failure")) if
            runtime_session_id && invocation
        end

        def invocation_document
          { "schema_version" => "1", "session_id" => SecureRandom.uuid, "source" => "orchestrator",
            "retrospective_enabled" => true, "lifecycle_eligible" => true, "recursion_suppressed" => true,
            "primary_result_acknowledged" => true, "timeout_seconds" => RETROSPECTIVE_TIMEOUT }
        end

        def root_session_id(output)
          ids = output.lines.filter_map do |line|
            value = JSON.parse(line)
            value["sessionID"] if value.is_a?(Hash) && value["sessionID"].is_a?(String)
          rescue JSON::ParserError
            nil
          end.uniq
          ids.one? ? ids.first : nil
        end

        def retrospective_delivery(runtime_session_id, invocation, process, output, prompt)
          reason = if process.timed_out
            "timeout"
          elsif process.stdout_truncated || process.stderr_truncated
            "transport_failure"
          elsif !process.status.success?
            "provider_failure"
          end
          return no_result_delivery(runtime_session_id, invocation, reason) if reason

          result = parse_retrospective_result(process.stdout, runtime_session_id)
          return no_result_delivery(runtime_session_id, invocation, "malformed_result") unless
            result && bound_result?(result, invocation) && sanitized_result?(result, output, prompt)

          delivery_base(runtime_session_id, invocation).merge("outcome" => "result", "result" => result)
        end

        def delivery_base(runtime_session_id, invocation)
          { "schema_version" => "1", "runtime" => "opencode", "runtime_session_id" => runtime_session_id,
            "invocation" => invocation }
        end

        def no_result_delivery(runtime_session_id, invocation, reason)
          delivery_base(runtime_session_id, invocation).merge("outcome" => "no_result", "reason" => reason)
        end

        def parse_retrospective_result(output, session_id)
          text = output.lines.filter_map do |line|
            event = JSON.parse(line)
            part = event["part"]
            part["text"] if event["type"] == "text" && event["sessionID"] == session_id &&
              part.is_a?(Hash) && part["type"] == "text" && part.dig("time", "end")
          rescue JSON::ParserError
            nil
          end.join
          Kos::JsonParser.parse(text)
        rescue JSON::ParserError
          nil
        end

        def bound_result?(result, invocation)
          Transport.valid_retrospective_result?(result) &&
            result.values_at("session_id", "source", "primary_result_acknowledged") ==
              invocation.values_at("session_id", "source", "primary_result_acknowledged")
        end

        def sanitized_result?(result, output, prompt)
          texts = proposal_text(result)
          return false if texts.any? { |text| SENSITIVE_TEXT.any? { |pattern| text.match?(pattern) } }

          budget = { nodes: 0, bytes: 0 }
          return false unless source_value_safe?(prompt, texts, budget)

          output.each_line.all? do |line|
            value = JSON.parse(line)
            !value.is_a?(Hash) || !value["sessionID"].is_a?(String) ||
              source_value_safe?(value.fetch("part", {}), texts, budget)
          rescue JSON::ParserError
            texts.none? { |text| line.include?(text) }
          end
        end

        def proposal_text(result)
          result.fetch("proposals").flat_map do |proposal|
            proposal.values_at("problem", "observed_impact", "sanitized_evidence", "proposed_outcome") +
              proposal.fetch("uncertainties")
          end
        end

        def source_value_safe?(value, texts, budget)
          budget[:nodes] += 1
          return false if budget[:nodes] > SOURCE_NODE_LIMIT

          case value
          when Hash then value.values.all? { |item| source_value_safe?(item, texts, budget) }
          when Array then value.all? { |item| source_value_safe?(item, texts, budget) }
          when String
            budget[:bytes] += value.bytesize
            budget[:bytes] <= SOURCE_BYTE_LIMIT && texts.none? do |text|
              value.length >= 8 && (value.include?(text) || text.include?(value))
            end
          else true
          end
        end

        def write_delivery(delivery)
          return unless @retrospective_output && Transport.valid_retrospective_delivery?(delivery)

          bytes = "#{JSON.generate(delivery)}\n"
          if @retrospective_output.respond_to?(:write_nonblock)
            @retrospective_output.write_nonblock(bytes, exception: false)
          else
            @retrospective_output.write(bytes)
          end
        rescue StandardError
          nil
        end

        def output_from_environment
          value = @environment["KOS_RETROSPECTIVE_FD"]
          return unless value

          descriptor = Integer(value, 10)
          return if descriptor < 3

          output = IO.for_fd(descriptor, "w", autoclose: false)
          output.dup if output.stat.file?
        rescue ArgumentError, SystemCallError
          nil
        end

        def retrospective_environment(model)
          provider = model&.split("/", 2)&.first
          keys = RETROSPECTIVE_ENVIRONMENT_KEYS + PROVIDER_CREDENTIAL_KEYS.fetch(provider, [])
          keys.filter_map { |key| [ key, @environment.fetch(key) ] if @environment.key?(key) }.to_h
            .merge("KOS_RETROSPECTIVE_ACTIVE" => "1", "KOS_RETROSPECTIVE_ENABLED" => "0")
        end

        def runtime_integrity_snapshot(worktree)
          return if @environment.key?("OPENCODE_CONFIG") || @environment.key?("OPENCODE_CONFIG_CONTENT")

          configuration = project_configuration(worktree)
          return if configuration == :ambiguous

          manifest_path = File.join(worktree, MANIFEST_PATH)
          paths = [ *MANAGED_RUNTIME_FILES.keys, configuration ].compact
          if File.exist?(manifest_path) || File.symlink?(manifest_path)
            manifest = read_regular_file(worktree, MANIFEST_PATH)
            document = Kos::JsonParser.parse(manifest)
            schema = JSONSchemer.schema(JSON.parse(File.read(
              File.expand_path("../../../../schemas/installation/v1/installer.json", __dir__))))
            return unless schema.ref("#/$defs/manifest").valid?(document)
            return unless valid_manifest_contract?(document, worktree)

            paths.unshift(MANIFEST_PATH)
          else
            return unless exact_release_files?(worktree)
          end
          { configuration: configuration,
            digests: paths.to_h { |path| [ path, digest(read_regular_file(worktree, path)) ] } }
        rescue StandardError
          nil
        end

        def valid_manifest_contract?(manifest, worktree)
          entries = manifest.fetch("managed_files")
          inventory = entries.map { |entry| [ entry.fetch("path"), entry.fetch("source") ] }
          return false unless inventory == MANAGED_RUNTIME_FILES.to_a
          return false unless manifest.fetch("capability_report_digest") == CAPABILITY_REPORT_DIGEST
          return false unless manifest.dig("repository", "worktree_root") == worktree
          return false unless manifest.fetch("source_bundle_digest") == digest(canonical_json(entries))

          installed = entries.to_h { |entry| [ entry.fetch("path"), digest(read_regular_file(worktree,
            entry.fetch("path"))) ] }
          entries.all? { |entry| installed.fetch(entry.fetch("path")) == entry.fetch("digest") } &&
            CRITICAL_RELEASE_PATHS.all? { |path| installed.fetch(path) == RELEASE_DIGESTS.fetch(path) }
        end

        def exact_release_files?(worktree)
          RELEASE_DIGESTS.all? do |path, expected|
            digest(read_regular_file(worktree, path)) == expected
          end
        end

        def project_configuration(worktree)
          candidates = %w[opencode.json opencode.jsonc].select do |name|
            path = File.join(worktree, name)
            File.exist?(path) || File.symlink?(path)
          end
          candidates.length > 1 ? :ambiguous : candidates.first
        end

        def runtime_integrity_unchanged?(worktree, snapshot)
          return false unless project_configuration(worktree) == snapshot.fetch(:configuration)

          snapshot.fetch(:digests).all? { |path, expected| digest(read_regular_file(worktree, path)) == expected }
        rescue StandardError
          false
        end

        def read_regular_file(worktree, relative)
          path = File.join(worktree, relative)
          stat = File.lstat(path)
          raise IOError, "managed runtime file is not regular" unless stat.file? && !stat.symlink?

          File.binread(path)
        end

        def digest(bytes)
          "sha256:#{Digest::SHA256.hexdigest(bytes)}"
        end

        def canonical_json(value)
          case value
          when Hash
            "{#{value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(',')}}"
          when Array then "[#{value.map { |item| canonical_json(item) }.join(',')}]"
          else JSON.generate(value)
          end
        end

        def graceful?(process)
          !process.timed_out && process.status.exited?
        end

        def process_exit_status(process)
          return process.status.exitstatus if process.status.exited?

          process.status.signaled? ? 128 + process.status.termsig : 1
        end

        def opencode
          @environment.fetch("KOS_OPENCODE_EXECUTABLE", "opencode")
        end

        def kos
          @environment.fetch("KOS_EXECUTABLE", "kos")
        end
      end
    end
  end
end
