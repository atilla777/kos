require "test_helper"
require "yaml"

class KosBriefSkillTest < ActiveSupport::TestCase
  SKILL_PATH = Rails.root.join("skills/kos-brief/SKILL.md")
  COMMAND_PATH = Rails.root.join(".opencode/commands/kos-brief.md")

  test "exposes a main-agent brief command and discoverable skill" do
    command = File.read(COMMAND_PATH)
    command_frontmatter = frontmatter(command)
    skill = File.read(SKILL_PATH)
    skill_frontmatter = frontmatter(skill)

    assert_match(/Specify and publish/, command_frontmatter.fetch("description"))
    assert_equal "build", command_frontmatter.fetch("agent")
    assert_includes command, "Load the `kos` and `kos-brief` skills"
    assert_includes command, "$ARGUMENTS"
    assert_includes command, "stop\nwithout reading or mutating KOS state"

    assert_equal "kos-brief", skill_frontmatter.fetch("name")
    assert_match(/user invokes \/kos-brief/, skill_frontmatter.fetch("description"))
    assert_equal [ "SKILL.md" ], Dir.children(SKILL_PATH.dirname).sort
  end

  test "defines durable brief creation and restart-safe clarification" do
    source = File.read(SKILL_PATH)

    assert_includes source, "stable built-in key `brief`"
    assert_includes source, "brief-<request-digest>.json"
    assert_includes source, "brief-<request-digest>-task.json"
    assert_includes source, "brief-<request-digest>.lock/"
    assert_includes source, "non-replacing atomic intent and receipt publication"
    assert_includes source, "owner-idempotent `create-and-claim`"
    assert_includes source, "Never create a second task"
    assert_includes source, "completed brief is a permanent"
    assert_includes source, "never\ndelete the receipt or create another brief"
    assert_includes source, "--task-type-key\nbrief"
    assert_includes source, "<step-id>-answer.md"
    assert_includes source, "survive another interruption"
  end

  test "keeps specification work in the main agent and independently reviews it" do
    source = File.read(SKILL_PATH)

    assert_includes source, "exact step ID `brief` must run in this main"
    assert_includes source, "Do not delegate it to `kos-step`"
    assert_includes source, "Use `okf`"
    %w[goal actors errors security compatibility migration observability non-goals].each do |concern|
      assert_match(/\b#{concern}\b/i, source)
    end
    assert_includes source, "materially change product"
    assert_includes source, "do not\nrequire an approval pause"
    assert_includes source, "advanced `kos-review` profile"
    assert_includes source, "different from this main agent"
    assert_includes source, "brief-graph-reviewed.json"
    assert_includes source, "brief-spec-reviewed.json"
    assert_includes source, "standalone scopes and acceptance criteria"
    assert_includes source, "repository-relative link"
    assert_includes source, "byte-for-byte equality with `brief-spec-reviewed.json`"
    assert_includes source, "same-path status remaining unchanged is not proof"
    assert_includes source, "tracked,\nstaged, untracked, newly created, and binary specification files"
    assert_includes source, "standard padded Base64"
    assert_includes source, '"path": path, "content_base64": Base64.strict_encode64(bytes)'
    assert_includes source, 'top-level `{"files": entries}` with Ruby `JSON.generate`'
    assert_includes source, "Use Ruby's exact JSON\nstring escaping and emit no trailing LF"
  end

  test "binds reviewed bytes before publication and materialization" do
    source = File.read(SKILL_PATH)
    byte_check = source.index("Require their bytes to\nbe identical")
    validation = source.index("task validate-children")
    publication = source.index("launch one fresh standard `kos-publish` agent")
    materialization = source.index("task materialize-children")

    assert byte_check
    assert validation
    assert publication
    assert materialization
    assert_operator byte_check, :<, validation
    assert_operator validation, :<, publication
    assert_operator publication, :<, materialization
    assert_match(/do not invoke\s+`materialize-children` and do not publish/, source)
    assert_includes source, "Never materialize children before publication is observed remotely"
    assert_includes source, "publisher may commit and push the bound change"
    assert_includes source, "publisher may commit and push the bound change and atomically write `publish.md`;\nit must never call a KOS graph command"
    assert_includes source, "byte mismatch after push is a technical"
    assert_includes source, "do not use `graph_invalid` for an already published specification"
    assert_includes source, "SHA-256 of the exact reviewed specification manifest bytes"
    assert_includes source, "brief-graph-validation.json"
    assert_includes source, "no in-memory value from the prior process is\nrequired"
    assert_includes source, "candidate commit's complete `specs/` tree"
  end

  test "recovers graph creation and completion by observation" do
    source = File.read(SKILL_PATH)

    assert_includes source, "Never blindly repeat it"
    assert_includes source, "task children <task-id>"
    assert_includes source, "An exact complete match proves materialization succeeded once"
    assert_includes source, "one identical retry is safe"
    assert_includes source, "partial graph, different digest"
    assert_includes source, "Only after exact materialization is observed"
    assert_includes source, "proving completed status, released ownership"
    assert_includes source, "Children must remain pending and blocked"
    assert_includes source, "never repeat materialization or create another commit"
    assert_includes source, "resumed publish step already has an exact complete child graph"
    assert_includes source, "proceed directly to reporting\n`published`"
    assert_includes source, "After a process restart, recover those values only"
    assert_includes source, "continue directly to one materialization attempt"
    assert_includes source, "Do not\nrepublish or require the now-clean worktree"
    assert_includes source, "publisher crashed after push but before writing `publish.md`"
    assert_includes source, "atomically writes that artifact from the observed commit"
  end

  test "documented global installation includes the brief integration" do
    readme = File.read(Rails.root.join("README.md"))
    installer = File.read(Rails.root.join("bin/install-opencode"))

    assert_includes readme, "bin/install-opencode"
    assert_includes installer, "kos-brief"
  end

  private

  def frontmatter(source)
    match = source.match(/\A---\n(.*?)\n---/m)
    assert match
    YAML.safe_load(match[1])
  end
end
