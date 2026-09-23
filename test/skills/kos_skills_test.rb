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
    assert_skill CLI_PATH, "kos-cli", /CLI discovery/

    config = JSON.parse(File.read(Rails.root.join("opencode.json")))
    assert_equal [ "./skills" ], config.dig("skills", "paths")
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

    %w[description workflow outcome model tier path project ID diff Git fact artifact].each do |forbidden|
      assert_match(/must not contain .*#{forbidden}/, compact)
    end
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
  end

  test "focused CLI skill validates context artifact and report operations" do
    source = File.read(CLI_PATH)
    compact = source.gsub(/\s+/, " ")

    assert_includes source, "absolute administrator-configured `KOS_CLI_PATH`"
    assert_includes source, "`task context ID`"
    assert_includes source, "`task artifact ID --step STEP`"
    assert_includes source, "`task report-attempt ID --owner-id OWNER --claim-version VERSION --step STEP"
    assert_includes compact, "atomically stored Markdown"
    assert_includes source, "Never blindly retry a mutation"
    assert_includes source, "Server authorization and fencing remain"
    assert_includes compact, "Do not emulate them with old `task show`, local artifact paths"
    assert_match(/^## Project Discovery$/, source)
    assert_includes source, "single `origin`\nfetch URL and single `origin` push URL"
    assert_includes source, "`project show\n--repository-identity IDENTITY`"
    assert_includes source, "equal `IDENTITY` byte-for-byte"
    assert_includes source, "stops before every task mutation"
  end

  test "profiles enforce exact authority and publish alone can commit or push" do
    agents = AGENT_PATHS.transform_values { |path| frontmatter(path) }

    AGENT_PATHS.each do |name, path|
      profile = agents.fetch(name)
      source = File.read(path)
      assert_equal "subagent", profile.fetch("mode")
      assert_equal "deny", profile.dig("permission", "task")
      assert_equal "allow", profile.dig("permission", "skill", "kos-step")
      assert_equal "allow", profile.dig("permission", "skill", "kos-cli")
      assert_includes source, "prompt is only the task ID"
      next if name == "kos-publish"

      assert_equal "deny", profile.dig("permission", "bash", "git *commit *"), name
      assert_equal "deny", profile.dig("permission", "bash", "git *push *"), name
    end

    assert_nil agents.dig("kos-publish", "permission", "bash", "git *commit *")
    assert_nil agents.dig("kos-publish", "permission", "bash", "git *push *")
    assert_includes File.read(AGENT_PATHS.fetch("kos-publish")), "this profile alone may"
    assert_includes File.read(AGENT_PATHS.fetch("kos-implement")), "every required\ntest, lint, formatting, build, and type check"
    assert_equal "allow", agents.dig("kos-document", "permission", "skill", "okf")
    assert_equal "allow", agents.dig("kos-brief", "permission", "skill", "okf")
  end

  test "review verify plan and diagnose profiles are read-only" do
    %w[kos-diagnose kos-plan kos-review kos-verify].each do |name|
      profile = frontmatter(AGENT_PATHS.fetch(name))
      source = File.read(AGENT_PATHS.fetch(name))

      assert_equal "deny", profile.dig("permission", "edit"), name
      assert_equal "deny", profile.dig("permission", "bash", "git *checkout *"), name
      assert_match(/unchanged|read-only/, source, name)
    end
    assert_includes File.read(AGENT_PATHS.fetch("kos-verify")), "Only `verified` may complete"
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
