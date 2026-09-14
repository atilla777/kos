require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tempfile"
require "timeout"
require "tmpdir"

require_relative "deterministic_provider"
require_relative "launcher"
require_relative "transport"

module Kos
  module Runtime
    module OpenCode
      class CapabilityVerifier
        class Incompatible < StandardError; end

        VERSION = "1.18.26"
        CAPABILITY_MESSAGES = {
          "skill_discovery" => "Discovered the isolated installed skill bundle",
          "non_interactive_json" => "Completed the real pinned runtime through JSON events",
          "subagent_launch" => "Launched and retained a foreground workflow-step child",
          "worktree_cwd" => "Observed the explicit worktree in parent and child sessions",
          "typed_effect_round_trip" => "Delivered a typed effect result to the retained child",
          "retrospective_agent_isolation" =>
            "Resolved deny-all retrospective tools and the required embedded procedure markers",
          "retrospective_root_post_primary" =>
            "Launcher sampled enabled config, preserved primary bytes/status, and delivered an FD result from the same root",
          "retrospective_child_delivery" =>
            "Plugin continued the retained kos-workflow-step child after its final primary result",
          "retrospective_disabled_suppression" => "Rejected child retrospective while installation enablement was disabled",
          "retrospective_recursion_suppression" => "Rejected child retrospective while recursion suppression was active",
          "retrospective_child_timeout_independence" =>
            "Plugin returned one child timeout no-result and completed the parent without a late retrospective delivery",
          "retrospective_timeout_failure_independence" =>
            "Launcher preserved the primary result across real provider failure and a 30-second timeout with no late delivery"
        }.freeze
        CAPABILITIES = CAPABILITY_MESSAGES.keys.freeze
        INSTALLED_SKILLS = %w[
          kos-cli kos-initialize kos-orchestrate kos-repository kos-retrospective kos-workflow-step
        ].freeze
        INSTALLED_AGENTS = %w[kos-orchestrate kos-retrospective kos-workflow-step].freeze
        AGENT_CONTRACTS = {
          "kos-orchestrate" => {
            "mode" => "primary", "tools" => { "invalid" => false, "bash" => true, "skill" => true,
              "task" => true },
            "permissions" => [ [ "*", "*", "deny" ], [ "bash", "*", "deny" ],
              [ "bash", "kos *", "allow" ], [ "bash", "kos-repository *", "allow" ],
              [ "skill", "*", "deny" ], [ "skill", "kos-cli", "allow" ],
              [ "skill", "kos-orchestrate", "allow" ], [ "skill", "kos-repository", "allow" ],
              [ "task", "*", "deny" ], [ "task", "kos-workflow-step", "allow" ],
              [ "child_retrospective", "*", "allow" ] ]
          },
          "kos-retrospective" => {
            "mode" => "primary", "deny_all_tools" => true,
            "permissions" => [ [ "*", "*", "deny" ] ]
          },
          "kos-workflow-step" => {
            "mode" => "subagent", "tools" => { "invalid" => false, "bash" => true, "skill" => true,
              "task" => false },
            "permissions" => [ [ "*", "*", "deny" ], [ "bash", "*", "allow" ],
              [ "bash", "git *", "deny" ], [ "bash", "kos *", "deny" ],
              [ "bash", "kos-repository *", "deny" ], [ "edit", "*", "allow" ],
              [ "skill", "*", "deny" ], [ "skill", "kos-workflow-step", "allow" ],
              [ "task", "*", "deny" ] ]
          }
        }.freeze
        AGENT_ENABLED_TOOLS = {
          "kos-orchestrate" => %w[bash child_retrospective skill task],
          "kos-retrospective" => [],
          "kos-workflow-step" => %w[bash edit skill write]
        }.freeze
        RETROSPECTIVE_PROCEDURE_MARKERS = [
          "only concrete friction, failure, ambiguity, unsafe behavior, or repeated waste",
          "Do not turn ordinary successful work, stylistic preference, or speculation into a proposal",
          "Determine the observed impact without quoting the dialogue",
          "systemic problem from a one-off outcome",
          "smallest independently actionable improvement outcome",
          "Split mixed findings when their corrections can be delivered independently",
          "Retain every material uncertainty",
          "return `no_action` when there is no useful finding, evidence is insufficient, sanitization is unsafe",
          "`kos_product` covers KOS Rails, CLI, schemas, runtime adapters, or canonical KOS skills",
          "`kos_installation` covers installation configuration, installed-copy drift, or supported-runtime compatibility",
          "`workflow` covers a shared workflow version, instruction, template, transition, or artifact contract",
          "`project` covers target-project rules, documentation, source, tests, or repository-specific guidance",
          "Return exactly one JSON object and no prose",
          "Never use tools, mutate state, read or write files, invoke Git, access the network, launch agents",
          "Omit secrets, environment assignments, personal data, unrelated content, and private absolute paths"
        ].freeze

        def self.expected_report
          { "schema_version" => "1", "runtime" => "opencode", "runtime_version" => VERSION,
            "compatible" => true, "observations" => CAPABILITIES.to_h do |capability|
              [ capability, { "outcome" => "passed", "message" => CAPABILITY_MESSAGES.fetch(capability) } ]
            end }
        end

        def self.report_digest(report = expected_report)
          "sha256:#{Digest::SHA256.hexdigest(canonical_json(report))}"
        end

        def self.canonical_json(value)
          case value
          when Hash
            "{#{value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(',')}}"
          when Array then "[#{value.map { |item| canonical_json(item) }.join(',')}]"
          else JSON.generate(value)
          end
        end

        DEFAULT_TIMEOUT = Launcher::RETROSPECTIVE_TIMEOUT + 15

        def initialize(executable:, launcher_executable:, staged_opencode:, path: ENV.fetch("PATH", ""),
          timeout: DEFAULT_TIMEOUT)
          @executable = executable
          @launcher_executable = launcher_executable
          @staged_opencode = staged_opencode
          @path = path
          @timeout = timeout
        end

        def call
          parent = File.dirname(@staged_opencode)
          Dir.mktmpdir("kos-opencode-capability-", parent) do |directory|
            directory = File.realpath(directory)
            verify_version(directory)
            verify_installed_bundle(directory)
            verify_positive_contract(directory)
            verify_launcher_root_contract(directory)
            verify_guard_rejection(directory)
            verify_retrospective_suppression(directory, active: false)
            verify_retrospective_suppression(directory, active: true)
            verify_child_timeout_contract(directory)
            verify_launcher_failure_contract(directory)
            verify_launcher_timeout_contract(directory)
          end
          report = self.class.expected_report
          raise Incompatible, "Capability report failed its closed schema" unless
            Transport.schema.ref("#/$defs/capability_report").valid?(report)

          report
        rescue Incompatible
          raise
        rescue JSON::ParserError, KeyError, SystemCallError, Transport::InvalidExchange => error
          raise Incompatible, "OpenCode capability verification failed: #{error.class}"
        end

        private

        def verify_version(directory)
          stdout, = capture(directory, @executable, "--version")
          raise Incompatible, "OpenCode #{VERSION} is required" unless stdout.strip == VERSION
        end

        def verify_installed_bundle(directory)
          project = File.join(directory, "installed-bundle")
          FileUtils.mkdir_p(File.join(project, "nested"))
          FileUtils.cp_r(@staged_opencode, File.join(project, ".opencode"))
          write_marker(File.join(project, ".opencode"))
          _stdout, _stderr, status = capture(directory, "git", "init", "--quiet", project)
          raise Incompatible, "Capability worktree initialization failed" unless status.success?

          INSTALLED_SKILLS.each { |skill| verify_installed_skill(directory, project, skill) }

          INSTALLED_AGENTS.each do |agent|
            definition, = capture(directory, @executable, "debug", "agent", agent,
              chdir: File.join(project, "nested"))
            verify_agent_definition!(agent, parse_json(definition, "installed #{agent} agent report"))
          end
        end

        def verify_installed_skill(directory, project, expected)
          skills = File.join(project, ".opencode", "skills")
          hold = Dir.mktmpdir("kos-skill-hold-", directory)
          moved = Dir.children(skills).reject { |entry| entry == expected }
          moved.each { |entry| File.rename(File.join(skills, entry), File.join(hold, entry)) }
          stdout, = capture(directory, @executable, "debug", "skill", chdir: File.join(project, "nested"))
          discovered = parse_json(stdout, "installed skill report")
          raise Incompatible, "OpenCode did not discover the complete installed skill bundle" unless
            discovered.any? { |skill| skill["name"] == expected }
        ensure
          moved&.each do |entry|
            source = File.join(hold, entry)
            File.rename(source, File.join(skills, entry)) if File.exist?(source)
          end
          FileUtils.rm_rf(hold) if hold
        end

        def verify_agent_definition!(name, definition)
          contract = AGENT_CONTRACTS.fetch(name)
          tools = definition.fetch("tools")
          permissions = definition.fetch("permission")
          failures = []
          failures << "identity" unless definition["name"] == name
          failures << "mode" unless definition["mode"] == contract.fetch("mode")
          enabled_tools = tools.select { |_tool, enabled| enabled }.keys.sort
          expected_tools = AGENT_ENABLED_TOOLS.fetch(name).sort
          unless enabled_tools == expected_tools
            failures << "tools(extra=#{(enabled_tools - expected_tools).join(',')}," \
              "missing=#{(expected_tools - enabled_tools).join(',')})"
          end
          failures << "permissions" unless contract.fetch("permissions").all? do |permission, pattern, action|
            effective_permission(permissions, permission, pattern) == action
          end
          actual_allows = effective_allows(permissions, tools.keys)
          allowed = expected_allows(contract)
          unless actual_allows == allowed
            extra = (actual_allows - allowed).map(&:first).uniq.sort
            missing = (allowed - actual_allows).map(&:first).uniq.sort
            failures << "authority(extra=#{extra.join(',')},missing=#{missing.join(',')})"
          end
          failures << "procedure" if name == "kos-retrospective" && !retrospective_procedure?(definition["prompt"])
          raise Incompatible, "Installed #{name} agent violates its restrictive #{failures.join('/')} contract" unless
            failures.empty?
        rescue KeyError, NoMethodError
          raise Incompatible, "Installed #{name} agent is malformed"
        end

        def effective_permission(entries, permission, pattern)
          entry = entries.reverse.find do |candidate|
            [ "*", permission ].include?(candidate["permission"]) &&
              [ "*", pattern ].include?(candidate["pattern"])
          end
          entry&.fetch("action", nil)
        end

        def effective_allows(entries, tool_names)
          entries.filter_map do |entry|
            permission = entry.fetch("permission")
            pattern = entry.fetch("pattern")
            if tool_names.include?(permission) && effective_permission(entries, permission, pattern) == "allow"
              [ permission, pattern ]
            end
          end.uniq.sort
        end

        def expected_allows(contract)
          contract.fetch("permissions").filter_map do |permission, pattern, action|
            [ permission, pattern ] if action == "allow"
          end.sort
        end

        def retrospective_procedure?(prompt)
          prompt.is_a?(String) && RETROSPECTIVE_PROCEDURE_MARKERS.all? { |marker| prompt.include?(marker) }
        end

        def verify_positive_contract(directory)
          provider = DeterministicProvider.new
          provider.start
          project = prepare_project(directory, "positive", provider.base_url, read_only: false)
          verify_discovery(directory, project)
          FileUtils.chmod_R(0o555, File.join(project, ".opencode"))
          stdout, stderr, status = run_opencode(directory, project)
          raise Incompatible, "OpenCode non-interactive run failed" unless status.success?

          verify_events(stdout, provider.requests, project)
        ensure
          restore_permissions(project)
          provider&.stop
        end

        def verify_retrospective_suppression(directory, active:)
          provider = DeterministicProvider.new
          provider.start
          project = prepare_project(directory, active ? "recursive" : "disabled", provider.base_url)
          stdout, = run_opencode(directory, project, retrospective_enabled: active, retrospective_active: active)
          verify_rejected_retrospective(stdout, provider.requests, active ? "recursive" : "disabled")
        ensure
          restore_permissions(project)
          provider&.stop
        end

        def verify_guard_rejection(directory)
          provider = DeterministicProvider.new(invalid_continuation: true)
          provider.start
          project = prepare_project(directory, "guard", provider.base_url)
          stdout, = run_opencode(directory, project)
          events = parse_events(stdout)
          rejected = events.any? do |event|
            event["type"] == "tool_use" && event.dig("part", "tool") == "task" &&
              event.dig("part", "state", "status") == "error" &&
              JSON.generate(event.dig("part", "state", "error")).include?("unretained child session")
          end
          raise Incompatible, "Session guard accepted an unretained child" unless rejected
        ensure
          restore_permissions(project)
          provider&.stop
        end

        def verify_child_timeout_contract(directory)
          provider = DeterministicProvider.new(retrospective_result: :delayed)
          provider.start
          project = prepare_project(directory, "child-timeout", provider.base_url)
          stdout, = run_opencode(directory, project)
          provider.stop
          events = parse_events(stdout)
          deliveries = events.filter_map do |event|
            next unless event["type"] == "tool_use" && event.dig("part", "tool") == "child_retrospective" &&
              event.dig("part", "state", "status") == "completed"

            JSON.parse(event.dig("part", "state", "output"))
          end
          valid = deliveries.one? && deliveries.first.values_at("outcome", "reason") == %w[no_result timeout] &&
            completed_primary?(events)
          raise Incompatible, "Child retrospective timeout did not preserve the completed parent" unless valid
        ensure
          restore_permissions(project)
          provider&.stop
        end

        def prepare_project(directory, name, base_url, read_only: true)
          project = File.join(directory, "#{name}-worktree")
          FileUtils.mkdir_p([ File.join(project, "nested"), File.join(project, ".opencode") ])
          FileUtils.cp_r("#{@staged_opencode}/.", File.join(project, ".opencode"))
          FileUtils.rm_f(File.join(project, ".opencode", "kos-runtime-manifest.json"))
          write_probe(project)
          write_marker(File.join(project, ".opencode"))
          write_config(project, base_url)
          _stdout, _stderr, status = capture(directory, "git", "init", "--quiet", project)
          raise Incompatible, "Capability worktree initialization failed" unless status.success?

          FileUtils.chmod_R(0o555, File.join(project, ".opencode")) if read_only
          project
        end

        def write_probe(project)
          skill = File.join(project, ".opencode/skills/kos-contract-probe")
          FileUtils.mkdir_p(skill)
          File.write(File.join(skill, "SKILL.md"), <<~MARKDOWN)
            ---
            name: kos-contract-probe
            description: Deterministic local OpenCode capability probe.
            ---
            KOS_CONTRACT_SKILL
          MARKDOWN
          agents = File.join(project, ".opencode/agents")
          FileUtils.mkdir_p(agents)
          File.write(File.join(agents, "kos-contract-orchestrator.md"), orchestrator_agent)
        end

        def orchestrator_agent
          <<~MARKDOWN
            ---
            description: Runs the isolated KOS OpenCode capability contract.
            mode: primary
            permission:
              "*": deny
              bash: { "*": deny, "pwd": allow }
              task: { "*": deny, "kos-workflow-step": allow }
              child_retrospective: allow
            ---
            KOS_CONTRACT_PARENT
            Follow the deterministic provider tool calls exactly.
          MARKDOWN
        end

        def write_config(project, base_url)
          config = { "$schema" => "https://opencode.ai/config.json", "model" => "kos-contract/kos-contract",
            "small_model" => "kos-contract/kos-contract", "share" => "disabled", "autoupdate" => false,
            "provider" => { "kos-contract" => { "npm" => "@ai-sdk/openai-compatible", "name" => "KOS Contract",
              "options" => { "baseURL" => base_url, "apiKey" => "contract-only" },
              "models" => { "kos-contract" => { "name" => "KOS Contract" } } } } }
          File.write(File.join(project, "opencode.json"), JSON.pretty_generate(config))
        end

        def verify_discovery(directory, project)
          skills = File.join(project, ".opencode", "skills")
          hold = Dir.mktmpdir("kos-probe-hold-", directory)
          moved = Dir.children(skills).reject { |entry| entry == "kos-contract-probe" }
          moved.each { |entry| File.rename(File.join(skills, entry), File.join(hold, entry)) }
          stdout, = capture(directory, @executable, "debug", "skill", chdir: File.join(project, "nested"))
          skill = parse_json(stdout, "probe skill report").find { |candidate| candidate["name"] == "kos-contract-probe" }
          expected = File.join(project, ".opencode/skills/kos-contract-probe/SKILL.md")
          raise Incompatible, "Project skill was not discovered from nested cwd" unless skill&.fetch("location") == expected
        ensure
          moved&.each do |entry|
            source = File.join(hold, entry)
            File.rename(source, File.join(skills, entry)) if File.exist?(source)
          end
          FileUtils.rm_rf(hold) if hold
        end

        def run_opencode(directory, project, retrospective_enabled: true, retrospective_active: false)
          environment = { "KOS_RETROSPECTIVE_ENABLED" => retrospective_enabled ? "1" : "0" }
          environment["KOS_RETROSPECTIVE_ACTIVE"] = "1" if retrospective_active
          capture(directory, @executable, "run", "--format", "json", "--dir", project,
            "--agent", "kos-contract-orchestrator", "--model", "kos-contract/kos-contract",
            "--title", "KOS runtime contract", "Run the KOS runtime contract.", chdir: project,
            extra_environment: environment)
        end

        def verify_events(stdout, requests, project)
          events = parse_events(stdout)
          task_events = events.select do |event|
            event["type"] == "tool_use" && event.dig("part", "tool") == "task" &&
              event.dig("part", "state", "status") == "completed"
          end
          raise Incompatible, "Expected two foreground Task completions" unless task_events.length == 2

          verify_exchange(task_events)
          raise Incompatible, "Parent did not finish through JSON events" unless
            events.any? { |event| event["type"] == "text" && event.dig("part", "text") == "contract-complete" }
          raise Incompatible, "Child was not continued exactly once" unless child_requests(requests).length == 4
          raise Incompatible, "Parent and child cwd differ from worktree" unless cwd_verified?(requests, project)
          raise Incompatible, "Child did not load the project skill" unless probe_loaded?(requests)
          delivery = retrospective_tool_delivery(events)
          unless delivery&.fetch("outcome", nil) == "result" && delivery.dig("invocation", "source") == "workflow_step" &&
              delivery.dig("invocation", "timeout_seconds") == 30
            raise Incompatible, "Plugin child_retrospective did not deliver a separate result"
          end
        end

        def verify_launcher_root_contract(directory)
          with_launcher_contract(directory, "launcher", retrospective_result: :valid) do |result|
            if result.fetch(:delivery).empty?
              sessions = result.fetch(:primary_stdout).lines.filter_map do |line|
                JSON.parse(line)["sessionID"]
              rescue JSON::ParserError
                nil
              end.uniq
              raise Incompatible, "Launcher produced no retrospective delivery " \
                "(status=#{result.fetch(:status).exitstatus}, sessions=#{sessions.inspect}, " \
                "processes=#{result.fetch(:environment).length}, " \
                "enabled=#{result.fetch(:environment).first&.fetch('enabled', nil).inspect}, " \
                "config=#{result.fetch(:config_arguments).inspect})"
            end
            delivery = parse_json(result.fetch(:delivery), "launcher retrospective delivery")
            checks = { status: normal_primary_status?(result),
              stdout: result.fetch(:stdout) == result.fetch(:primary_stdout),
              stderr: result.fetch(:stderr) == result.fetch(:primary_stderr), result: delivery["outcome"] == "result",
              separate: [ result.fetch(:stdout), result.fetch(:stderr) ].none? { |stream| stream.include?(result.fetch(:delivery)) },
              routing: launcher_routing_verified?(result, delivery) }
            failures = checks.reject { |_name, passed| passed }.keys
            raise Incompatible, "Launcher root contract failed: #{failures.join(',')}" unless failures.empty?
          end
        end

        def verify_launcher_failure_contract(directory)
          with_launcher_contract(directory, "launcher-failure", retrospective_result: :failure) do |result|
            delivery = parse_json(result.fetch(:delivery), "launcher failure delivery")
            checks = { status: normal_primary_status?(result),
              stdout: result.fetch(:stdout) == result.fetch(:primary_stdout),
              stderr: result.fetch(:stderr) == result.fetch(:primary_stderr),
              outcome: delivery["outcome"] == "no_result", reason: delivery["reason"] == "provider_failure",
              single_delivery: result.fetch(:delivery).lines.one? }
            failures = checks.reject { |_name, passed| passed }.keys
            raise Incompatible, "Launcher provider-failure contract failed: #{failures.join(',')}" unless failures.empty?
          end
        end

        def verify_launcher_timeout_contract(directory)
          with_launcher_contract(directory, "launcher-timeout", retrospective_result: :delayed) do |result|
            delivery = parse_json(result.fetch(:delivery), "launcher timeout delivery")
            checks = { status: normal_primary_status?(result),
              stdout: result.fetch(:stdout) == result.fetch(:primary_stdout),
              stderr: result.fetch(:stderr) == result.fetch(:primary_stderr),
              outcome: delivery["outcome"] == "no_result", reason: delivery["reason"] == "timeout",
              budget: delivery.dig("invocation", "timeout_seconds") == 30,
              no_late_response: result.fetch(:provider).delayed_responses.zero?,
              single_delivery: result.fetch(:delivery).lines.one? }
            failures = checks.reject { |_name, passed| passed }.keys
            raise Incompatible, "Launcher timeout contract failed: #{failures.join(',')}" unless failures.empty?
          end
        end

        def with_launcher_contract(directory, name, retrospective_result:)
          provider = DeterministicProvider.new(root_only: true, retrospective_result: retrospective_result)
          provider.start
          project = prepare_project(directory, name, provider.base_url)
          paths = launcher_fixture_paths(directory, name)
          write_fake_kos(paths.fetch(:kos), paths.fetch(:config_log))
          write_opencode_wrapper(paths)
          result = run_launcher(directory, project, provider, paths)
          provider.stop
          yield result.merge(provider: provider)
        ensure
          restore_permissions(project)
          provider&.stop
        end

        def launcher_fixture_paths(directory, name)
          root = File.join(directory, "#{name}-launcher")
          FileUtils.mkdir_p(root)
          { kos: File.join(root, "kos"), wrapper: File.join(root, "opencode"),
            primary_stdout: File.join(root, "primary.stdout"), primary_stderr: File.join(root, "primary.stderr"),
            environment_log: File.join(root, "environment.jsonl"), config_log: File.join(root, "config.json") }
        end

        def write_fake_kos(path, log)
          body = { "schema_version" => "1", "request_id" => "99999999-9999-4999-8999-999999999999",
            "command" => "runtime_config.get", "data" => { "schema_version" => "1",
              "retrospective_enabled" => true, "lock_version" => 0, "updated_at" => "2026-09-14T09:00:00Z" } }
          File.write(path, <<~RUBY)
            #!#{RbConfig.ruby}
            require "json"
            File.write(#{log.inspect}, JSON.generate(ARGV))
            abort "unexpected runtime configuration command" unless ARGV == %w[runtime-config get --json]
            puts #{JSON.generate(body).inspect}
          RUBY
          File.chmod(0o755, path)
        end

        def write_opencode_wrapper(paths)
          File.write(paths.fetch(:wrapper), <<~RUBY)
            #!#{RbConfig.ruby}
            require "json"
            require "open3"
            retrospective = ARGV.include?("--session")
            version = ARGV == ["--version"]
            secret_keys = %w[KOS_API_TOKEN KOS_API_URL KOS_REPOSITORY_ID GIT_ASKPASS GIT_SSH_COMMAND
              SSH_AGENT_PID SSH_AUTH_SOCK]
            observation = { "retrospective" => retrospective, "arguments" => ARGV,
              "enabled" => ENV["KOS_RETROSPECTIVE_ENABLED"], "active" => ENV["KOS_RETROSPECTIVE_ACTIVE"],
              "secrets" => secret_keys.to_h { |key| [key, ENV[key]] } }
            File.open(#{paths.fetch(:environment_log).inspect}, "a") { |file| file.puts(JSON.generate(observation)) } unless version
            stdout, stderr, status = Open3.capture3(#{@executable.inspect}, *ARGV)
            unless retrospective || version
              File.binwrite(#{paths.fetch(:primary_stdout).inspect}, stdout)
              File.binwrite(#{paths.fetch(:primary_stderr).inspect}, stderr)
            end
            STDOUT.binmode.write(stdout)
            STDERR.binmode.write(stderr)
            exit(retrospective || version ? status.exitstatus : 7)
          RUBY
          File.chmod(0o755, paths.fetch(:wrapper))
        end

        def run_launcher(directory, project, provider, paths)
          delivery = Tempfile.new("kos-retrospective-delivery", directory)
          environment = { "KOS_OPENCODE_EXECUTABLE" => paths.fetch(:wrapper),
            "KOS_EXECUTABLE" => paths.fetch(:kos), "KOS_RETROSPECTIVE_FD" => delivery.fileno.to_s,
            "KOS_API_TOKEN" => "capability-token", "KOS_API_URL" => "http://kos.secret",
            "KOS_REPOSITORY_ID" => "capability-repository", "GIT_ASKPASS" => "capability-askpass",
            "GIT_SSH_COMMAND" => "capability-ssh", "SSH_AGENT_PID" => "1234",
            "SSH_AUTH_SOCK" => "/capability/ssh.sock" }
          stdout, stderr, status = capture(directory, @launcher_executable, "--worktree", project,
            "--model", "kos-contract/kos-contract", "--", "Run launcher contract.", chdir: project,
            extra_environment: environment, file_descriptors: { delivery.fileno => delivery })
          delivery.rewind
          { stdout: stdout, stderr: stderr, status: status, delivery: delivery.read,
            primary_stdout: File.binread(paths.fetch(:primary_stdout)),
            primary_stderr: File.binread(paths.fetch(:primary_stderr)), provider: provider,
            environment: File.readlines(paths.fetch(:environment_log)).map { |line| JSON.parse(line) },
            config_arguments: JSON.parse(File.read(paths.fetch(:config_log))) }
        ensure
          delivery&.close!
        end

        def launcher_routing_verified?(result, delivery)
          environments = result.fetch(:environment)
          invocation = retrospective_invocation(result.fetch(:provider).requests.last)
          primary, retrospective = environments
          result.fetch(:config_arguments) == %w[runtime-config get --json] &&
            environments.length == 2 && primary["retrospective"] == false && retrospective["retrospective"] == true &&
            primary["enabled"] == "1" && retrospective.values_at("enabled", "active") == %w[0 1] &&
            primary.fetch("secrets").values.none?(&:nil?) && retrospective.fetch("secrets").values.all?(&:nil?) &&
            primary.fetch("arguments").include?("kos-orchestrate") &&
            retrospective.fetch("arguments").include?("kos-retrospective") &&
            retrospective.fetch("arguments").each_cons(2).any? { |left, right| left == "--session" && right == delivery["runtime_session_id"] } &&
            invocation&.fetch("session_id", nil) == delivery.dig("invocation", "session_id") &&
            JSON.generate(result.fetch(:provider).requests.last).include?("launcher-primary")
        end

        def normal_primary_status?(result)
          result.fetch(:status).exited? && result.fetch(:status).exitstatus == 7
        end

        def verify_rejected_retrospective(stdout, requests, label)
          events = parse_events(stdout)
          rejected = events.any? do |event|
            event["type"] == "tool_use" && event.dig("part", "tool") == "child_retrospective" &&
              event.dig("part", "state", "status") == "error" &&
              JSON.generate(event.dig("part", "state", "error")).include?("rejected retrospective lifecycle input")
          end
          invoked = requests.any? { |request| retrospective_invocation(request)&.fetch("source", nil) == "workflow_step" }
          raise Incompatible, "Retrospective #{label} suppression failed" unless rejected && !invoked && completed_primary?(events)
        end

        def retrospective_tool_delivery(events)
          event = events.find do |candidate|
            candidate["type"] == "tool_use" && candidate.dig("part", "tool") == "child_retrospective" &&
              candidate.dig("part", "state", "status") == "completed"
          end
          JSON.parse(event.dig("part", "state", "output")) if event
        rescue JSON::ParserError
          nil
        end

        def completed_primary?(events)
          events.any? { |event| event["type"] == "text" && event.dig("part", "text") == "contract-complete" }
        end

        def retrospective_invocation(request)
          string_values(request.fetch("messages")).reverse_each do |value|
            document = JSON.parse(value)
            return document if document.is_a?(Hash) && document["timeout_seconds"] == 30 &&
              %w[orchestrator workflow_step].include?(document["source"])
          rescue JSON::ParserError
            next
          end
          nil
        end

        def verify_exchange(events)
          request = DeterministicProvider::EFFECT_REQUEST
          result = DeterministicProvider::EFFECT_RESULT
          exchange = Transport.new(attempt_id: request.fetch("attempt_id"),
            input_context_digest: request.fetch("input_context_digest"), allowed_operations: [ "fetch" ])
          first = exchange.accept_task_completion(events.first)
          delivery = { "schema_version" => "1", "runtime" => "opencode",
            "child_session_id" => exchange.child_session_id, "effect_result" => result }
          exchange.deliver_effect(delivery, expected_effect_intent_id: result.fetch("effect_intent_id"))
          second = exchange.accept_task_completion(events.last)
          valid = first.fetch("turn") == request && second.fetch("turn") == DeterministicProvider::RESULT_MANIFEST &&
            exchange.state == :completed
          raise Incompatible, "Typed effect exchange did not complete" unless valid
        end

        def parse_events(stdout)
          stdout.lines.map { |line| JSON.parse(line) }
        rescue JSON::ParserError
          raise Incompatible, "OpenCode emitted malformed JSON events"
        end

        def parse_json(value, label)
          JSON.parse(value)
        rescue JSON::ParserError
          raise Incompatible, "OpenCode emitted a malformed #{label}"
        end

        def child_requests(requests)
          requests.select do |request|
            tools = request.fetch("tools", []).filter_map { |definition| definition.dig("function", "name") }
            tools.include?("skill") && !tools.include?("task")
          end
        end

        def cwd_verified?(requests, project)
          grouped = requests.group_by { |request| child_requests([ request ]).empty? ? :parent : :child }
          grouped.keys.sort == %i[child parent] && grouped.values.all? do |session|
            session.any? { |request| tool_outputs(request).any? { |output| output.lines.map(&:strip).include?(project) } }
          end
        end

        def probe_loaded?(requests)
          child_requests(requests).any? do |request|
            tool_outputs(request).any? { |output| output.include?("<skill_content name=\"kos-workflow-step\">") }
          end
        end

        def tool_outputs(request)
          request.fetch("messages").select { |message| message["role"] == "tool" }
            .flat_map { |message| string_values(message["content"]) }
        end

        def string_values(value)
          case value
          when Hash then value.values.flat_map { |item| string_values(item) }
          when Array then value.flat_map { |item| string_values(item) }
          when String then [ value ]
          else []
          end
        end

        def capture(directory, *command, chdir: directory, extra_environment: {}, file_descriptors: {})
          environment = isolated_environment(directory).merge(extra_environment)
          options = { chdir: chdir, unsetenv_others: true, pgroup: true }.merge(file_descriptors)
          Open3.popen3(environment, *command, options) do |stdin, stdout, stderr, wait|
            stdin.close
            out_reader = Thread.new { stdout.read }
            err_reader = Thread.new { stderr.read }
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
            complete = join_before(wait, deadline) && join_before(out_reader, deadline) && join_before(err_reader, deadline)
            terminate(wait, out_reader, err_reader) unless complete
            output = [ out_reader.value, err_reader.value, wait.value ]
            raise Incompatible, "OpenCode command exceeded timeout" unless complete

            output
          end
        end

        def join_before(thread, deadline)
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          remaining.positive? && thread.join(remaining)
        end

        def terminate(wait, *readers)
          Process.kill("TERM", -wait.pid)
          sleep(0.05)
          Process.kill("KILL", -wait.pid)
        rescue Errno::ESRCH
          nil
        ensure
          wait.join
          readers.each(&:join)
        end

        def isolated_environment(directory)
          paths = { "HOME" => File.join(directory, "home"), "XDG_CONFIG_HOME" => File.join(directory, "config"),
            "XDG_DATA_HOME" => File.join(directory, "data"), "XDG_CACHE_HOME" => File.join(directory, "cache"),
            "XDG_STATE_HOME" => File.join(directory, "state") }
          paths.each_value { |path| FileUtils.mkdir_p(path) }
          write_marker(File.join(paths.fetch("XDG_CONFIG_HOME"), "opencode"))
          paths.merge("PATH" => @path, "TMPDIR" => directory, "USER" => "kos-contract",
            "OPENCODE_DISABLE_AUTOUPDATE" => "true", "OPENCODE_DISABLE_DEFAULT_PLUGINS" => "true",
            "OPENCODE_DISABLE_MODELS_FETCH" => "true", "OPENCODE_DISABLE_CLAUDE_CODE" => "true",
            "NO_PROXY" => "127.0.0.1,localhost")
        end

        def write_marker(directory)
          FileUtils.mkdir_p(File.join(directory, "node_modules"))
          dependency = { "@opencode-ai/plugin" => VERSION }
          File.write(File.join(directory, "package.json"), JSON.generate("dependencies" => dependency))
          lock = { "name" => "kos-runtime-contract", "lockfileVersion" => 3,
            "packages" => { "" => { "dependencies" => dependency } } }
          File.write(File.join(directory, "package-lock.json"), JSON.generate(lock))
        end

        def restore_permissions(project)
          FileUtils.chmod_R(0o755, File.join(project, ".opencode")) if project && File.exist?(File.join(project, ".opencode"))
        end
      end
    end
  end
end
