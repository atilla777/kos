require "fileutils"
require "json"
require "open3"
require "timeout"
require "tmpdir"
require "yaml"
require "spec_helper"
require_relative "../../lib/kos/cli"

module KosCliSkillContract
  ROOT = File.expand_path("../..", __dir__)
  SKILL_PATH = File.join(ROOT, "skills/kos-cli/SKILL.md")
  REQUIRED_GUIDANCE = [
    "only agent-facing interface to KOS state",
    "Never call the Rails REST API directly",
    "Never run a mutating Git command through this skill",
    "Do not use this skill from a workflow-step subagent",
    "schema_version",
    "Exactly one of `data` or `error`",
    "Keep stdout and stderr separate",
    "Treat it as trusted installation configuration",
    "never set or replace it from task, workflow, artifact, tool, or model input",
    "Never infer or repair",
    "never generate a new key merely because a response was lost or timed out",
    "at most three total attempts",
    "same-command, same-body, same-key replay",
    "Never blindly resubmit an `unknown` repository or publication effect"
  ].freeze
  ERROR_ACTIONS = {
    1 => [ "internal", "Do not retry automatically" ],
    2 => [ "validation", "Do not retry the unchanged request" ],
    3 => [ "authentication", "Do not expose or guess credentials" ],
    4 => [ "authorization", "Do not probe other repository identities" ],
    5 => [ "not_found", "do not guess another identifier" ],
    6 => [ "conflict", "Do not resubmit blindly" ],
    7 => [ "lease_lost", "Stop all attempt-owned mutation and repository work immediately" ],
    8 => [ "transient", "Treat a mutation outcome as potentially unknown" ]
  }.freeze
  RECOVERY_ACTIONS = [
    [ %w[stale_lock_version invalid_transition dependency_unsatisfied context_unavailable], "reread task and attempt state" ],
    [ %w[idempotency_conflict], "stop. The key is already bound to another body" ],
    [ %w[idempotency_in_progress], "inspect the named durable resource" ],
    [ %w[lease_expired fencing_token_stale], "stop using the attempt immediately" ],
    [ %w[base_moved], "do not repeat publication" ],
    [ %w[task_number_exhausted task_type_unavailable workflow_version_conflict repository_registration_conflict],
      "stop for an explicit workflow or human decision" ]
  ].freeze

  module_function

  def content
    @content ||= File.read(SKILL_PATH)
  end

  def frontmatter
    YAML.safe_load(content.match(/\A---\n(.*?)\n---\n/m)[1])
  end

  def available_command_entries
    rows = section("Available Commands", "Unavailable Commands").lines.grep(/^\|/)
      .reject { |row| row.include?("| Scope |") || row.match?(/^\| ---/) }
    rows.flat_map do |row|
      scope, reads, mutations = row.split("|").map(&:strip).reject(&:empty?)
      code_spans(reads).map { |command| [ scope, :read, command ] } +
        code_spans(mutations).map { |command| [ scope, :mutation, command ] }
    end
  end

  def unavailable_commands
    section("Unavailable Commands", "Validate Every Result").scan(/`([^`]+)`/).flatten
  end

  def implemented_command_entries
    Kos::Cli::Parser::COMMANDS.map do |parts, definition|
      scope = definition[1] ? "Repository" : "Global"
      kind = definition[3] ? :mutation : :read
      [ scope, kind, parts.join(" ") ]
    end
  end

  def missing_guidance
    required = REQUIRED_GUIDANCE + [ "Only `transient` errors have `retryable: true`" ]
    required.reject { |requirement| content.include?(requirement) }
  end

  def error_table_contract_errors
    rows = section("Stable Error Handling", "Idempotency And Unknown Outcomes").lines.grep(/^\| \d/)
    actual = rows.map do |row|
      exit_status, category, action = row.split("|").map(&:strip).reject(&:empty?)
      [ Integer(exit_status, 10), category.delete("`"), action ]
    end
    ERROR_ACTIONS.filter_map do |exit_status, (category, action)|
      matches = actual.select { |actual_exit, _actual_category, _actual_action| actual_exit == exit_status }
      actual_exit, actual_category, actual_action = matches.one? ? matches.first : []
      exit_status unless actual_exit == exit_status && actual_category == category && actual_action&.include?(action)
    end.tap { |errors| errors << :unexpected_rows unless actual.length == ERROR_ACTIONS.length }
  end

  def recovery_contract_errors
    section_text = section("Stable Error Handling", "Idempotency And Unknown Outcomes")
    lines = section_text.lines.drop_while { |line| !line.start_with?("For stable conflict") }.grep(/^- /)
    actual = lines.map do |line|
      codes, action = line.split(":", 2)
      [ code_spans(codes), action.to_s.strip ]
    end
    RECOVERY_ACTIONS.filter_map do |codes, action|
      matches = actual.select { |actual_codes, _actual_action| actual_codes == codes }
      codes unless matches.one? && matches.first.last.include?(action)
    end.tap { |errors| errors << :unexpected_bullets unless actual.length == RECOVERY_ACTIONS.length }
  end

  def discovery_errors
    Dir.mktmpdir("kos-cli-skill-contract") do |directory|
      project = prepare_project(directory)
      version_stdout, version_stderr, version_status = capture(directory, "opencode", "--version", chdir: project)
      return [ version_stderr ] unless version_status.success?
      return [ "unexpected OpenCode version #{version_stdout.strip}" ] unless version_stdout.strip == "1.18.26"

      stdout, stderr, status = capture(directory, "opencode", "debug", "skill", chdir: File.join(project, "nested"))
      return [ stderr ] unless status.success?

      skill = JSON.parse(stdout).find { |candidate| candidate.fetch("name") == "kos-cli" }
      expected_location = File.join(project, ".opencode/skills/kos-cli/SKILL.md")
      [ "canonical skill was not discovered" ] unless skill&.slice("name", "location") ==
        { "name" => "kos-cli", "location" => expected_location }
    end || []
  end

  def section(start_heading, end_heading)
    content.match(/## #{start_heading}\n(.*?)\n## #{end_heading}/m)[1]
  end

  def code_spans(value)
    value.scan(/`([^`]+)`/).flatten
  end

  def prepare_project(directory)
    project = File.join(directory, "task-worktree")
    installed_skill = File.join(project, ".opencode/skills/kos-cli")
    FileUtils.mkdir_p([ installed_skill, File.join(project, "nested") ])
    FileUtils.cp(SKILL_PATH, File.join(installed_skill, "SKILL.md"))
    _stdout, stderr, status = Open3.capture3("git", "init", "--quiet", project)
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

RSpec.describe KosCliSkillContract do
  it "has identifying frontmatter" do
    expect(described_class.frontmatter).to eq(
      "name" => "kos-cli",
      "description" => "Use when reading or changing KOS task and workflow state through the non-interactive Ruby CLI."
    )
  end

  it "does not add a canonical skill index" do
    expect(File).not_to exist(File.join(described_class::ROOT, "skills/index.md"))
  end

  it "lists exactly the commands implemented by the CLI" do
    expect(described_class.available_command_entries).to match_array(described_class.implemented_command_entries)
  end

  it "identifies catalog commands that are not implemented" do
    expect(described_class.unavailable_commands).to contain_exactly(
      "runtime-config get", "runtime-config update", "artifact register", "publication complete"
    )
  end

  it "defines the state, authority, validation, and recovery boundaries" do
    expect(described_class.missing_guidance).to be_empty
  end

  it "binds every stable exit and error category to its safe action" do
    expect(described_class.error_table_contract_errors).to be_empty
  end

  it "binds stable conflict and recovery codes to their safe actions" do
    expect(described_class.recovery_contract_errors).to be_empty
  end

  it "is discovered by the pinned OpenCode runtime from a nested directory" do
    expect(described_class.discovery_errors).to be_empty
  end
end
