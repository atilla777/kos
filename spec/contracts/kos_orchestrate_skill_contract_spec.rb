require "fileutils"
require "json"
require "open3"
require "timeout"
require "tmpdir"
require "yaml"
require "spec_helper"
require_relative "../../lib/kos/cli"

module KosOrchestrateSkillContract
  ROOT = File.expand_path("../..", __dir__)
  SKILL_PATH = File.join(ROOT, "skills/kos-orchestrate/SKILL.md")
  WORKFLOW_SCHEMA_PATH = File.join(ROOT, "schemas/cli/v1/workflow.json")
  DEFINITION_SCHEMA_PATH = File.join(ROOT, "schemas/cli/v1/workflow_definition.json")
  EXPECTED_MODES = %w[main_session subagent].freeze
  EXPECTED_OPERATIONS = %w[worktree_remove commit fetch rebase push].freeze
  EXPECTED_PROTOCOLS = {
    "worktree_remove" => [ "worktree release", "release_pending", "remove", "absent", "worktree release" ],
    "commit" => [ "effect prepare", "commit", "effect reconcile" ],
    "fetch" => [ "effect prepare", "fetch", "effect reconcile" ],
    "rebase" => [ "onto_sha", "effect prepare", "rebase", "effect reconcile" ],
    "push" => [ "push", "publication reconcile" ]
  }.freeze
  REQUIRED_COMMANDS = %w[
    task.get workflow.get attempt.get worktree.get effect.get publication.get artifact.list
    attempt.claim attempt.renew attempt.fail attempt.needs_human attempt.reconcile step.context step.complete
    worktree.reserve worktree.confirm worktree.reconcile worktree.release
    effect.prepare effect.reconcile publication.prepare publication.reconcile
  ].freeze
  REQUIRED_GUIDANCE = {
    "Authority Boundary" => [
      "explicit immutable `repository_id` and public task number", "only interface to KOS state",
      "Never call Rails or its REST API directly", "Never run Git directly", "one workflow status per invocation",
      "Never let the workflow-step child call `kos`, `kos-repository`, Git, another subagent"
    ],
    "Read Authoritative State" => [
      "immutable `workflow_version_id`", "Never use an active replacement workflow",
      "Reread all operation-specific state immediately before", "registered repository field",
      "Never source a Git common directory", "cursor to exhaustion without loops"
    ],
    "Own The Attempt" => [
      "expired unreconciled attempt", "undiscoverable generic effect", "one idempotency key", "Never use a new key",
      "foreground child blocks the parent", "reread the task and attempt immediately after every child turn",
      "adapter's bounded timeout plus the time reserved for KOS reconciliation",
      "stop all attempt-owned mutation and repository work immediately"
    ],
    "Prepare The Context" => [
      "no such path-allocation read", "never derive a path", "worktree reserve", "worktree confirm",
      "Dirty or mismatched state is a blocker",
      "publication prepare", "RFC 8785 canonical JSON serialization", "mix it with another context"
    ],
    "Dispatch The Pinned Mode" => [
      "not a context field", "runtime-generated completed Task wrapper", "process-event metadata",
      "never from nested child-generated JSON", "exactly one JSON document and no prose",
      "continue exactly the retained child session"
    ],
    "Mediate Typed Effects" => [
      "appears exactly in `allowed_repository_effects`", "no earlier request is pending",
      "Persist the required intent before", "Adapter success is an observation, not workflow success",
      "Return it only to the retained child session", "preserve `failed` and `unknown` outcomes exactly",
      "return success only after an `absent` observation", "`push_state_uncertain`",
      "cannot complete, fail, or enter `needs_human`"
    ],
    "Submit The Result" => [
      "preserve its substantive outcome, artifacts, summary, and evidence unchanged",
      "only when exactly one transition is fully evidenced", "Do not infer a `decision` value",
      "publication complete", "never pass publication evidence to `step complete`"
    ],
    "Deliver Retrospective Separately" => [
      "`KOS_RETROSPECTIVE_ENABLED`", "explicitly invoke `child_retrospective`",
      "`subagent_type` is exactly `kos-workflow-step`", "with exactly one argument, `child_session_id`",
      "tool call itself is the explicit acknowledgement signal", "never send `lifecycle_eligible`",
      "`outcome: \"no_result\"`", "`no_action`", "structurally validate", "never as proof of semantic privacy",
      "five schema-valid sanitized child results in receipt order", "KOS supplies no raw child dialogue",
      "`kos-opencode`", "`KOS_RETROSPECTIVE_FD`"
    ],
    "Fail Closed At Missing Boundaries" => [
      "publication cannot advance to `completed`", "complete registered repository trust snapshot",
      "authoritative worktree allocation path", "adopted generic effect IDs",
      "No generic adapter observation operation", "No background lease keeper",
      "Do not call an unavailable command"
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

  def definition_schema
    @definition_schema ||= JSON.parse(File.read(DEFINITION_SCHEMA_PATH))
  end

  def schema_modes
    definition_schema.dig("$defs", "status", "properties", "execution_mode", "enum")
  end

  def documented_modes
    table_entries(section("Dispatch The Pinned Mode", "Mediate Typed Effects")).map(&:first)
  end

  def schema_operations
    workflow_schema.dig("$defs", "requested_effect", "oneOf").map do |entry|
      entry.fetch("$ref").split("/").last.delete_suffix("_effect")
    end
  end

  def allowlist_operations
    workflow_schema.dig("$defs", "context", "properties", "allowed_repository_effects", "items", "enum")
  end

  def documented_protocols
    table_entries(section("Mediate Typed Effects", "Submit The Result")).to_h do |operation, protocol|
      [ operation, protocol.scan(/`([^`]+)`/).flatten ]
    end
  end

  def implemented_commands
    Kos::Cli::Parser::COMMANDS.values.map(&:first)
  end

  def missing_guidance
    REQUIRED_GUIDANCE.flat_map do |heading, requirements|
      text = section(heading, next_heading(heading))
      requirements.reject { |requirement| text.include?(requirement) }.map { |requirement| [ heading, requirement ] }
    end
  end

  def missing_boundary_guidance
    required = [ "`publication complete` is unavailable", "`worktree get` does not supply every fresh HEAD",
      "No generic adapter observation operation", "No background lease keeper", "direct API or Git access" ]
    blocked = section("Fail Closed At Missing Boundaries", nil)
    required.reject { |guidance| blocked.include?(guidance) }
  end

  def discovery_errors
    Dir.mktmpdir("kos-orchestrate-skill-contract") do |directory|
      project = prepare_project(directory)
      version_stdout, version_stderr, version_status = capture(directory, "opencode", "--version", chdir: project)
      return [ version_stderr ] unless version_status.success?
      return [ "unexpected OpenCode version #{version_stdout.strip}" ] unless version_stdout.strip == "1.18.26"

      stdout, stderr, status = capture(directory, "opencode", "debug", "skill", chdir: File.join(project, "nested"))
      return [ stderr ] unless status.success?

      skill = JSON.parse(stdout).find { |candidate| candidate.fetch("name") == "kos-orchestrate" }
      expected_location = File.join(project, ".opencode/skills/kos-orchestrate/SKILL.md")
      [ "canonical skill was not discovered" ] unless skill&.slice("name", "location") ==
        { "name" => "kos-orchestrate", "location" => expected_location }
    end || []
  end

  def section(start_heading, end_heading)
    ending = end_heading ? "\n## #{Regexp.escape(end_heading)}" : "\\z"
    content.match(/## #{Regexp.escape(start_heading)}\n(.*?)#{ending}/m)[1]
  end

  def next_heading(heading)
    headings = [ "Authority Boundary", "Read Authoritative State", "Own The Attempt", "Prepare The Context",
      "Dispatch The Pinned Mode", "Mediate Typed Effects", "Submit The Result", "Deliver Retrospective Separately",
      "Fail Closed At Missing Boundaries" ]
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
    installed_skill = File.join(project, ".opencode/skills/kos-orchestrate")
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

RSpec.describe KosOrchestrateSkillContract do
  it "has identifying frontmatter" do
    expect(described_class.frontmatter).to eq(
      "name" => "kos-orchestrate",
      "description" => "Use as the lease-owning main session to coordinate one pinned KOS workflow status, its foreground executor, and durable repository effects."
    )
  end

  it "does not add a canonical skill index" do
    expect(File).not_to exist(File.join(described_class::ROOT, "skills/index.md"))
  end

  it "documents exactly the version 1 execution modes", :aggregate_failures do
    expect(described_class.schema_modes).to eq(described_class::EXPECTED_MODES)
    expect(described_class.documented_modes).to eq(described_class::EXPECTED_MODES)
  end

  it "documents exactly the version 1 effect operations and durable protocols", :aggregate_failures do
    expect(described_class.schema_operations).to eq(described_class::EXPECTED_OPERATIONS)
    expect(described_class.allowlist_operations).to eq(described_class::EXPECTED_OPERATIONS)
    expect(described_class.documented_protocols).to eq(described_class::EXPECTED_PROTOCOLS)
  end

  it "uses only implemented CLI commands for the available orchestration path" do
    expect(described_class::REQUIRED_COMMANDS - described_class.implemented_commands).to be_empty
  end

  it "defines authority, ownership, context, routing, effect, and completion boundaries" do
    expect(described_class.missing_guidance).to be_empty
  end

  it "identifies unavailable operational boundaries without bypassing them" do
    expect(described_class.missing_boundary_guidance).to be_empty
  end

  it "is discovered by the pinned OpenCode runtime from a nested directory" do
    expect(described_class.discovery_errors).to be_empty
  end
end
