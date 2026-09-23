require "test_helper"

class RepositoryIdentityTest < ActiveSupport::TestCase
  test "normalizes equivalent HTTPS and SSH repository URLs" do
    expected = "github.com/atilla777/kos"

    [
      "https://GitHub.com/atilla777/kos.git",
      "ssh://git@github.com/atilla777/kos.git",
      "git@github.com:atilla777/kos.git"
    ].each do |url|
      assert_equal expected, RepositoryIdentity.normalize(url)
    end
  end

  test "rejects local credentialed malformed and incomplete URLs" do
    [
      "/tmp/kos",
      "file:///tmp/kos",
      "https://user@github.com/a/kos",
      "ssh://git:secret@github.com/a/kos",
      "ssh://other@github.com/a/kos",
      "git@github.com:a/kos extra",
      "https://github.com/kos",
      "https://github.com/a/kos?x=1",
      "https://github.com/a/%2e%2e/kos",
      "https://git..example.com/a/kos"
    ].each do |url|
      assert_raises(RepositoryIdentity::Invalid, url) { RepositoryIdentity.normalize(url) }
    end
  end

  test "rejects ambiguous leading slashes instead of normalizing them" do
    [
      "git@github.com:/atilla777/kos.git",
      "ssh://git@github.com//atilla777/kos.git",
      "https://github.com//atilla777/kos.git"
    ].each do |url|
      assert_raises(RepositoryIdentity::Invalid, url) { RepositoryIdentity.normalize(url) }
    end
  end

  test "rejects explicit HTTPS and SSH ports" do
    [
      "https://github.com:443/atilla777/kos.git",
      "https://github.com:8443/atilla777/kos.git",
      "https://github.com:/atilla777/kos.git",
      "ssh://git@github.com:22/atilla777/kos.git",
      "ssh://git@github.com:/atilla777/kos.git"
    ].each do |url|
      assert_raises(RepositoryIdentity::Invalid, url) { RepositoryIdentity.normalize(url) }
    end
  end

  test "project identity must exactly match its remote" do
    project = Project.new(name: "KOS", remote_url: "https://github.com/atilla777/kos.git",
      repository_identity: "github.com/other/kos", default_branch: "main")

    assert_not project.valid?
    assert_includes project.errors[:repository_identity], "must match remote URL"
  end

  test "requires a nonblank valid Git default branch" do
    [
      "", "bad branch", "topic..next", "topic.lock", "-topic", ".topic", "topic@{old}",
      "/topic", "topic/", "topic//next"
    ].each do |branch|
      project = Project.new(name: "KOS", remote_url: "https://github.com/atilla777/kos.git",
        repository_identity: "github.com/atilla777/kos", default_branch: branch)

      assert_not project.valid?, branch
      assert project.errors[:default_branch].present?, branch
    end

    project = Project.new(name: "KOS", remote_url: "https://github.com/atilla777/kos.git",
      repository_identity: "github.com/atilla777/kos", default_branch: "release/2026.09")
    assert_predicate project, :valid?
  end
end
