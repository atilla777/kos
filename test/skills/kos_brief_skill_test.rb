require "test_helper"
require "yaml"

class KosBriefSkillTest < ActiveSupport::TestCase
  SKILL_PATH = Rails.root.join("skills/kos-brief/SKILL.md")

  test "brief is an ID-only scheduler with a fresh brief authority" do
    source = File.read(SKILL_PATH)
    metadata = YAML.safe_load(source.match(/\A---\n(.*?)\n---/m)[1])

    assert_equal "kos-brief", metadata.fetch("name")
    assert_includes source, "never execute a workflow\nstep in the main agent"
    assert_includes source, "`brief` is now performed by a fresh\n`kos-brief` profile"
    %w[brief review publish verify].each do |step|
      assert_match(/^\| `#{step}` \| `kos-#{step}` \|$/, source)
    end
    assert_includes source, "complete prompt is only the task ID"
    assert_includes source, "ignore its textual\nresponse and claimed result"
    assert_includes source, "persisted server question or reason"
    assert_includes source, "immutable pre-verification snapshot"
    assert_includes source, "must not publish or materialize children"
  end

  test "brief uses server-idempotent creation but has no step filesystem protocol" do
    source = File.read(SKILL_PATH)
    compact = source.gsub(/\s+/, " ")

    assert_includes source, "`task\ncreate-or-get`"
    assert_includes source, "retry that identical operation once"
    assert_includes source, "without local recovery files"
    assert_includes source, "positive ASCII-decimal ID"
    assert_includes source, "does not\nread or validate Markdown or graph files"
    assert_includes compact, "does not read or validate Markdown or graph files, inspect Git, parse outcomes, report"
    assert_not_includes source, "brief.md"
    assert_not_includes source, "brief-graph.json"
    assert_not_includes source, "materialize-children <task-id>"
  end
end
