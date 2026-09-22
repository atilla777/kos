require "test_helper"
require "json"
require "yaml"

class KosSkillsTest < ActiveSupport::TestCase
  ORCHESTRATOR_PATH = Rails.root.join("skills/kos/SKILL.md")
  STEP_PATH = Rails.root.join("skills/kos-step/SKILL.md")
  COMMAND_PATH = Rails.root.join(".opencode/commands/kos.md")
  AGENT_PATHS = {
    "kos-plan" => Rails.root.join(".opencode/agents/kos-plan.md"),
    "kos-step-standard" => Rails.root.join(".opencode/agents/kos-step-standard.md"),
    "kos-step-advanced" => Rails.root.join(".opencode/agents/kos-step-advanced.md"),
    "kos-review" => Rails.root.join(".opencode/agents/kos-review.md"),
    "kos-publish" => Rails.root.join(".opencode/agents/kos-publish.md")
  }.freeze

  test "defines discoverable orchestrator and step skills" do
    assert_skill ORCHESTRATOR_PATH, "kos", /user invokes \/kos/
    assert_skill STEP_PATH, "kos-step", /exactly one supplied step/
  end

  test "exposes the kos slash command and project skill path" do
    command = File.read(COMMAND_PATH)
    match = command.match(/\A---\n(.*?)\n---/m)

    assert match
    frontmatter = YAML.safe_load(match[1])
    assert_match(/development task/, frontmatter.fetch("description"))
    assert_equal "build", frontmatter.fetch("agent")
    assert_includes command, "Load the `kos` skill"
    assert_includes command, "$ARGUMENTS"
    assert_includes command, "accepts no arguments"
    assert_includes command, "stop without reading or mutating KOS state"
    assert_not Rails.root.join(".opencode/agents/kos-orchestrator.md").exist?

    config = JSON.parse(File.read(Rails.root.join("opencode.json")))
    assert_equal "https://opencode.ai/config.json", config.fetch("$schema")
    assert_equal [ "./skills" ], config.dig("skills", "paths")
  end

  test "defines tiered isolated step and read-only plan and review agent profiles" do
    agents = AGENT_PATHS.transform_values { |path| frontmatter(path) }

    assert_equal "subagent", agents.dig("kos-step-standard", "mode")
    assert_equal "openai/gpt-5.4-mini", agents.dig("kos-step-standard", "model")
    assert_equal "deny", agents.dig("kos-step-standard", "permission", "task")
    assert_equal "deny", agents.dig("kos-step-standard", "permission", "bash", "kos *")
    assert_nil agents.dig("kos-step-standard", "permission", "skill", "kos-git")
    assert_equal "allow", agents.dig("kos-step-standard", "permission", "skill", "okf")
    assert_equal "deny", agents.dig("kos-step-standard", "permission", "bash", "git *commit *")
    assert_equal "allow", agents.dig("kos-step-standard", "permission", "external_directory")
    assert_equal "openai/gpt-5.6-sol", agents.dig("kos-step-advanced", "model")
    assert_equal "subagent", agents.dig("kos-plan", "mode")
    assert_equal "openai/gpt-5.6-sol", agents.dig("kos-plan", "model")
    assert_equal "deny", agents.dig("kos-plan", "permission", "edit", "*")
    assert_equal "allow", agents.dig("kos-plan", "permission", "edit", "~/.local/share/kos/tasks/*/plan.md")
    assert_equal "allow", agents.dig("kos-plan", "permission", "edit", "~/.local/share/kos/tasks/*/.plan-*.tmp")
    assert_equal "deny", agents.dig("kos-plan", "permission", "bash")
    assert_equal "subagent", agents.dig("kos-review", "mode")
    assert_equal "openai/gpt-5.6-sol", agents.dig("kos-review", "model")
    assert_equal "deny", agents.dig("kos-review", "permission", "edit", "*")
    assert_equal "allow", agents.dig("kos-review", "permission", "edit", "~/.local/share/kos/tasks/*/review.md")
    assert_equal "allow", agents.dig("kos-review", "permission", "edit", "~/.local/share/kos/tasks/*/.review-*.tmp")
    assert_equal "deny", agents.dig("kos-review", "permission", "bash")
    assert_equal "allow", agents.dig("kos-review", "permission", "external_directory")
    assert_equal "subagent", agents.dig("kos-publish", "mode")
    assert_equal "openai/gpt-5.4-mini", agents.dig("kos-publish", "model")
    assert_equal "allow", agents.dig("kos-publish", "permission", "skill", "kos-git")
  end

  test "orchestrator defines the closed lifecycle and ownership protocol" do
    source = File.read(ORCHESTRATOR_PATH)

    [
      "Runtime Inputs", "Select Or Resume Development", "Preserve Human Answers", "Resolve Local Paths",
      "Run The Workflow", "Verify The Artifact First", "Report And Continue",
      "Recover A Lost Report Response", "Cancellation During Publication",
      "Stop Conditions"
    ].each { |heading| assert_match(/^## #{Regexp.escape(heading)}$/, source) }

    assert_includes source, "CLI as the only interface to KOS state"
    assert_includes source, "KOS_CLI_PATH"
    assert_includes source, "<kos-cli> --version"
    assert_includes source, "each needed task command's"
    assert_includes source, "`--help`"
    assert_includes source, "Never fall back to an ambient `kos` command"
    assert_includes source, "KOS_PROJECT_REMOTE_URL"
    assert_includes source, "KOS_PROJECT_DEFAULT_BRANCH"
    assert_not_includes source, "KOS_TASK_TYPE_ID"
    assert_includes source, "`/kos` accepts no task text and never creates a task"
    assert_includes source, "task resumable --project-id <project-id>"
    assert_includes source, "--task-type-key development"
    assert_match(/task\s+show-owned --project-id <project-id>/, source)
    assert_includes source, "never require the user to enter an internal ID"
    assert_includes source, "<step-id>-answer.md"
    assert_match(/Before `task resume`,\s+atomically write/, source)
    assert_match(/reuse\s+it without asking again/, source)
    assert_includes source, "takeover of an `active` task interrupted"
    assert_includes source, "when retrying a step with a current answer sidecar"
    assert_includes source, "After an accepted report or recovered report observably advances"
    assert_includes source, "Before every step, including the first"
    assert_includes source, "lease_expires_at"
    assert_includes source, "claim_version"
    assert_includes source, "launch exactly one fresh"
    assert_includes source, "only `review` is independent read-only review"
    assert_includes source, "only `publish` may commit"
    assert_includes source, "`kos-publish` agent"
    assert_includes source, "different agent"
    assert_includes source, "`kos-review` permission profile"
    assert_includes source, "the complete current diff"
    assert_includes source, "record HEAD and complete status immediately before dispatch"
    assert_includes source, "require HEAD to remain unchanged"
    assert_includes source, "<kos-data-home>/tasks/<task-id>/<step-id>.md"
    assert_includes source, "`kos-step-standard`"
    assert_includes source, "`kos-step-advanced`"
    assert_includes source, "`kos-plan` agent"
    assert_includes source, "The child, never the orchestrator or Rails"
    assert_includes source, "Only after the artifact is complete and verified"
    assert_match(/one\s+retry of the identical report is safe/, source)
    assert_includes source, "HTTP 5xx"
    assert_includes source, "already published"
    assert_includes source, "Never claim success before publication is"
  end

  test "step skill is isolated and returns one allowed result" do
    source = File.read(STEP_PATH)

    [
      "Accept One Context", "Authority Boundary", "Execute And Verify",
      "Read-Only Planning", "Independent Review", "Publication", "Persist The Artifact", "Return One Result"
    ].each { |heading| assert_match(/^## #{Regexp.escape(heading)}$/, source) }

    assert_includes source, "Never invoke `kos`"
    assert_includes source, "Work only inside the exact supplied worktree"
    assert_includes source, "Execute only this step"
    assert_includes source, "Do not commit before publication"
    assert_match(/Write only the\s+external `plan\.md` artifact/, source)
    assert_includes source, "remain read-only"
    assert_includes source, "material design error back to"
    assert_includes source, "Load and follow `kos-git`"
    assert_includes source, "exactly one outcome key"
    assert_includes source, '"outcome":"<exact allowed key>"'
    assert_not_includes source, '"artifact_markdown"'
    assert_includes source, "atomically replace only the exact supplied"
    assert_includes source, "different file identity"
    assert_includes source, "Write the observed publication facts"
  end

  private

  def assert_skill(path, name, description_pattern)
    source = File.read(path)
    match = source.match(/\A---\n(.*?)\n---/m)

    assert match
    frontmatter = YAML.safe_load(match[1])
    assert_equal name, frontmatter.fetch("name")
    assert_match description_pattern, frontmatter.fetch("description")
    assert_equal [ "SKILL.md" ], Dir.children(path.dirname).sort
  end

  def frontmatter(path)
    match = File.read(path).match(/\A---\n(.*?)\n---/m)

    assert match
    YAML.safe_load(match[1])
  end
end
