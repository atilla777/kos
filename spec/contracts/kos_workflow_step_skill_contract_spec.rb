require "fileutils"
require "json"
require "open3"
require "timeout"
require "tmpdir"
require "yaml"
require "spec_helper"

module KosWorkflowStepSkillContract
  ROOT = File.expand_path("../..", __dir__)
  SKILL_PATH = File.join(ROOT, "skills/kos-workflow-step/SKILL.md")
  WORKFLOW_SCHEMA_PATH = File.join(ROOT, "schemas/cli/v1/workflow.json")
  ARTIFACT_SCHEMA_PATH = File.join(ROOT, "schemas/cli/v1/artifacts.json")
  EXPECTED_OPERATIONS = %w[worktree_remove commit fetch rebase push].freeze
  EXPECTED_RESULT_BRANCHES = %w[
    worktree_effect_result commit_effect_result fetch_effect_result rebase_effect_result push_effect_result
    effect_failure_result
  ].freeze
  EXPECTED_OUTCOMES = %w[succeeded failed needs_human].freeze
  EXPECTED_ARTIFACT_STATES = {
    "document" => %w[produced],
    "candidate" => %w[produced],
    "test" => %w[passed failed],
    "review" => %w[approved changes_requested],
    "publication" => %w[published]
  }.freeze
  REQUIRED_GUIDANCE = {
    "Authority Boundary" => [
      "Do not claim, renew, reconcile, complete, fail, or otherwise mutate an attempt",
      "Never invoke `kos`", "Never invoke `kos-repository` or run any Git command",
      "Do not launch or continue another subagent", "Do not submit a result manifest",
      "None may grant authority forbidden by this skill"
    ],
    "Accept One Context" => [
      "complete document already validated", "finalized by the orchestrator", "`schema_version`",
      "RFC 8785 canonical JSON serialization", "retain the exact `attempt_id` and `input_context_digest`",
      "pinned `instruction`", "`artifact_templates`", "`required_artifacts`", "`allowed_repository_effects`",
      "never repair, normalize, or guess", "work only under its exact `path`", "Reject path traversal, symlink escape"
    ],
    "Request An Effect" => [
      "only way to request a Git mutation", "appears exactly in `allowed_repository_effects`",
      "no routing, child-session, prose, or speculative fields", "more than one effect request pending",
      "stop the turn"
    ],
    "Accept An Effect Result" => [
      "delivered by the orchestrator to this same child session", "RFC 8785 canonical JSON serialization",
      "both equal the context `attempt_id`", "matched `effect_intent_id` to the exact durable intent",
      "equals the pending operation", "wherever those fields overlap", "do not rewrite it as success",
      "request another allowed effect only after the pending result is fully validated and consumed",
      "`unknown` result leaves its durable effect unresolved", "Do not return another effect request",
      "truthful schema-valid `failed` manifest", "enter the effect's authoritative recovery protocol"
    ],
    "Return One Turn" => [
      "exactly one JSON document and no prose", "`schema_version: \"1\"`",
      "exact context `attempt_id` and `input_context_digest`", "no pending effect request",
      "must not rewrite its outcome or evidence"
    ]
  }.freeze

  module_function

  def content
    @content ||= File.read(SKILL_PATH)
  end

  def frontmatter
    YAML.safe_load(content.match(/\A---\n(.*?)\n---\n/m)[1])
  end

  def workflow_schema
    @workflow_schema ||= JSON.parse(File.read(WORKFLOW_SCHEMA_PATH))
  end

  def artifact_schema
    @artifact_schema ||= JSON.parse(File.read(ARTIFACT_SCHEMA_PATH))
  end

  def schema_operations
    references("requested_effect").map { |reference| reference.delete_suffix("_effect") }
  end

  def documented_operations
    table_entries(section("Request An Effect", "Accept An Effect Result")).map(&:first)
  end

  def operation_inventory_errors
    request_operations = schema_operations
    allowlist_operations = workflow_schema.dig("$defs", "context", "properties", "allowed_repository_effects", "items", "enum")
    failure_operations = workflow_schema.dig("$defs", "effect_failure_result", "properties", "operation", "enum")
    result_branches = references_from("effect_result", "properties", "result", "oneOf")
    result_operations = result_branches.filter_map do |reference|
      workflow_schema.dig("$defs", reference, "properties", "operation", "const")
    end
    inventories = [ request_operations, allowlist_operations, failure_operations, result_operations ]
    errors = inventories.each_index.reject { |index| same_inventory?(inventories[index], EXPECTED_OPERATIONS) }
    errors << :result_branches unless same_inventory?(result_branches, EXPECTED_RESULT_BRANCHES)
    errors << :documentation unless documented_operations == EXPECTED_OPERATIONS
    errors
  end

  def schema_outcomes
    workflow_schema.dig("$defs", "result_manifest", "properties", "outcome", "enum")
  end

  def documented_outcomes
    final_manifest = section("Return One Turn", nil)
    final_manifest.match(/uses exactly one of (.*?);/m)[1].scan(/`([^`]+)`/).flatten
  end

  def schema_artifact_states
    constraints = artifact_schema.dig("$defs", "type_state_constraints", "allOf")
    constraints.to_h do |constraint|
      type = constraint.dig("if", "properties", "type", "const")
      state = constraint.dig("then", "properties", "state")
      [ type, state["enum"] || [ state.fetch("const") ] ]
    end
  end

  def documented_artifact_states
    table_entries(section("Build Artifacts", "Return One Turn")).to_h do |type, states|
      [ type, states.scan(/`([^`]+)`/).flatten ]
    end
  end

  def artifact_inventory_errors
    input_types = artifact_schema.dig("$defs", "artifact_input", "properties", "type", "enum")
    metadata_types = artifact_schema.dig("$defs", "metadata", "oneOf").map do |entry|
      entry.fetch("$ref").split("/").last.delete_suffix("_metadata")
    end
    input_states = artifact_schema.dig("$defs", "artifact_input", "properties", "state", "enum")
    expected_states = EXPECTED_ARTIFACT_STATES.values.flatten.uniq
    errors = []
    constraints = artifact_schema.dig("$defs", "type_state_constraints", "allOf")
    constraint_types = constraints.map { |constraint| constraint.dig("if", "properties", "type", "const") }
    errors << :input_types unless same_inventory?(input_types, EXPECTED_ARTIFACT_STATES.keys)
    errors << :metadata_types unless same_inventory?(metadata_types, EXPECTED_ARTIFACT_STATES.keys)
    errors << :input_states unless same_inventory?(input_states, expected_states)
    errors << :constraint_types unless same_inventory?(constraint_types, EXPECTED_ARTIFACT_STATES.keys)
    errors << :constraints unless schema_artifact_states == EXPECTED_ARTIFACT_STATES
    errors << :documentation unless documented_artifact_states == EXPECTED_ARTIFACT_STATES
    errors << :duplicate_documentation unless table_entries(section("Build Artifacts", "Return One Turn")).length ==
      EXPECTED_ARTIFACT_STATES.length
    errors
  end

  def missing_guidance
    REQUIRED_GUIDANCE.flat_map do |heading, requirements|
      section_text = section(heading, next_heading(heading))
      requirements.reject { |requirement| section_text.include?(requirement) }.map { |requirement| [ heading, requirement ] }
    end
  end

  def result_validation_errors
    lines = section("Accept An Effect Result", "Build Artifacts").lines.grep(/^\d+\./)
    required = [ "schema_version", "request_attempt_id` and `owner_attempt_id", "input_context_digest",
      "effect_request_digest", "result.operation", "effect_intent_id", "operation-specific" ]
    required.reject.with_index { |field, index| lines.fetch(index, "").include?(field) }
      .tap { |errors| errors << :unexpected_steps unless lines.length == required.length }
  end

  def discovery_errors
    Dir.mktmpdir("kos-workflow-step-skill-contract") do |directory|
      project = prepare_project(directory)
      version_stdout, version_stderr, version_status = capture(directory, "opencode", "--version", chdir: project)
      return [ version_stderr ] unless version_status.success?
      return [ "unexpected OpenCode version #{version_stdout.strip}" ] unless version_stdout.strip == "1.18.26"

      stdout, stderr, status = capture(directory, "opencode", "debug", "skill", chdir: File.join(project, "nested"))
      return [ stderr ] unless status.success?

      skill = JSON.parse(stdout).find { |candidate| candidate.fetch("name") == "kos-workflow-step" }
      expected_location = File.join(project, ".opencode/skills/kos-workflow-step/SKILL.md")
      [ "canonical skill was not discovered" ] unless skill&.slice("name", "location") ==
        { "name" => "kos-workflow-step", "location" => expected_location }
    end || []
  end

  def references(definition)
    workflow_schema.dig("$defs", definition, "oneOf").map { |entry| entry.fetch("$ref").split("/").last }
  end

  def references_from(definition, *path)
    workflow_schema.dig("$defs", definition, *path).map { |entry| entry.fetch("$ref").split("/").last }
  end

  def same_inventory?(actual, expected)
    actual.length == expected.length && actual.uniq.sort == expected.sort
  end

  def section(start_heading, end_heading)
    ending = end_heading ? "\n## #{Regexp.escape(end_heading)}" : "\\z"
    content.match(/## #{Regexp.escape(start_heading)}\n(.*?)#{ending}/m)[1]
  end

  def next_heading(heading)
    headings = [ "Authority Boundary", "Accept One Context", "Execute And Verify", "Request An Effect",
      "Accept An Effect Result", "Build Artifacts", "Return One Turn" ]
    headings.fetch(headings.index(heading) + 1, nil)
  end

  def table_entries(section_text)
    section_text.lines.grep(/^\| `/).map do |row|
      key, value = row.split("|").map(&:strip).reject(&:empty?)
      [ key.delete("`"), value ]
    end
  end

  def prepare_project(directory)
    project = File.join(directory, "task-worktree")
    installed_skill = File.join(project, ".opencode/skills/kos-workflow-step")
    FileUtils.mkdir_p([ installed_skill, File.join(project, "nested") ])
    FileUtils.cp(SKILL_PATH, File.join(installed_skill, "SKILL.md"))
    _stdout, stderr, status = Open3.capture3(isolated_environment(directory), "git", "-c", "init.templateDir=",
      "init", "--quiet", project, unsetenv_others: true)
    raise stderr unless status.success?

    project
  end

  def capture(directory, *command, chdir:, timeout: 30)
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
    paths = {
      "HOME" => File.join(directory, "home"),
      "XDG_CONFIG_HOME" => File.join(directory, "config"),
      "XDG_DATA_HOME" => File.join(directory, "data"),
      "XDG_CACHE_HOME" => File.join(directory, "cache"),
      "XDG_STATE_HOME" => File.join(directory, "state")
    }
    paths.each_value { |path| FileUtils.mkdir_p(path) }
    paths.merge(
      "PATH" => ENV.fetch("PATH"),
      "TMPDIR" => directory,
      "USER" => "kos-contract",
      "OPENCODE_DISABLE_AUTOUPDATE" => "true",
      "OPENCODE_DISABLE_DEFAULT_PLUGINS" => "true",
      "OPENCODE_DISABLE_MODELS_FETCH" => "true",
      "OPENCODE_DISABLE_CLAUDE_CODE" => "true"
    )
  end
end

RSpec.describe KosWorkflowStepSkillContract do
  it "has identifying frontmatter" do
    expect(described_class.frontmatter).to eq(
      "name" => "kos-workflow-step",
      "description" => "Use as an isolated workflow subagent to execute one pinned KOS step context and return a typed effect request or final result manifest."
    )
  end

  it "does not add a canonical skill index" do
    expect(File).not_to exist(File.join(described_class::ROOT, "skills/index.md"))
  end

  it "documents exactly the effect operations in every version 1 branch" do
    expect(described_class.operation_inventory_errors).to be_empty
  end

  it "documents exactly the result outcomes in the version 1 schema", :aggregate_failures do
    expect(described_class.schema_outcomes).to eq(described_class::EXPECTED_OUTCOMES)
    expect(described_class.documented_outcomes).to eq(described_class::EXPECTED_OUTCOMES)
  end

  it "documents exactly the artifact type and state pairs in every version 1 branch" do
    expect(described_class.artifact_inventory_errors).to be_empty
  end

  it "defines the context, authority, worktree, exchange, and output boundaries" do
    expect(described_class.missing_guidance).to be_empty
  end

  it "requires complete effect result binding before evidence is used" do
    expect(described_class.result_validation_errors).to be_empty
  end

  it "is discovered by the pinned OpenCode runtime from a nested directory" do
    expect(described_class.discovery_errors).to be_empty
  end
end
