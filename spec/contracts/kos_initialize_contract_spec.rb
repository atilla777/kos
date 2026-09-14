require "json"
require "json_schemer"
require "yaml"
require "spec_helper"
require_relative "../../lib/kos/version"

module KosInitializeContract
  ROOT = File.expand_path("../..", __dir__)
  SCHEMA_PATH = File.join(ROOT, "schemas/installation/v1/installer.json")
  SKILL_PATH = File.join(ROOT, "skills/kos-initialize/SKILL.md")

  module_function

  def schema
    @schema ||= JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))
  end

  def request
    {
      "schema_version" => "1", "task_prefix" => "KOS", "trusted_remote" => "origin",
      "base_ref" => "refs/heads/main", "registration_idempotency_key" => "initialize-1",
      "runtime" => { "target" => "opencode", "version" => "1.18.26" }
    }
  end

  def schema_contract_results
    document = JSON.parse(File.read(SCHEMA_PATH))
    definitions = %w[request plan apply_result manifest failure]
    [ document.fetch("$schema") == "https://json-schema.org/draft/2020-12/schema",
      definitions.all? { |definition| schema.ref("#/$defs/#{definition}") },
      schema.ref("#/$defs/request").valid?(request),
      !schema.ref("#/$defs/request").valid?(request.merge("unexpected" => true)),
      !schema.ref("#/$defs/request").valid?(request.merge(
        "runtime" => { "target" => "opencode", "version" => "1.18.27" })) ]
  end

  def skill_contract_results
    content = File.read(SKILL_PATH)
    frontmatter = YAML.safe_load(content.match(/\A---\n(.*?)\n---\n/m)[1])
    [ frontmatter.fetch("name") == "kos-initialize",
      %w[exact\ canonical\ Git\ common\ directory --approved-plan --force].all? { |text| content.include?(text) },
      content.include?("does not provide or claim graceful-end invocation"),
      Dir[File.join(ROOT, "skills/*/SKILL.md")].length == 6 ]
  end

  def support_contract_results
    orchestrator = File.read(File.join(ROOT, "runtime/opencode/agents/kos-orchestrate.md"))
    step = File.read(File.join(ROOT, "runtime/opencode/agents/kos-workflow-step.md"))
    guard = File.read(File.join(ROOT, "runtime/opencode/plugins/kos-session-guard.js"))
    [ orchestrator.include?('"*": deny') && orchestrator.include?('"kos-workflow-step": allow'),
      step.include?('"git *": deny') && step.include?('"kos *": deny') && step.include?("task: deny"),
      guard.include?("unretained child session") && guard.include?("child session rebinding") ]
  end
end

RSpec.describe KosInitializeContract do
  it "defines valid closed request, plan, result, manifest, and failure schemas" do
    expect(described_class.schema_contract_results).to all(be_truthy)
  end

  it "defines the canonical sixth skill and explicit approval boundaries" do
    expect(described_class.skill_contract_results).to all(be_truthy)
  end

  it "ships restrictive production OpenCode support sources" do
    expect(described_class.support_contract_results).to all(be_truthy)
  end

  it "exposes the release through Zeitwerk-compatible version constants" do
    expect([ Kos::Version::STRING, Kos::VERSION ]).to eq(%w[0.1.0 0.1.0])
  end
end
