require "test_helper"
require "yaml"

class KosBriefSkillTest < ActiveSupport::TestCase
  SKILL_PATH = Rails.root.join("skills/kos-brief/SKILL.md")

  test "brief is a thin adapter to the shared scheduler" do
    source = File.read(SKILL_PATH)
    metadata = YAML.safe_load(source.match(/\A---\n(.*?)\n---/m)[1])

    assert_equal "kos-brief", metadata.fetch("name")
    assert_includes source, "Load the `kos` scheduler"
    assert_includes source, "`brief` mode"
    assert_includes source, "request unchanged"
    assert_includes source, "Do not execute a workflow\nstep in this agent"
    assert_includes source, "fresh `kos-brief` profile"
    assert_operator source.lines.length, :<=, 12
  end

  test "brief adapter does not duplicate lifecycle or filesystem policy" do
    source = File.read(SKILL_PATH)

    refute_match(/task (?:context|resume|create-or-get|report-attempt)/, source)
    refute_match(/^\| .* \| .* \|$/, source)
    %w[brief.md brief-graph.json materialize-children takeover-confirmed].each do |detail|
      assert_not_includes source, detail
    end
  end
end
