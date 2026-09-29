require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "requires a canonical unique repository" do
    Project.create!(name: "KOS", repository: "github.com/atilla777/kos")

    duplicate = Project.new(name: "Other", repository: "github.com/atilla777/kos")
    invalid = Project.new(name: "Other", repository: "https://github.com/atilla777/other")

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:repository, :taken)
    assert_not invalid.valid?
    assert invalid.errors.of_kind?(:repository, :invalid)
  end

  test "canonicalizes host and GitHub repository casing before uniqueness checks" do
    project = Project.create!(name: "KOS", repository: "GitHub.com/Atilla777/KOS.git")
    duplicate = Project.new(name: "Duplicate", repository: "github.com/atilla777/kos")

    assert_equal "github.com/atilla777/kos", project.repository
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:repository, :taken)
  end

  test "preserves path casing on other Git hosts" do
    project = Project.create!(name: "KOS", repository: "Git.Example.com/Team/KOS.git")

    assert_equal "git.example.com/Team/KOS", project.repository
  end
end
