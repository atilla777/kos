require "digest"
require "fileutils"
require "json"
require "open3"
require "timeout"
require "tmpdir"

require_relative "deterministic_provider"
require_relative "transport"

module Kos
  module Runtime
    module OpenCode
      class CapabilityVerifier
        class Incompatible < StandardError; end

        VERSION = "1.18.26"
        CAPABILITIES = %w[
          skill_discovery non_interactive_json subagent_launch worktree_cwd typed_effect_round_trip
        ].freeze
        INSTALLED_SKILLS = %w[
          kos-cli kos-initialize kos-orchestrate kos-repository kos-retrospective kos-workflow-step
        ].freeze
        INSTALLED_AGENTS = %w[kos-orchestrate kos-workflow-step].freeze
        AGENT_CONTRACTS = {
          "kos-orchestrate" => {
            "mode" => "primary", "tools" => { "invalid" => false, "bash" => true, "skill" => true,
              "task" => true },
            "permissions" => [ [ "*", "*", "deny" ], [ "bash", "*", "deny" ],
              [ "bash", "kos *", "allow" ], [ "bash", "kos-repository *", "allow" ],
              [ "skill", "*", "deny" ], [ "skill", "kos-cli", "allow" ],
              [ "skill", "kos-orchestrate", "allow" ], [ "skill", "kos-repository", "allow" ],
              [ "task", "*", "deny" ], [ "task", "kos-workflow-step", "allow" ] ]
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

        def self.expected_report
          { "schema_version" => "1", "runtime" => "opencode", "runtime_version" => VERSION,
            "compatible" => true, "observations" => CAPABILITIES.to_h do |capability|
              [ capability, { "outcome" => "passed", "message" => "Verified by isolated executable contract" } ]
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

        def initialize(executable:, staged_opencode:, path: ENV.fetch("PATH", ""), timeout: 30)
          @executable = executable
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
            verify_guard_rejection(directory)
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
          tool_mismatches = contract.fetch("tools").reject { |tool, allowed| tools[tool] == allowed }
          failures << "tools(#{tool_mismatches.keys.join(',')})" unless tool_mismatches.empty?
          failures << "permissions" unless contract.fetch("permissions").all? do |permission, pattern, action|
            effective_permission(permissions, permission, pattern) == action
          end
          failures << "unexpected authority" unless unexpected_authority(permissions, contract).empty?
          raise Incompatible, "Installed #{name} agent violates its restrictive #{failures.join('/')} contract" unless
            failures.empty?
        rescue KeyError, NoMethodError
          raise Incompatible, "Installed #{name} agent is malformed"
        end

        def effective_permission(entries, permission, pattern)
          entry = entries.reverse.find do |candidate|
            candidate["permission"] == permission && candidate["pattern"] == pattern
          end
          entry&.fetch("action", nil)
        end

        def unexpected_authority(entries, contract)
          expected_allows = contract.fetch("permissions").select { |_permission, _pattern, action| action == "allow" }
          effective = entries.reverse.uniq { |entry| [ entry["permission"], entry["pattern"] ] }
          effective.select do |entry|
            %w[* bash edit skill task].include?(entry["permission"]) && entry["action"] == "allow" &&
              !expected_allows.include?([ entry["permission"], entry["pattern"], entry["action"] ])
          end
        end

        def verify_positive_contract(directory)
          provider = DeterministicProvider.new
          provider.start
          project = prepare_project(directory, "positive", provider.base_url)
          verify_discovery(directory, project)
          stdout, stderr, status = run_opencode(directory, project)
          raise Incompatible, "OpenCode non-interactive run failed" unless status.success?

          verify_events(stdout, provider.requests, project)
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

        def prepare_project(directory, name, base_url)
          project = File.join(directory, "#{name}-worktree")
          FileUtils.mkdir_p([ File.join(project, "nested"), File.join(project, ".opencode") ])
          FileUtils.cp_r("#{@staged_opencode}/.", File.join(project, ".opencode"))
          write_probe(project)
          write_marker(File.join(project, ".opencode"))
          write_config(project, base_url)
          _stdout, _stderr, status = capture(directory, "git", "init", "--quiet", project)
          raise Incompatible, "Capability worktree initialization failed" unless status.success?

          FileUtils.chmod_R(0o555, File.join(project, ".opencode"))
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
          Dir.children(File.dirname(skill)).reject { |entry| entry == "kos-contract-probe" }.each do |entry|
            FileUtils.rm_rf(File.join(File.dirname(skill), entry))
          end
          agents = File.join(project, ".opencode/agents")
          FileUtils.mkdir_p(agents)
          File.write(File.join(agents, "kos-contract-orchestrator.md"), orchestrator_agent)
          File.write(File.join(agents, "kos-contract-step.md"), step_agent)
        end

        def orchestrator_agent
          <<~MARKDOWN
            ---
            description: Runs the isolated KOS OpenCode capability contract.
            mode: primary
            permission:
              "*": deny
              bash: { "*": deny, "pwd": allow }
              task: { "*": deny, "kos-contract-step": allow }
            ---
            KOS_CONTRACT_PARENT
            Follow the deterministic provider tool calls exactly.
          MARKDOWN
        end

        def step_agent
          <<~MARKDOWN
            ---
            description: Runs the isolated KOS capability child.
            mode: subagent
            permission:
              "*": deny
              bash: { "*": deny, "pwd": allow }
              skill: { "*": deny, "kos-contract-probe": allow }
              task: deny
            ---
            KOS_CONTRACT_CHILD
            Return exactly the requested JSON document without prose.
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
          stdout, = capture(directory, @executable, "debug", "skill", chdir: File.join(project, "nested"))
          skill = parse_json(stdout, "probe skill report").find { |candidate| candidate["name"] == "kos-contract-probe" }
          expected = File.join(project, ".opencode/skills/kos-contract-probe/SKILL.md")
          raise Incompatible, "Project skill was not discovered from nested cwd" unless skill&.fetch("location") == expected
        end

        def run_opencode(directory, project)
          capture(directory, @executable, "run", "--format", "json", "--dir", project,
            "--agent", "kos-contract-orchestrator", "--model", "kos-contract/kos-contract",
            "--title", "KOS runtime contract", "Run the KOS runtime contract.", chdir: project)
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
          requests.select { |request| JSON.generate(request.fetch("messages")).include?("KOS_CONTRACT_CHILD") }
        end

        def cwd_verified?(requests, project)
          grouped = requests.group_by { |request| child_requests([ request ]).empty? ? :parent : :child }
          grouped.keys.sort == %i[child parent] && grouped.values.all? do |session|
            session.any? { |request| tool_outputs(request).any? { |output| output.lines.map(&:strip).include?(project) } }
          end
        end

        def probe_loaded?(requests)
          child_requests(requests).any? do |request|
            tool_outputs(request).any? { |output| output.include?("<skill_content name=\"kos-contract-probe\">") }
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

        def capture(directory, *command, chdir: directory)
          environment = isolated_environment(directory)
          Open3.popen3(environment, *command, chdir: chdir, unsetenv_others: true, pgroup: true) do |stdin, stdout, stderr, wait|
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
