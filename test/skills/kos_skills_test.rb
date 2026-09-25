require "test_helper"
require "json"
require "yaml"

class KosSkillsTest < ActiveSupport::TestCase
  ORCHESTRATOR_PATH = Rails.root.join("skills/kos/SKILL.md")
  STEP_PATH = Rails.root.join("skills/kos-step/SKILL.md")
  CLI_PATH = Rails.root.join("skills/kos-cli/SKILL.md")
  BUILT_IN_PROFILES = %w[diagnose plan implement document brief review publish verify].freeze
  AGENT_PATHS = (BUILT_IN_PROFILES + %w[step-standard step-advanced]).to_h do |name|
    [ "kos-#{name}", Rails.root.join(".opencode/agents/kos-#{name}.md") ]
  end.freeze

  test "defines discoverable scheduler step and CLI skills" do
    assert_skill ORCHESTRATOR_PATH, "kos", /scheduler/
    assert_skill STEP_PATH, "kos-step", /positive task ID/
    assert_skill CLI_PATH, "kos-cli", /public KOS CLI/

    config = JSON.parse(File.read(Rails.root.join("opencode.json")))
    assert_equal [ "./skills" ], config.dig("skills", "paths")
  end

  test "request creation uses the focused idempotent CLI operation" do
    scheduler = File.read(ORCHESTRATOR_PATH)
    brief_scheduler = File.read(Rails.root.join("skills/kos-brief/SKILL.md"))
    compact = scheduler.gsub(/\s+/, " ")

    assert_includes scheduler, "`fix` or `brief`: use `task create-or-get`"
    assert_includes scheduler, "complete exact request through standard input"
    assert_includes compact, "Follow `kos-cli` whenever a mutation's result is ambiguous"
    assert_includes brief_scheduler, "Load the `kos` scheduler"
    assert_includes brief_scheduler, "`brief` mode"

    [ scheduler, brief_scheduler ].each do |source|
      %w[intent.json task.json create.lock fsync inode].each { |detail| assert_not_includes source, detail }
    end
  end

  test "slash commands contain only argument handling model choice and skill entry" do
    commands = {
      "kos" => [ "openai/gpt-5.6-terra", "`kos` scheduler skill", "`development` mode" ],
      "kos-fix" => [ "openai/gpt-5.6-terra", "`kos` scheduler skill", "`fix` mode" ],
      "kos-brief" => [ "openai/gpt-5.6-sol", "`kos-brief` scheduler skill", "unmodified arguments" ]
    }

    commands.each do |name, (model, skill_entry, mode)|
      path = Rails.root.join(".opencode/commands/#{name}.md")
      source = File.read(path)
      metadata = frontmatter(path)
      body = source.sub(/\A---\n.*?\n---\n/m, "")

      assert_equal "build", metadata.fetch("agent")
      assert_equal model, metadata.fetch("model")
      assert_includes source, skill_entry
      assert_includes source, mode
      assert_includes source, "$ARGUMENTS"
      refute_match(/task (?:context|claim|resume|create-or-get)|owner|profile|outcome/i, body)
      assert_operator body.lines.length, :<=, 8
    end
  end

  test "scheduler dispatches built-ins by exact step with an ID-only prompt" do
    source = File.read(ORCHESTRATOR_PATH)
    compact = source.gsub(/\s+/, " ")

    BUILT_IN_PROFILES.each do |step|
      assert_match(/^\| `#{step}` \| `kos-#{step}` \|$/, source)
    end
    assert_includes compact, "one fresh foreground child whose complete prompt is only the task ID"
    assert_includes compact, "Ignore the child's text and claimed result, then reread context"
    assert_includes source, "Stop successfully on `completed`"
    assert_includes source, "On `needs_human` or `blocked`"
    assert_includes source, "unknown custom step"
    assert_includes source, "authoritative tier"
  end

  test "schedulers generate private command owners instead of requiring environment configuration" do
    scheduler = File.read(ORCHESTRATOR_PATH)
    brief_scheduler = File.read(Rails.root.join("skills/kos-brief/SKILL.md"))

    [ scheduler, brief_scheduler ].each do |source|
      assert_not_includes source, "PID"
    end
    assert_includes scheduler, "fresh unpredictable `kos-session-<32 lowercase hex digits>` owner"
    assert_includes scheduler, "Never read `KOS_OWNER_ID`"
    assert_includes scheduler, "Do not access\nRails, SQLite, the REST API"
    assert_operator brief_scheduler.lines.length, :<=, 12
  end

  test "scheduler has no step artifact Git or result-parsing policy" do
    source = File.read(ORCHESTRATOR_PATH)

    assert_includes source, "Never add task context to the child prompt"
    assert_includes source, "inspect task artifacts or Git"
    assert_includes source, "interpret child output"
    assert_includes source, "report a step"
    assert_includes source, "keep local\nrecovery state"
    assert_not_includes source, "<step-id>.md"
    assert_not_includes source, '"outcome"'
    assert_not_includes source, "git status"
    assert_not_includes source, "immutable pre-verification snapshot"
  end

  test "step guidance keeps the lifecycle concise and leaves validation to the server" do
    source = File.read(STEP_PATH)
    body = source.sub(/\A---\n.*?\n---\n/m, "")

    assert_includes source, "Accept one positive ASCII-decimal task ID"
    assert_includes source, "read the authoritative\ntask context"
    assert_includes source, "Load `kos-git` with the\ntask ID"
    assert_includes source, "using normal repository tools within the profile's\nboundary"
    assert_includes source, "server is authoritative\nfor ownership, fencing, outcomes, and atomic artifact acceptance"
    assert_includes source, "observe task state before any retry"
    assert_includes source, "Do not execute the next step"
    assert_operator body.lines.length, :<=, 36
    refute_match(/--owner-id|--claim-version|--artifact-file|report-attempt/, source)
  end

  test "CLI skill delegates syntax to help and retains essential safety boundaries" do
    source = File.read(CLI_PATH)

    %w[KOS_CLI_PATH KOS_API_URL KOS_API_TOKEN --version --help].each do |contract|
      assert_includes source, contract
    end
    assert_match(/help/i, source)
    assert_match(/standard input|stdin/i, source)
    assert_match(/repository identity/i, source)
    assert_match(/retry/i, source)
    assert_match(/authorization|fencing/i, source)
    (0..3).each { |status| assert_match(/Exit `#{status}`/, source) }

    refute_match(/task context ID/, source)
    refute_match(/task artifact ID --step/, source)
    refute_match(/task report-attempt ID --owner-id/, source)
  end

  test "profiles preserve role and model metadata without permission policy" do
    agents = AGENT_PATHS.transform_values { |path| frontmatter(path) }
    standard = %w[kos-implement kos-document kos-publish kos-step-standard]

    AGENT_PATHS.each do |name, path|
      profile = agents.fetch(name)
      source = File.read(path)

      assert_equal %w[description mode model reasoningEffort], profile.keys.sort
      assert_predicate profile.fetch("description"), :present?
      assert_equal "subagent", profile.fetch("mode")
      if standard.include?(name)
        assert_equal [ "openai/gpt-5.6-terra", "medium" ], profile.values_at("model", "reasoningEffort"), name
      else
        assert_equal [ "openai/gpt-5.6-sol", "high" ], profile.values_at("model", "reasoningEffort"), name
      end
      refute profile.key?("permission"), name
      assert_includes source, "prompt is only the task ID"
      body = source.sub(/\A---\n.*?\n---\n/m, "")
      assert_operator body.lines.length, :<=, 10, name
    end
  end

  test "profiles retain operational role boundaries" do
    assert_includes File.read(AGENT_PATHS.fetch("kos-publish")), "This profile alone may"
    assert_includes File.read(AGENT_PATHS.fetch("kos-publish")), "immutable pre-verification built-in snapshot"
    implement = File.read(AGENT_PATHS.fetch("kos-implement"))
    assert_includes implement.gsub(/\s+/, " "), "Run every required test, lint, formatting, build, and type check"
    assert_includes implement, "structured required-check result"
    assert_includes implement, "Keep all changes uncommitted"
    assert_includes File.read(AGENT_PATHS.fetch("kos-review")), "required-check evidence"
    publish = File.read(AGENT_PATHS.fetch("kos-publish"))
    assert_includes publish, "required-check evidence"
    assert_includes publish.gsub(/\s+/, " "), "validate its exact graph before commit or push"
    assert_includes File.read(AGENT_PATHS.fetch("kos-verify")), "required-check evidence"
    assert_includes File.read(AGENT_PATHS.fetch("kos-document")).gsub(/\s+/, " "), "Do not commit or push"
    assert_includes File.read(AGENT_PATHS.fetch("kos-brief")).gsub(/\s+/, " "), "Do not commit, push"
    assert_includes File.read(AGENT_PATHS.fetch("kos-step-standard")), "without commit or push"
    assert_includes File.read(AGENT_PATHS.fetch("kos-step-advanced")), "without commit or push"
    diagnose = File.read(AGENT_PATHS.fetch("kos-diagnose"))
    assert_includes diagnose, "exported temporary copy"
    assert_includes diagnose, "isolated environment"
    assert_includes diagnose, "no ambient secrets"
  end

  test "review verify plan and diagnose profiles are read-only" do
    %w[kos-diagnose kos-plan kos-review kos-verify].each do |name|
      source = File.read(AGENT_PATHS.fetch(name))

      assert_match(/unchanged|without changing|without changing the repository/, source, name)
    end
    verify = File.read(AGENT_PATHS.fetch("kos-verify"))
    assert_includes verify.gsub(/\s+/, " "), "Only `verified` may complete"
  end

  test "verification independently observes remote publication" do
    source = File.read(AGENT_PATHS.fetch("kos-verify"))

    assert_includes source, "Independently verify"
    assert_includes source, "remote"
    assert_includes source, "without changing\nthe repository"
    assert_includes source, "without changing\nthe repository or trusting publication prose"
  end

  private

  def assert_skill(path, name, description_pattern)
    source = File.read(path)
    metadata = YAML.safe_load(source.match(/\A---\n(.*?)\n---/m)[1])
    assert_equal name, metadata.fetch("name")
    assert_match description_pattern, metadata.fetch("description")
    assert_equal [ "SKILL.md" ], Dir.children(path.dirname).sort
  end

  def frontmatter(path)
    YAML.safe_load(File.read(path).match(/\A---\n(.*?)\n---/m)[1])
  end
end
