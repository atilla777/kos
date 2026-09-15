require "fileutils"
require "json"
require "open3"
require "timeout"
require "tmpdir"
require "yaml"
require "spec_helper"

module KosRepositorySkillContract
  ROOT = File.expand_path("../..", __dir__)
  SKILL_PATH = File.join(ROOT, "skills/kos-repository/SKILL.md")
  SCHEMA_PATHS = Dir[File.join(ROOT, "schemas/repository/v{1,2}/adapter.json")].sort.freeze
  EXPECTED_OPERATIONS = %w[materialize observe remove commit fetch rebase push publication_preflight].freeze
  NON_REPEATABLE_OPERATIONS = %w[materialize remove commit fetch rebase push].freeze
  REQUIRED_GUIDANCE = {
    "Authority Boundary" => [
      "sole executor of mutating Git operations", "Invoke this skill only as the lease-owning orchestrator",
      "Never use this skill from a workflow-step subagent", "read authoritative KOS state",
      "its current lock version", "the active attempt, unexpired lease, fencing token",
      "verify the finalized input-context digest and effect allowlist",
      "Materialization and lifecycle observation occur before context finalization",
      "workflow operation `worktree_remove` maps only to adapter operation `remove`",
      "does not query Rails or independently prove"
    ],
    "Durable Intent First" => [
      "Every operation belongs to an existing durable protocol", "Version 1 has no generic adapter command",
      "Never infer, repair, normalize, or substitute"
    ],
    "Invocation Contract" => [
      "Pass the executable and every argument as a process argument array", "Keep stdout and stderr separate",
      "has no API token, repository flag, idempotency key, or built-in retry loop"
    ]
  }.freeze
  DURABLE_AUTHORITY = {
    "materialize" => [ "Current `reserved` worktree reservation", "exact expected base commit" ],
    "observe" => [ "Current `reserved`, `confirmed`, or `release_pending` worktree reservation" ],
    "remove" => [ "Allowed `worktree_remove` effect", "current `release_pending`", "matching clean observation" ],
    "commit" => [ "Current `confirmed` reservation", "prepared durable `commit` effect" ],
    "fetch" => [ "Prepared or adopted durable `fetch` effect", "registered repository trust snapshot" ],
    "rebase" => [ "Current `confirmed` reservation", "durable `rebase` effect", "verified fetch request and result" ],
    "push" => [ "Prepared or adopted publication", "current task version",
      "approved review and required-check evidence for the exact candidate", "registered publication target" ],
    "publication_preflight" => [ "Prepared or adopted version 2 publication preflight",
      "registered repository trust snapshot" ]
  }.freeze
  RESULT_VALIDATION = {
    1 => "exactly one JSON object", 2 => "`schema_version`", 3 => "`operation` equals",
    4 => "`outcome` is exactly", 5 => "adapter.json#/$defs", 6 => "Exit status",
    7 => "Every returned repository, reservation, effect, publication", 8 => "Every required observation or evidence"
  }.freeze
  RECOVERY_GUIDANCE = [
    "Never submit an arbitrary raw adapter document or invent missing envelope fields",
    "Preserve `dirty`, `mismatched`, conflicts, failures, and unknown outcomes",
    "candidate_reachable: false", "cannot be submitted to `publication reconcile` without a concrete observation",
    "mandatory preflight observation returns without pushing", "Never blindly push again",
    "After a timeout, lost response, transient failure, or otherwise invalid result from a mutating operation"
  ].freeze
  ERROR_EXITS = {
    0 => [ "success", "not workflow completion" ],
    1 => [ "internal", "do not retry automatically" ],
    2 => [ "validation", "do not retry unchanged input" ],
    6 => [ "conflict", "do not override it" ],
    8 => [ "transient", "do not treat `retryable: true` as authority to repeat it" ]
  }.freeze

  module_function

  def content
    @content ||= File.read(SKILL_PATH)
  end

  def frontmatter
    YAML.safe_load(content.match(/\A---\n(.*?)\n---\n/m)[1])
  end

  def documented_operations
    rows = section("Implemented Operations", "Validate Every Result").lines.grep(/^\| `/)
    rows.map { |row| row.split("|").map(&:strip).reject(&:empty?).first.delete("`") }
  end

  def invocation_operations
    invocation = section("Invocation Contract", "Implemented Operations").match(
      /kos-repository <([^>]+)> --input <path\|-> --json/
    )[1]
    invocation.split("|")
  end

  def schema_operations
    SCHEMA_PATHS.flat_map do |path|
      schema = JSON.parse(File.read(path))
      request = schema.dig("$defs", "request")
      references = request.fetch("oneOf", [ { "$ref" => request.dig("properties", "operation", "const") } ])
      references.map do |reference|
        reference.fetch("$ref").split("/").last.delete_suffix("_request")
      end
    end
  end

  def missing_guidance
    REQUIRED_GUIDANCE.flat_map do |heading, requirements|
      section_text = section(heading, next_heading(heading))
      requirements.reject { |requirement| section_text.include?(requirement) }.map { |requirement| [ heading, requirement ] }
    end
  end

  def durable_authority_contract_errors
    actual = table_entries(section("Durable Intent First", "Invocation Contract"))
    DURABLE_AUTHORITY.filter_map do |operation, requirements|
      matches = actual.select { |actual_operation, _description| actual_operation == operation }
      operation unless matches.one? && requirements.all? { |requirement| matches.first.last.include?(requirement) }
    end.tap { |errors| errors << :unexpected_rows unless actual.map(&:first) == EXPECTED_OPERATIONS }
  end

  def result_validation_contract_errors
    lines = section("Validate Every Result", "Reconcile Observations").lines.grep(/^\d+\./)
    actual = lines.to_h { |line| [ Integer(line[/^\d+/], 10), line ] }
    RESULT_VALIDATION.filter_map do |number, requirement|
      number unless actual.fetch(number, "").include?(requirement)
    end.tap { |errors| errors << :unexpected_steps unless lines.length == RESULT_VALIDATION.length }
  end

  def recovery_contract_errors
    section_text = section("Reconcile Observations", "Safe Invocation Sequence")
    RECOVERY_GUIDANCE.reject { |requirement| section_text.include?(requirement) }.tap do |errors|
      operations = section_text.match(/Do not repeat (`[^\n]+`) merely/)&.captures&.first&.scan(/`([^`]+)`/)&.flatten
      errors << :mutation_inventory unless operations == NON_REPEATABLE_OPERATIONS
    end
  end

  def error_table_contract_errors
    rows = section("Validate Every Result", "Reconcile Observations").lines.grep(/^\| \d/)
    actual = rows.map do |row|
      exit_status, category, meaning = row.split("|").map(&:strip).reject(&:empty?)
      [ Integer(exit_status, 10), [ category.delete("`"), meaning ] ]
    end
    ERROR_EXITS.filter_map do |exit_status, (category, meaning)|
      matches = actual.select { |actual_exit, _interpretation| actual_exit == exit_status }
      actual_category, actual_meaning = matches.one? ? matches.first.last : []
      exit_status unless actual_category == category && actual_meaning&.include?(meaning)
    end.tap { |errors| errors << :unexpected_rows unless actual.length == ERROR_EXITS.length }
  end

  def discovery_errors
    Dir.mktmpdir("kos-repository-skill-contract") do |directory|
      project = prepare_project(directory)
      version_stdout, version_stderr, version_status = capture(directory, "opencode", "--version", chdir: project)
      return [ version_stderr ] unless version_status.success?
      return [ "unexpected OpenCode version #{version_stdout.strip}" ] unless version_stdout.strip == "1.18.26"

      stdout, stderr, status = capture(directory, "opencode", "debug", "skill", chdir: File.join(project, "nested"))
      return [ stderr ] unless status.success?

      skill = JSON.parse(stdout).find { |candidate| candidate.fetch("name") == "kos-repository" }
      expected_location = File.join(project, ".opencode/skills/kos-repository/SKILL.md")
      [ "canonical skill was not discovered" ] unless skill&.slice("name", "location") ==
        { "name" => "kos-repository", "location" => expected_location }
    end || []
  end

  def section(start_heading, end_heading)
    content.match(/## #{start_heading}\n(.*?)\n## #{end_heading}/m)[1]
  end

  def next_heading(heading)
    headings = REQUIRED_GUIDANCE.keys + [ "Implemented Operations" ]
    headings.fetch(headings.index(heading) + 1)
  end

  def table_entries(section_text)
    section_text.lines.grep(/^\| `/).map do |row|
      operation, description = row.split("|").map(&:strip).reject(&:empty?)
      [ operation.delete("`"), description ]
    end
  end

  def prepare_project(directory)
    project = File.join(directory, "task-worktree")
    installed_skill = File.join(project, ".opencode/skills/kos-repository")
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

RSpec.describe KosRepositorySkillContract do
  it "has identifying frontmatter" do
    expect(described_class.frontmatter).to eq(
      "name" => "kos-repository",
      "description" => "Use only as the lease-owning orchestrator to execute persisted typed Git effects through the closed KOS repository adapter contract."
    )
  end

  it "does not add a canonical skill index" do
    expect(File).not_to exist(File.join(described_class::ROOT, "skills/index.md"))
  end

  it "lists exactly the operations in the closed adapter request schema", :aggregate_failures do
    expect(described_class.schema_operations).to match_array(described_class::EXPECTED_OPERATIONS)
    expect(described_class.documented_operations).to match_array(described_class::EXPECTED_OPERATIONS)
    expect(described_class.invocation_operations).to eq(described_class::EXPECTED_OPERATIONS)
  end

  it "defines authority, durable state, validation, and recovery boundaries" do
    expect(described_class.missing_guidance).to be_empty
  end

  it "binds every adapter operation to its durable authority" do
    expect(described_class.durable_authority_contract_errors).to be_empty
  end

  it "requires complete result validation" do
    expect(described_class.result_validation_contract_errors).to be_empty
  end

  it "preserves uncertain outcomes for bounded recovery" do
    expect(described_class.recovery_contract_errors).to be_empty
  end

  it "binds every process exit to its safe interpretation" do
    expect(described_class.error_table_contract_errors).to be_empty
  end

  it "is discovered by the pinned OpenCode runtime from a nested directory" do
    expect(described_class.discovery_errors).to be_empty
  end
end
