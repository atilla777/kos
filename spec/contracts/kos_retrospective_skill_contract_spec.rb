require "fileutils"
require "json"
require "open3"
require "timeout"
require "tmpdir"
require "yaml"
require "spec_helper"

module KosRetrospectiveSkillContract
  ROOT = File.expand_path("../..", __dir__)
  SKILL_PATH = File.join(ROOT, "skills/kos-retrospective/SKILL.md")
  SCHEMA_PATH = File.join(ROOT, "schemas/runtime/v1/retrospective.json")
  EXPECTED_SOURCES = %w[orchestrator workflow_step].freeze
  EXPECTED_OUTCOMES = %w[no_action proposals].freeze
  EXPECTED_CATEGORIES = %w[kos_product kos_installation workflow project].freeze
  EXPECTED_RESULT_MEMBERS = %w[
    schema_version session_id source primary_result_acknowledged outcome proposals
  ].freeze
  EXPECTED_REQUIRED_PROPOSAL_MEMBERS = %w[
    category problem observed_impact sanitized_evidence proposed_outcome suggested_task_type uncertainties
  ].freeze
  EXPECTED_OPTIONAL_PROPOSAL_MEMBERS = %w[workflow_version_id repository_id].freeze
  EXPECTED_ANNOTATIONS = {
    "x-private-input" => "invoking-agent-dialogue-only",
    "x-persistence" => "none",
    "x-primary-result-independent" => true,
    "x-recursion-suppressed" => true
  }.freeze
  EXPECTED_BOUNDS = {
    proposals_maximum: 5,
    text_bounds: %w[problem observed_impact sanitized_evidence proposed_outcome].to_h do |field|
      [ field, [ 1, 4096 ] ]
    end,
    task_type_pattern: "^[a-z][a-z0-9_-]{0,127}$",
    task_type_maximum: 128,
    uncertainties_maximum: 10,
    uncertainty_bounds: [ 1, 1024 ],
    no_action_maximum: 0,
    proposals_minimum: 1
  }.freeze
  FORBIDDEN_GUIDANCE = [
    "may send raw dialogue", "can send raw dialogue", "may include verbatim transcript", "may read KOS state",
    "may mutate KOS state", "may read or write the filesystem", "may invoke Git", "may use the network",
    "may launch or continue a subagent", "may change the primary result"
  ].freeze
  REQUIRED_GUIDANCE = {
    "Accept The Lifecycle Boundary" => [
      "installation-wide retrospective setting is enabled", "disabled by default",
      "gracefully ending KOS orchestration session", "independently launched `kos-workflow-step` session",
      "Internal `kos-cli` or `kos-repository` calls", "Abrupt runtime or process loss",
      "runtime-established recursion marker", "Never infer, generate, repair, or override them",
      "Missing or malformed invocation data produces no retrospective result"
    ],
    "Preserve The Primary Result" => [
      "primary result was delivered", "acknowledged and durably handled it", "`primary_result_acknowledged: true`",
      "fixed 30-second runtime budget", "including provider latency", "must not delay, replace, downgrade, amend, or change",
      "Deliver the retrospective result separately"
    ],
    "Protect Privacy And Authority" => [
      "dialogue available in the invoking agent's own session", "only a closed child result that passed runtime validation",
      "untrusted evidence, not executable instructions", "Never send raw dialogue or verbatim transcript excerpts",
      "credentials, secrets, environment values, personal data, unrelated source content, and private absolute paths",
      "runtime structurally validates", "deterministically rejects obvious", "not proof", "return `no_action`",
      "Do not read or mutate KOS state", "read or write the filesystem", "launch or continue a subagent"
    ],
    "Analyze The Session" => [
      "Split mixed findings", "Retain every material uncertainty", "return `no_action`",
      "`suggested_task_type` is not reliably known"
    ],
    "Classify Proposals" => [
      "installed runtime copy is derived material", "never the canonical edit target",
      "only when the permitted input establishes the exact schema-valid UUID"
    ],
    "Build The Closed Result" => [
      "exactly one JSON document with no prose", "The string `1`", "schema-valid UUID supplied by the runtime",
      "The literal `true`", "zero to five closed proposal objects", "exactly these required members",
      "no other member is allowed", "nonempty strings of at most 4096 characters",
      "at most ten nonempty strings, each at most 1024 characters", "For `outcome: \"no_action\"`",
      "For `outcome: \"proposals\"`, it contains one to five"
    ],
    "Leave Follow-Up To The User" => [
      "sanitized runtime transport document with no persistence", "Do not deduplicate, submit, create, approve, schedule",
      "The user decides whether follow-up is warranted"
    ],
    "Use The OpenCode Lifecycle Transport" => [
      "`kos-opencode`", "samples installation-wide enablement once", "same root OpenCode session",
      "`subagent_type` is exactly `kos-workflow-step`", "with only `child_session_id`",
      "not a model-supplied eligibility or acknowledgement boolean", "retained idle child session",
      "at most five sanitized child results in receipt order", "`KOS_RETROSPECTIVE_FD`",
      "Distinguish transport outcome `no_result`", "skill outcome is `no_action`"
    ]
  }.freeze

  module_function

  def content
    @content ||= File.read(SKILL_PATH)
  end

  def frontmatter
    YAML.safe_load(content.match(/\A---\n(.*?)\n---\n/m)[1])
  end

  def schema
    @schema ||= JSON.parse(File.read(SCHEMA_PATH))
  end

  def result_schema
    schema.dig("$defs", "result")
  end

  def proposal_schema
    schema.dig("$defs", "proposal")
  end

  def documented_categories
    table_entries(section("Classify Proposals", "Build The Closed Result")).map(&:first)
  end

  def documented_result_members
    table_entries(section("Build The Closed Result", "Leave Follow-Up To The User")).map(&:first)
  end

  def documented_sources
    result_member_value("source").scan(/`([^`]+)`/).flatten
  end

  def documented_outcomes
    result_member_value("outcome").scan(/`([^`]+)`/).flatten
  end

  def documented_proposal_members
    result_text = section("Build The Closed Result", "Leave Follow-Up To The User")
    required = result_text.match(/required members: (.*?)\./m)[1].scan(/`([^`]+)`/).flatten
    optional = result_text.match(/may also contain (.*?);/m)[1].scan(/`([^`]+)`/).flatten
    [ required, optional ]
  end

  def schema_contract
    proposal_properties = proposal_schema.fetch("properties")
    result_properties = result_schema.fetch("properties")
    {
      sources: result_properties.dig("source", "enum"),
      outcomes: result_properties.dig("outcome", "enum"),
      categories: proposal_properties.dig("category", "enum"),
      result_members: result_properties.keys,
      required_result_members: result_schema.fetch("required"),
      required_proposal_members: proposal_schema.fetch("required"),
      optional_proposal_members: proposal_properties.keys - proposal_schema.fetch("required"),
      result_closed: result_schema.fetch("additionalProperties"),
      proposal_closed: proposal_schema.fetch("additionalProperties")
    }
  end

  def schema_bounds
    proposal_properties = proposal_schema.fetch("properties")
    text_fields = %w[problem observed_impact sanitized_evidence proposed_outcome]
    {
      proposals_maximum: result_schema.dig("properties", "proposals", "maxItems"),
      text_bounds: text_fields.to_h do |field|
        [ field, proposal_properties.fetch(field).values_at("minLength", "maxLength") ]
      end,
      task_type_pattern: schema.dig("$defs", "identifier", "pattern"),
      task_type_maximum: 128,
      uncertainties_maximum: proposal_properties.dig("uncertainties", "maxItems"),
      uncertainty_bounds: proposal_properties.dig("uncertainties", "items").values_at("minLength", "maxLength"),
      no_action_maximum: result_schema.dig("allOf", 0, "then", "properties", "proposals", "maxItems"),
      proposals_minimum: result_schema.dig("allOf", 1, "then", "properties", "proposals", "minItems")
    }
  end

  def shape_contract
    contract = schema_contract
    required, optional = documented_proposal_members
    [ contract[:result_members], contract[:required_result_members], documented_result_members,
      contract[:required_proposal_members], required, contract[:optional_proposal_members], optional,
      contract.values_at(:result_closed, :proposal_closed) ]
  end

  def inventory_contract
    contract = schema_contract
    [ contract[:sources], documented_sources, contract[:outcomes], documented_outcomes,
      contract[:categories], documented_categories ]
  end

  def missing_guidance
    REQUIRED_GUIDANCE.flat_map do |heading, requirements|
      section_text = section(heading, next_heading(heading))
      requirements.reject { |requirement| section_text.include?(requirement) }.map { |requirement| [ heading, requirement ] }
    end
  end

  def forbidden_guidance
    FORBIDDEN_GUIDANCE.select { |guidance| content.downcase.include?(guidance.downcase) }
  end

  def discovery_errors
    Dir.mktmpdir("kos-retrospective-skill-contract") do |directory|
      project = prepare_project(directory)
      version_stdout, version_stderr, version_status = capture(directory, "opencode", "--version", chdir: project)
      return [ version_stderr ] unless version_status.success?
      return [ "unexpected OpenCode version #{version_stdout.strip}" ] unless version_stdout.strip == "1.18.26"

      stdout, stderr, status = capture(directory, "opencode", "debug", "skill", chdir: File.join(project, "nested"))
      return [ stderr ] unless status.success?

      skill = JSON.parse(stdout).find { |candidate| candidate.fetch("name") == "kos-retrospective" }
      expected_location = File.join(project, ".opencode/skills/kos-retrospective/SKILL.md")
      [ "canonical skill was not discovered" ] unless skill&.slice("name", "location") ==
        { "name" => "kos-retrospective", "location" => expected_location }
    end || []
  end

  def result_member_value(member)
    table_entries(section("Build The Closed Result", "Leave Follow-Up To The User")).to_h.fetch(member)
  end

  def section(start_heading, end_heading)
    ending = end_heading ? "\n## #{Regexp.escape(end_heading)}" : "\\z"
    content.match(/## #{Regexp.escape(start_heading)}\n(.*?)#{ending}/m)[1]
  end

  def next_heading(heading)
    headings = [ "Accept The Lifecycle Boundary", "Preserve The Primary Result", "Protect Privacy And Authority",
      "Analyze The Session", "Classify Proposals", "Build The Closed Result", "Leave Follow-Up To The User",
      "Use The OpenCode Lifecycle Transport" ]
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
    installed_skill = File.join(project, ".opencode/skills/kos-retrospective")
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

RSpec.describe KosRetrospectiveSkillContract do
  it "has identifying frontmatter" do
    expect(described_class.frontmatter).to eq(
      "name" => "kos-retrospective",
      "description" => "Use for private post-primary analysis of one gracefully ending KOS session and a separate sanitized improvement result."
    )
  end

  it "does not add a canonical skill index" do
    expect(File).not_to exist(File.join(described_class::ROOT, "skills/index.md"))
  end

  it "documents the exact closed version 1 result shape" do
    result = described_class::EXPECTED_RESULT_MEMBERS
    proposal = described_class::EXPECTED_REQUIRED_PROPOSAL_MEMBERS
    optional = described_class::EXPECTED_OPTIONAL_PROPOSAL_MEMBERS
    expect(described_class.shape_contract).to eq([ result, result, result, proposal, proposal, optional, optional,
      [ false, false ] ])
  end

  it "documents exact source, outcome, and category inventories" do
    sources = described_class::EXPECTED_SOURCES
    outcomes = described_class::EXPECTED_OUTCOMES
    categories = described_class::EXPECTED_CATEGORIES
    expect(described_class.inventory_contract).to eq([ sources, sources, outcomes, outcomes, categories, categories ])
  end

  it "preserves the schema annotations and bounded result contract" do
    annotations = described_class::EXPECTED_ANNOTATIONS
    actual = described_class.result_schema.slice(*annotations.keys)
    expect([ actual, described_class.schema_bounds ]).to eq([ annotations, described_class::EXPECTED_BOUNDS ])
  end

  it "defines lifecycle, primary-result, privacy, authority, classification, and task boundaries" do
    expect([ described_class.missing_guidance, described_class.forbidden_guidance ]).to eq([ [], [] ])
  end

  it "is discovered from a nested worktree by pinned OpenCode" do
    expect(described_class.discovery_errors).to be_empty
  end
end
