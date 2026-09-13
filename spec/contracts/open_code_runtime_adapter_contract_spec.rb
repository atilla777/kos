require "fileutils"
require "json"
require "json_schemer"
require "open3"
require "timeout"
require "tmpdir"
require "uri"
require "spec_helper"
require_relative "../support/open_code_fake_provider"
require_relative "../../lib/kos/runtime/open_code/transport"

module OpenCodeRuntimeAdapterContract
  ROOT = File.expand_path("../..", __dir__)
  FIXTURE = File.expand_path("../fixtures/runtime/opencode/project", __dir__)
  RUNTIME_SCHEMA_PATH = File.expand_path("../../schemas/runtime/v1/opencode.json", __dir__)
  CLI_SCHEMA_DIRECTORY = File.expand_path("../../schemas/cli/v1", __dir__)

  module_function

  def schema
    @schema ||= begin
      runtime = JSON.parse(File.read(RUNTIME_SCHEMA_PATH))
      schemas = Dir[File.join(CLI_SCHEMA_DIRECTORY, "*.json")].to_h do |path|
        document = JSON.parse(File.read(path))
        [ URI(document.fetch("$id")), document ]
      end
      JSONSchemer.schema(runtime, ref_resolver: schemas.to_proc)
    end
  end

  def definition(name)
    schema.ref("#/$defs/#{name}")
  end

  def completion(child_session_id, turn)
    { "schema_version" => "1", "runtime" => "opencode",
      "child_session_id" => child_session_id, "turn" => turn }
  end
end

RSpec.describe OpenCodeRuntimeAdapterContract do
  let(:effect_request) { OpenCodeFakeProvider::EFFECT_REQUEST }
  let(:effect_result) { OpenCodeFakeProvider::EFFECT_RESULT }
  let(:result_manifest) { OpenCodeFakeProvider::RESULT_MANIFEST }
  let(:child_session_id) { "ses_contract_child" }

  it "defines closed capability, child turn, and effect delivery documents" do
    expect(schema_contract_results).to all(be(true))
  end

  it "accepts a valid effect exchange and final manifest in order" do
    expect(valid_exchange_result)
      .to eq([ effect_request, result_manifest, :completed ])
  end

  it "delivers a schema-valid effect failure without success-only target fields" do
    expect(failure_exchange_state).to eq(:awaiting_turn)
  end

  it "rejects malformed or mixed child text" do
    expect(raw_text_rejections).to all(be(true))
  end

  it "rejects invalid wrappers, sessions, identities, digests, operations, and ordering" do
    expect(invalid_exchange_messages).to eq(invalid_exchange_expectations)
  end

  it "passes the real OpenCode 1.18.26 adapter round trip" do
    expect(run_runtime_contract).to eq([])
  end

  def runtime_definition(name)
    described_class.definition(name)
  end

  def schema_contract_results
    report = capability_report
    completion = described_class.completion(child_session_id, effect_request)
    delivery = effect_delivery
    [ runtime_definition("capability_report").valid?(report),
      runtime_definition("workflow_step_completion").valid?(completion),
      runtime_definition("workflow_step_completion").valid?(described_class.completion(child_session_id, result_manifest)),
      runtime_definition("effect_delivery").valid?(delivery),
      !runtime_definition("workflow_step_completion").valid?(completion.merge("prose" => "trust me")),
      !runtime_definition("workflow_step_completion").valid?(described_class.completion(child_session_id, "not JSON")),
      !runtime_definition("effect_delivery").valid?(delivery.merge("prompt" => "rewrite the result")),
      !runtime_definition("capability_report").valid?(report.merge("runtime_version" => "1.18.27")),
      !runtime_definition("capability_report").valid?(failed_compatible_report),
      !runtime_definition("capability_report").valid?(report.merge("compatible" => false)) ]
  end

  def valid_exchange_result
    exchange = new_exchange
    first = exchange.accept_task_completion(task_event(child_session_id, JSON.pretty_generate(effect_request)))
    deliver(exchange, effect_delivery)
    second = exchange.accept_task_completion(task_event(child_session_id, JSON.generate(result_manifest)))
    [ first.fetch("turn"), second.fetch("turn"), exchange.state ]
  end

  def failure_exchange_state
    exchange = prepared_exchange
    failure = effect_result.merge("result" => { "outcome" => "failed", "operation" => "fetch",
      "error" => { "category" => "transient", "code" => "fetch_failed",
        "message" => "Fetch failed", "retryable" => true } })
    deliver(exchange, effect_delivery.merge("effect_result" => failure))
    exchange.state
  end

  def invalid_exchange_expectations
    [ "invalid OpenCode task completion wrapper",
      "task wrapper and metadata identify different child sessions",
      "task completion came from another child session", "turn belongs to another attempt",
      "turn has a different input context digest", "effect operation is not allowed",
      "effect result targets another child session", "effect result belongs to another intent",
      "effect result has a different request digest", "effect result operation does not match its request",
      "effect result targets different operation parameters", "final manifest arrived before the pending effect result",
      "no effect result is expected" ]
  end

  def raw_text_rejections
    texts = [ "{", "#{JSON.generate(effect_request)} trailing prose", "#{JSON.generate(effect_request)}\n{}" ]
    texts.map do |text|
      new_exchange.accept_task_completion(task_event(child_session_id, text))
      false
    rescue Kos::Runtime::OpenCode::Transport::InvalidExchange
      true
    end
  end

  def capability_report
    capabilities = %w[
      skill_discovery non_interactive_json subagent_launch worktree_cwd typed_effect_round_trip
    ]
    { "schema_version" => "1", "runtime" => "opencode", "runtime_version" => "1.18.26",
      "compatible" => true,
      "observations" => capabilities.to_h do |capability|
        [ capability, { "outcome" => "passed", "message" => "Verified by isolated contract" } ]
      end }
  end

  def failed_compatible_report
    capability_report.tap do |report|
      report["observations"]["subagent_launch"] = { "outcome" => "failed", "message" => "Not available" }
    end
  end

  def new_exchange(allowed_operations: [ "fetch" ])
    Kos::Runtime::OpenCode::Transport.new(attempt_id: effect_request.fetch("attempt_id"),
      input_context_digest: effect_request.fetch("input_context_digest"), allowed_operations: allowed_operations)
  end

  def effect_delivery
    { "schema_version" => "1", "runtime" => "opencode",
      "child_session_id" => child_session_id, "effect_result" => effect_result }
  end

  def task_event(wrapper_session_id, turn, metadata_session_id: wrapper_session_id)
    output = "<task id=\"#{wrapper_session_id}\" state=\"completed\">\n<task_result>\n#{turn}\n</task_result>\n</task>"
    { "type" => "tool_use", "part" => { "tool" => "task",
      "state" => { "status" => "completed", "output" => output,
        "metadata" => { "sessionId" => metadata_session_id } } } }
  end

  def invalid_exchange_messages
    cases = invalid_exchange_cases
    cases.map do |exchange, operation|
      operation.call(exchange)
      "accepted"
    rescue Kos::Runtime::OpenCode::Transport::InvalidExchange => error
      error.message
    end
  end

  def invalid_exchange_cases
    [ invalid_wrapper_case, wrapper_mismatch_case, changed_child_case, changed_attempt_case,
      changed_context_case, disallowed_effect_case, delivery_child_case, delivery_intent_case,
      delivery_digest_case, delivery_operation_case, delivery_parameters_case,
      final_before_delivery_case, unexpected_delivery_case ]
  end

  def invalid_wrapper_case
    [ new_exchange, ->(exchange) { exchange.accept_task_completion(task_event(child_session_id, "{}").tap {
      |event| event.dig("part", "state")["output"] = "not a task wrapper" }) } ]
  end

  def wrapper_mismatch_case
    [ new_exchange, ->(exchange) { exchange.accept_task_completion(
      task_event(child_session_id, JSON.generate(effect_request), metadata_session_id: "ses_other")) } ]
  end

  def changed_child_case
    exchange = new_exchange
    exchange.accept_task_completion(task_event(child_session_id, JSON.generate(effect_request)))
    deliver(exchange, effect_delivery)
    [ exchange, ->(value) { value.accept_task_completion(task_event("ses_other", JSON.generate(result_manifest))) } ]
  end

  def changed_attempt_case
    turn = effect_request.merge("attempt_id" => "99999999-9999-4999-8999-999999999999")
    [ new_exchange, ->(exchange) { exchange.accept_task_completion(task_event(child_session_id, JSON.generate(turn))) } ]
  end

  def changed_context_case
    turn = effect_request.merge("input_context_digest" => "sha256:#{'f' * 64}")
    [ new_exchange, ->(exchange) { exchange.accept_task_completion(task_event(child_session_id, JSON.generate(turn))) } ]
  end

  def disallowed_effect_case
    [ new_exchange(allowed_operations: []),
      ->(exchange) { exchange.accept_task_completion(task_event(child_session_id, JSON.generate(effect_request))) } ]
  end

  def prepared_exchange
    new_exchange.tap { |exchange| exchange.accept_task_completion(task_event(child_session_id, JSON.generate(effect_request))) }
  end

  def delivery_child_case
    delivery = effect_delivery.merge("child_session_id" => "ses_other")
    [ prepared_exchange, ->(exchange) { deliver(exchange, delivery) } ]
  end

  def delivery_intent_case
    [ prepared_exchange, ->(exchange) { deliver(exchange, effect_delivery,
      expected_intent: "99999999-9999-4999-8999-999999999999") } ]
  end

  def delivery_digest_case
    result = effect_result.merge("effect_request_digest" => "sha256:#{'f' * 64}")
    [ prepared_exchange, ->(exchange) { deliver(exchange, effect_delivery.merge("effect_result" => result)) } ]
  end

  def delivery_operation_case
    commit = { "outcome" => "succeeded", "operation" => "commit", "commit_sha" => "1" * 40,
      "evidence_digest" => "sha256:#{'c' * 64}" }
    result = effect_result.merge("result" => commit)
    [ prepared_exchange, ->(exchange) { deliver(exchange, effect_delivery.merge("effect_result" => result)) } ]
  end

  def delivery_parameters_case
    result = effect_result.merge("result" => effect_result.fetch("result").merge("remote" => "other"))
    [ prepared_exchange, ->(exchange) { deliver(exchange, effect_delivery.merge("effect_result" => result)) } ]
  end

  def final_before_delivery_case
    [ prepared_exchange,
      ->(exchange) { exchange.accept_task_completion(task_event(child_session_id, JSON.generate(result_manifest))) } ]
  end

  def unexpected_delivery_case
    [ new_exchange, ->(exchange) { deliver(exchange, effect_delivery) } ]
  end

  def deliver(exchange, delivery, expected_intent: effect_result.fetch("effect_intent_id"))
    exchange.deliver_effect(delivery, expected_effect_intent_id: expected_intent)
  end

  def run_runtime_contract
    discovery = Dir.mktmpdir("kos-opencode-discovery-") { |directory| verify_skill_discovery(directory) }
    valid = Dir.mktmpdir("kos-opencode-contract-") { |directory| execute_runtime_contract(directory) }
    rejected = Dir.mktmpdir("kos-opencode-guard-") { |directory| verify_session_guard(directory) }
    discovery + valid + rejected
  rescue StandardError => error
    [ "#{error.class}: #{error.message}" ]
  end

  def execute_runtime_contract(directory)
    project = prepare_project(directory)
    provider = OpenCodeFakeProvider.new
    provider.start
    write_config(project, provider.base_url)
    runtime_contract_errors(directory, project, provider)
  ensure
    FileUtils.chmod_R(0755, File.join(project, ".opencode")) if project && File.exist?(File.join(project, ".opencode"))
    provider&.stop
  end

  def verify_session_guard(directory)
    project = prepare_project(directory)
    provider = OpenCodeFakeProvider.new(invalid_continuation: :omit)
    provider.start
    write_config(project, provider.base_url)
    protect_runtime_config(project)
    stdout, stderr, _status = run_opencode(directory, project)
    return [] if session_guard_rejected?(stdout)

    [ "session guard accepted an unretained child: #{stderr}" ]
  ensure
    FileUtils.chmod_R(0755, File.join(project, ".opencode")) if project && File.exist?(File.join(project, ".opencode"))
    provider&.stop
  end

  def session_guard_rejected?(stdout)
    stdout.lines.map { |line| JSON.parse(line) }.any? do |event|
      event["type"] == "tool_use" && event.dig("part", "tool") == "task" &&
        event.dig("part", "state", "status") == "error" &&
        event.dig("part", "state", "error").include?("unretained child session")
    end
  end

  def runtime_contract_errors(directory, project, provider)
    errors = []
    errors << "unexpected runtime version" unless runtime_version(directory) == "1.18.26"
    protect_runtime_config(project)
    stdout, stderr, status = run_opencode(directory, project)
    errors << "OpenCode failed: #{stderr}" unless status.success?
    return errors unless status.success?

    verify_runtime_events(stdout, provider.requests, project, errors)
  end

  def verify_skill_discovery(directory)
    project = prepare_project(directory)
    FileUtils.rm_r(File.join(project, ".opencode/plugins"))
    skill_discovered?(directory, project) ? [] : [ "fixture skill was not discovered" ]
  end

  def skill_discovered?(directory, project)
    skill = discovered_skill(directory, project)
    skill && skill["name"] == "kos-contract-probe" &&
      skill["location"] == File.join(project, ".opencode/skills/kos-contract-probe/SKILL.md")
  end

  def verify_runtime_events(stdout, requests, project, errors)
    events = stdout.lines.map { |line| JSON.parse(line) }
    task_events = events.filter_map { |event| completed_task_event(event) }
    errors << "expected two completed Task calls" unless task_events.length == 2
    return errors unless task_events.length == 2

    verify_runtime_exchange(task_events, errors)
    errors << "parent did not finish non-interactively" unless final_text?(events)
    errors << "child was not resumed exactly once" unless requests.count { |request| child_request?(request) } == 4
    errors << "parent and child did not observe the worktree cwd" unless cwd_observed_by_both_sessions?(requests, project)
    errors << "child did not load the fixture skill" unless child_loaded_skill?(requests)
    errors
  end

  def verify_runtime_exchange(task_events, errors)
    exchange = new_exchange
    first = exchange.accept_task_completion(task_events.first)
    delivery = effect_delivery.merge("child_session_id" => exchange.child_session_id)
    deliver(exchange, delivery)
    second = exchange.accept_task_completion(task_events.last)
    errors << "child returned an unexpected effect request" unless first.fetch("turn") == effect_request
    errors << "child returned an unexpected final manifest" unless second.fetch("turn") == result_manifest
    errors << "exchange did not complete" unless exchange.state == :completed
  rescue Kos::Runtime::OpenCode::Transport::InvalidExchange => error
    errors << error.message
  end

  def prepare_project(directory)
    project = File.join(directory, "task-worktree")
    FileUtils.mkdir_p(project)
    FileUtils.cp_r("#{OpenCodeRuntimeAdapterContract::FIXTURE}/.", project)
    prepare_plugin_dependency_marker(project)
    _stdout, stderr, status = Open3.capture3("git", "init", "--quiet", project)
    raise stderr unless status.success?

    project
  end

  def prepare_plugin_dependency_marker(project)
    prepare_npm_marker(File.join(project, ".opencode"))
  end

  def prepare_npm_marker(config)
    FileUtils.mkdir_p(File.join(config, "node_modules"))
    dependency = { "@opencode-ai/plugin" => "1.18.26" }
    File.write(File.join(config, "package.json"), JSON.generate("dependencies" => dependency))
    lock = { "name" => "kos-runtime-contract", "lockfileVersion" => 3, "packages" => {
      "" => { "dependencies" => dependency } } }
    File.write(File.join(config, "package-lock.json"), JSON.generate(lock))
  end

  def protect_runtime_config(project)
    FileUtils.chmod_R(0555, File.join(project, ".opencode"))
  end

  def write_config(project, base_url)
    config = {
      "$schema" => "https://opencode.ai/config.json",
      "model" => "kos-contract/kos-contract",
      "small_model" => "kos-contract/kos-contract",
      "share" => "disabled",
      "autoupdate" => false,
      "provider" => {
        "kos-contract" => {
          "npm" => "@ai-sdk/openai-compatible",
          "name" => "KOS Contract",
          "options" => { "baseURL" => base_url, "apiKey" => "contract-only" },
          "models" => { "kos-contract" => { "name" => "KOS Contract" } }
        }
      }
    }
    File.write(File.join(project, "opencode.json"), JSON.pretty_generate(config))
  end

  def runtime_version(directory)
    stdout, stderr, status = capture(directory, "opencode", "--version")
    raise stderr unless status.success?

    stdout.strip
  end

  def discovered_skill(directory, project)
    stdout, stderr, status = capture(directory, "opencode", "debug", "skill", chdir: File.join(project, "nested"))
    raise stderr unless status.success?

    JSON.parse(stdout).find { |skill| skill.fetch("name") == "kos-contract-probe" }
  end

  def run_opencode(directory, project)
    capture(directory, "opencode", "run", "--format", "json", "--dir", project,
      "--agent", "kos-contract-orchestrator", "--model", "kos-contract/kos-contract",
      "--title", "KOS runtime contract", "--print-logs", "--log-level", "DEBUG",
      "Run the KOS runtime contract.", timeout: 30)
  end

  def capture(directory, *command, chdir: OpenCodeRuntimeAdapterContract::ROOT, timeout: 30)
    environment = isolated_environment(directory)
    Open3.popen3(environment, *command, chdir: chdir, unsetenv_others: true, pgroup: true) do |stdin, stdout, stderr, wait|
      stdin.close
      out_reader = Thread.new { stdout.read }
      err_reader = Thread.new { stderr.read }
      timed_out = !wait.join(timeout)
      terminate_process(wait) if timed_out
      output = [ out_reader.value, err_reader.value, wait.value ]
      raise Timeout::Error, "#{command.join(' ')} exceeded #{timeout} seconds: #{output[1]}" if timed_out

      output
    end
  end

  def terminate_process(wait)
    Process.kill("TERM", -wait.pid)
    Process.kill("KILL", -wait.pid) unless wait.join(2)
    wait.join
  rescue Errno::ESRCH
    nil
  end

  def isolated_environment(directory)
    home = File.join(directory, "home")
    paths = {
      "HOME" => home,
      "XDG_CONFIG_HOME" => File.join(directory, "config"),
      "XDG_DATA_HOME" => File.join(directory, "data"),
      "XDG_CACHE_HOME" => File.join(directory, "cache"),
      "XDG_STATE_HOME" => File.join(directory, "state")
    }
    paths.each_value { |path| FileUtils.mkdir_p(path) }
    prepare_npm_marker(File.join(paths.fetch("XDG_CONFIG_HOME"), "opencode"))
    paths.merge(
      "PATH" => ENV.fetch("PATH"),
      "TMPDIR" => directory,
      "USER" => "kos-contract",
      "OPENCODE_DISABLE_AUTOUPDATE" => "true",
      "OPENCODE_DISABLE_DEFAULT_PLUGINS" => "true",
      "OPENCODE_DISABLE_MODELS_FETCH" => "true",
      "OPENCODE_DISABLE_CLAUDE_CODE" => "true",
      "NO_PROXY" => "127.0.0.1,localhost"
    )
  end

  def completed_task_event(event)
    return unless event["type"] == "tool_use"
    return unless event.dig("part", "tool") == "task"
    return unless event.dig("part", "state", "status") == "completed"

    event
  end

  def child_request?(request)
    JSON.generate(request.fetch("messages")).include?("KOS_CONTRACT_CHILD")
  end

  def cwd_observed_by_both_sessions?(requests, project)
    grouped = requests.group_by { |request| child_request?(request) ? :child : :parent }
    grouped.values.all? do |session_requests|
      session_requests.any? do |request|
        tool_outputs(request).any? { |output| output.lines.map(&:strip).include?(project) }
      end
    end
  end

  def child_loaded_skill?(requests)
    requests.select { |request| child_request?(request) }.any? do |request|
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

  def final_text?(events)
    events.any? { |event| event["type"] == "text" && event.dig("part", "text") == "contract-complete" }
  end
end
