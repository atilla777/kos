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

  test "request creation uses one server-idempotent CLI operation without local state" do
    scheduler = File.read(ORCHESTRATOR_PATH)
    brief_scheduler = File.read(Rails.root.join("skills/kos-brief/SKILL.md"))

    [ scheduler, brief_scheduler ].each do |source|
      assert_match(/`task\s+create-or-get`/, source)
      assert_includes source, "complete exact request through standard input"
      assert_includes source, "retry that identical operation once"
      assert_match(/server-derived\s+creation key/, source)
      assert_not_includes source, "intent.json"
      assert_not_includes source, "task.json"
      assert_not_includes source, "create.lock"
      assert_not_includes source, "fsync"
      assert_not_includes source, "inode"
    end
    assert_includes scheduler, "never use the repeated problem text as its answer"
    assert_includes scheduler, "`--takeover-confirmed`"
    assert_includes brief_scheduler, "`--takeover-confirmed`"
  end

  test "slash commands retain input safety and delegate only to schedulers" do
    command = File.read(Rails.root.join(".opencode/commands/kos.md"))
    fix = File.read(Rails.root.join(".opencode/commands/kos-fix.md"))
    brief = File.read(Rails.root.join(".opencode/commands/kos-brief.md"))

    assert_includes command, "`kos` scheduler skill"
    assert_includes command, "accepts no arguments"
    assert_includes command, "stop without reading or mutating KOS state"
    assert_includes fix, "`kos` scheduler skill"
    assert_includes fix, "If it is blank"
    assert_includes brief, "`kos-brief` scheduler skill"
    assert_includes brief, "If it is blank"
  end

  test "scheduler dispatches built-ins by exact step with an ID-only prompt" do
    source = File.read(ORCHESTRATOR_PATH)
    compact = source.gsub(/\s+/, " ")

    BUILT_IN_PROFILES.each do |step|
      assert_match(/^\| `#{step}` \| `kos-#{step}` \|$/, source)
    end
    assert_includes source, "complete prompt is the task\n   ID's decimal digits and nothing else"
    assert_includes source, "discard all dispatch context except that ID"
    assert_includes source, "ignore all textual output and claimed outcome"
    assert_includes source, "reread authoritative state"
    assert_includes source, "persisted server question"
    assert_includes source, "persisted server reason"
    assert_includes source, "immutable pre-verification snapshot"
    assert_includes source, "never treat it as\n   publication-capable"

    %w[description workflow outcome model tier path project ID diff Git fact artifact].each do |forbidden|
      assert_match(/must not contain .*#{forbidden}/, compact)
    end
  end

  test "schedulers generate private command owners instead of requiring environment configuration" do
    scheduler = File.read(ORCHESTRATOR_PATH)
    brief_scheduler = File.read(Rails.root.join("skills/kos-brief/SKILL.md"))

    [ scheduler, brief_scheduler ].each do |source|
      assert_includes source, "cryptographically unpredictable owner ID"
      assert_includes source, "Never read `KOS_OWNER_ID`"
    end
    assert_includes scheduler, "claim the next available development task with the generated\nowner"
    assert_includes brief_scheduler, "uses this same owner for `task\ncreate-or-get`"
  end

  test "scheduler has no step artifact Git or result-parsing policy" do
    source = File.read(ORCHESTRATOR_PATH)

    assert_includes source, "Do not read or validate Markdown"
    assert_includes source, "inspect Git"
    assert_includes source, "parse child\nresults"
    assert_includes source, "call `report-attempt`"
    assert_includes source, "pending submissions"
    assert_not_includes source, "<step-id>.md"
    assert_not_includes source, '"outcome"'
    assert_not_includes source, "git status"
  end

  test "step executor derives context and atomically reports Markdown itself" do
    source = File.read(STEP_PATH)

    assert_includes source, "Accept exactly one positive ASCII-decimal task ID and no other"
    assert_includes source, "`task context ID`"
    assert_includes source, "Fetch each needed accepted predecessor artifact separately"
    assert_includes source, "`task artifact` operation"
    assert_includes source, "Load `kos-git` with only the task ID"
    assert_includes source, "Re-read `task context ID` immediately before reporting"
    assert_includes source, "invoke `task report-attempt` itself"
    assert_includes source, "`--artifact-file -` standard-input form"
    assert_includes source, "server atomically accepts the artifact and\ntransition"
    assert_includes source, "minimal non-authoritative statement"
    assert_includes source, "never read a local task artifact"
    assert_includes source, "never read a local task artifact,\nsidecar, manifest, receipt, or pending submission"
    assert_includes source, "Do not return an outcome for the scheduler to parse"
    assert_includes source, "immutable pre-verification built-in snapshot"
    assert_includes source, "cancelled and recreated from the current built-in\ncatalog after its work is preserved"
    assert_includes source, "Do not publish, materialize, import,\nrepoint"
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
    end
  end

  test "profiles retain operational role boundaries" do
    assert_includes File.read(AGENT_PATHS.fetch("kos-publish")), "this profile alone may"
    assert_includes File.read(AGENT_PATHS.fetch("kos-publish")), "immutable\npre-verification snapshot"
    assert_includes File.read(AGENT_PATHS.fetch("kos-implement")), "every required\ntest, lint, formatting, build, and type check"
    assert_includes File.read(AGENT_PATHS.fetch("kos-implement")), "Keep all changes uncommitted"
    assert_includes File.read(AGENT_PATHS.fetch("kos-document")), "Do\nnot commit or push"
    assert_includes File.read(AGENT_PATHS.fetch("kos-brief")), "Do not commit, push"
    assert_includes File.read(AGENT_PATHS.fetch("kos-step-standard")), "without commit or push"
    assert_includes File.read(AGENT_PATHS.fetch("kos-step-advanced")), "without commit or push"
    diagnose = File.read(AGENT_PATHS.fetch("kos-diagnose"))
    assert_includes diagnose, "`git archive | tar`"
    assert_includes diagnose, "temporary copy's `bin/*` commands through `env -i`"
    assert_includes diagnose, "Never\nexecute repository-controlled code from the task worktree"
    assert_includes diagnose, "`mktemp -d ...kos-task-...` command"
    assert_match(/Never generate or\nrequest a Ruby, Python, Open3/, diagnose)
  end

  test "review verify plan and diagnose profiles are read-only" do
    %w[kos-diagnose kos-plan kos-review kos-verify].each do |name|
      source = File.read(AGENT_PATHS.fetch(name))

      assert_match(/unchanged|read-only/, source, name)
    end
    assert_includes File.read(AGENT_PATHS.fetch("kos-verify")), "Only `verified` may complete"
  end

  test "verification independently observes remote publication" do
    source = File.read(AGENT_PATHS.fetch("kos-verify"))

    assert_includes source, "Independently use `kos-git`"
    assert_includes source, "remote"
    assert_includes source, "Never trust publication prose"
    assert_includes source, "keep HEAD"
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
