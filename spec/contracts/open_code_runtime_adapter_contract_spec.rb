require "fileutils"
require "json"
require "json_schemer"
require "tmpdir"
require "uri"
require "spec_helper"
require_relative "../../lib/kos/runtime/open_code/capability_verifier"
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
  let(:effect_request) { Kos::Runtime::OpenCode::DeterministicProvider::EFFECT_REQUEST }
  let(:effect_result) { Kos::Runtime::OpenCode::DeterministicProvider::EFFECT_RESULT }
  let(:result_manifest) { Kos::Runtime::OpenCode::DeterministicProvider::RESULT_MANIFEST }
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
    Dir.mktmpdir("kos-opencode-contract-") do |directory|
      staged = File.join(directory, ".opencode")
      FileUtils.mkdir_p(staged)
      FileUtils.cp_r(File.join(described_class::ROOT, "skills"), File.join(staged, "skills"))
      %w[agents plugins].each do |member|
        FileUtils.cp_r(File.join(described_class::ROOT, "runtime/opencode", member), File.join(staged, member))
      end
      verifier = Kos::Runtime::OpenCode::CapabilityVerifier.new(executable: "opencode", staged_opencode: staged)
      verifier.call == Kos::Runtime::OpenCode::CapabilityVerifier.expected_report ? [] : [ "unexpected report" ]
    end
  rescue StandardError => error
    [ "#{error.class}: #{error.message}" ]
  end
end
