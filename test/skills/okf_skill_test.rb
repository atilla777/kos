require "test_helper"
require "tmpdir"
require "yaml"

class OkfSkillTest < ActiveSupport::TestCase
  SKILL_PATH = Rails.root.join("skills/okf/SKILL.md")
  BUNDLE_PATH = Rails.root.join("specs")

  test "is a discoverable distributable OpenCode skill" do
    source = File.read(SKILL_PATH)
    match = source.match(/\A---\n(.*?)\n---/m)

    assert match
    frontmatter = YAML.safe_load(match[1])
    assert_equal "okf", frontmatter.fetch("name")
    assert_match(/product behavior specifications/, frontmatter.fetch("description"))
    assert_equal [ "SKILL.md" ], Dir.children(SKILL_PATH.dirname).sort
  end

  test "defines the confined preservation and evidence contract" do
    source = File.read(SKILL_PATH)
    compact_source = source.gsub(/\s+/, " ")

    [
      "Boundary", "Read Progressively", "Find Affected Concepts", "Conformance",
      "Product Specification Shape", "Evidence And Uncertainty", "Verify"
    ].each { |heading| assert_match(/^## #{Regexp.escape(heading)}$/, source) }

    assert_includes compact_source, "read or write only paths below that directory"
    assert_includes compact_source, "Refuse a symlinked bundle root"
    assert_includes compact_source, "Its only universally required field is a nonempty string `type`"
    assert_includes compact_source, "Lifecycle fields"
    assert_includes compact_source, "optional and must never be invented"
    assert_includes compact_source, "Preserve every unknown field"
    assert_includes compact_source, "all unrelated body content"
    assert_includes compact_source, "Read `specs/index.md` first"
    assert_includes compact_source, "Keep each affected directory index accurate"
    assert_includes compact_source, "Prefer bundle-relative links"
    assert_includes compact_source, "Do not duplicate"
    assert_includes compact_source, "Never infer a product requirement solely"
    assert_includes compact_source, "without evidence"
  end

  test "ships a conformant progressively disclosed KOS product bundle" do
    root_index = File.read(BUNDLE_PATH.join("index.md"))
    index_match = root_index.match(/\A---\n(.*?)\n---\n/m)

    assert index_match
    assert_equal({ "okf_version" => "0.2" }, YAML.safe_load(index_match[1]))

    concept_paths = Dir.glob(BUNDLE_PATH.join("**/*.md")).reject do |path|
      %w[index.md log.md].include?(File.basename(path))
    end
    assert_equal [ BUNDLE_PATH.join("kos.md").to_s ], concept_paths

    concept_paths.each do |path|
      match = File.read(path).match(/\A---\n(.*?)\n---\n/m)
      assert match, "#{path} must start with YAML frontmatter"

      type = YAML.safe_load(match[1]).fetch("type")
      assert type.is_a?(String) && type.strip.present?, "#{path} must have a nonempty string type"
    end

    concept = File.read(BUNDLE_PATH.join("kos.md"))
    metadata = YAML.safe_load(concept.match(/\A---\n(.*?)\n---\n/m)[1])
    assert_equal "Product Specification", metadata.fetch("type")
    assert_not_includes metadata, "status"
    %w[Goal Actors User\ Scenarios Rules Errors Edge\ Cases Acceptance\ Criteria Non-goals].each do |heading|
      assert_match(/^# #{Regexp.escape(heading)}$/, concept)
    end
  end

  test "bundle links resolve and the root index describes every root concept" do
    markdown_paths = Dir.glob(BUNDLE_PATH.join("**/*.md"))

    markdown_paths.each do |path|
      File.read(path).scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |target|
        next if target.match?(/\A[a-z][a-z0-9+.-]*:/i)

        resolved = if target.start_with?("/")
          BUNDLE_PATH.join(target.delete_prefix("/"))
        else
          Pathname(path).dirname.join(target)
        end
        assert resolved.exist?, "#{path} links to missing #{target}"
      end
    end

    index = File.read(BUNDLE_PATH.join("index.md"))
    root_concepts = Dir.glob(BUNDLE_PATH.join("*.md")).reject do |path|
      %w[index.md log.md].include?(File.basename(path))
    end
    root_concepts.each do |path|
      metadata = YAML.safe_load(File.read(path).match(/\A---\n(.*?)\n---\n/m)[1])
      expected = "[#{metadata.fetch("title")}](#{File.basename(path)}) - #{metadata.fetch("description")}"
      assert_includes index, expected
    end
  end

  test "contract update in a temporary worktree preserves unrelated knowledge and confinement" do
    Dir.mktmpdir("okf-skill-contract") do |directory|
      worktree = Pathname(directory)
      specs = worktree.join("specs")
      journeys = specs.join("journeys")
      docs = worktree.join("docs")
      journeys.mkpath
      docs.mkpath

      specs.join("index.md").write(<<~MARKDOWN)
        ---
        okf_version: "0.2"
        ---

        # Product Specifications

        - [Journeys](journeys/) - User journeys.
      MARKDOWN
      journeys.join("index.md").write(<<~MARKDOWN)
        # User Journeys

        - [Checkout](checkout.md) - Existing checkout behavior.
        - [Returns](returns.md) - Return behavior that refers to checkout.
      MARKDOWN
      checkout = journeys.join("checkout.md")
      checkout.write(<<~MARKDOWN)
        ---
        type: Product Specification
        title: Checkout
        description: Existing checkout behavior.
        vendor_extension:
          owner: payments
        ---

        # Rules

        Payment is collected once.

        # Unrelated Appendix

        Preserve this exact operational note.
      MARKDOWN
      journeys.join("returns.md").write(<<~MARKDOWN)
        ---
        type: Product Specification
        title: Returns
        description: Return behavior that refers to checkout.
        ---

        Returns link to the [checkout rules](/journeys/checkout.md).
      MARKDOWN
      architecture = docs.join("architecture.md")
      architecture.write("Technical boundary remains outside specs.\n")

      original_metadata = concept_metadata(checkout)
      original_appendix = checkout.read[/# Unrelated Appendix\n\n.*\z/m]
      original_architecture = architecture.read

      checkout.write(checkout.read.sub("Payment is collected once.", "Payment is collected exactly once after confirmation."))
      journeys.join("index.md").write(journeys.join("index.md").read.sub(
        "Existing checkout behavior.", "Checkout collects payment after confirmation."
      ))

      assert_equal original_metadata.fetch("vendor_extension"), concept_metadata(checkout).fetch("vendor_extension")
      assert_equal original_appendix, checkout.read[/# Unrelated Appendix\n\n.*\z/m]
      assert_equal original_architecture, architecture.read
      assert_includes journeys.join("index.md").read, "Checkout collects payment after confirmation."
      assert_includes journeys.join("returns.md").read, "](/journeys/checkout.md)"
      assert_equal %w[journeys/checkout.md journeys/returns.md], concept_paths(specs)
      assert_bundle_links_resolve(specs)
    end
  end

  test "skill contract rejects paths that can escape the temporary worktree bundle" do
    source = File.read(SKILL_PATH).gsub(/\s+/, " ")

    Dir.mktmpdir("okf-skill-boundary") do |directory|
      worktree = Pathname(directory)
      worktree.join("specs").mkpath
      worktree.join("outside.md").write("outside\n")
      worktree.join("specs/escape.md").make_symlink(worktree.join("outside.md"))

      assert worktree.join("specs/escape.md").symlink?
      assert_includes source, "Refuse a symlinked bundle root, a path that escapes the bundle"
      assert_includes source, "read or write only paths below that directory"
    end
  end

  private

  def concept_metadata(path)
    YAML.safe_load(path.read.match(/\A---\n(.*?)\n---\n/m)[1])
  end

  def concept_paths(bundle)
    Dir.glob(bundle.join("**/*.md")).filter_map do |path|
      next if %w[index.md log.md].include?(File.basename(path))

      Pathname(path).relative_path_from(bundle).to_s
    end.sort
  end

  def assert_bundle_links_resolve(bundle)
    Dir.glob(bundle.join("**/*.md")).each do |path|
      File.read(path).scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |target|
        resolved = if target.start_with?("/")
          bundle.join(target.delete_prefix("/"))
        else
          Pathname(path).dirname.join(target)
        end
        assert resolved.exist?, "#{path} links to missing #{target}"
      end
    end
  end
end
