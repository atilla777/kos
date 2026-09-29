require "minitest/autorun"
require_relative "../lib/kos_cli/repository"

class RepositoryTest < Minitest::Test
  def test_normalizes_equivalent_github_remotes
    expected = "github.com/owner/project"

    assert_equal expected, KosCli::Repository.normalize("git@github.com:Owner/Project.git")
    assert_equal expected, KosCli::Repository.normalize("https://github.com/owner/project.git")
    assert_equal expected, KosCli::Repository.normalize("ssh://git@github.com/owner/project.git")
  end

  def test_removes_credentials_without_exposing_them
    assert_equal "example.com/Team/Project", KosCli::Repository.normalize("https://secret@example.com/Team/Project.git")
  end

  def test_preserves_path_case_for_other_hosts
    assert_equal "git.example.com/Team/Project", KosCli::Repository.normalize("git@git.example.com:Team/Project.git")
  end

  def test_rejects_unsupported_values_without_repeating_them
    error = assert_raises(KosCli::RepositoryError) do
      KosCli::Repository.normalize("file:///secret/project.git")
    end

    refute_includes error.message, "secret"
  end
end
