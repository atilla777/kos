require "open3"
require "tmpdir"

module GitRepositoryHelpers
  def with_repository
    Dir.mktmpdir("kos-git") do |directory|
      root = Pathname(directory)
      remote = root.join("remote.git")
      seed = root.join("seed")
      source = root.join("source")
      publisher = root.join("publisher")

      git("init", "--bare", "--initial-branch=main", remote.to_s)
      git("init", "--initial-branch=main", seed.to_s)
      configure_repository(seed)
      File.write(seed.join("README.md"), "initial\n")
      git("add", "README.md", chdir: seed)
      git("commit", "-m", "Initial", chdir: seed)
      git("remote", "add", "origin", remote.to_s, chdir: seed)
      git("push", "-u", "origin", "main", chdir: seed)
      git("clone", remote.to_s, source.to_s)
      git("clone", remote.to_s, publisher.to_s)
      configure_repository(source)
      configure_repository(publisher)

      yield({ root:, remote:, source:, publisher: })
    end
  end

  def configure_repository(path)
    git("config", "user.name", "KOS Test", chdir: path)
    git("config", "user.email", "kos@example.test", chdir: path)
  end

  def git(*arguments, chdir: Rails.root)
    environment = {
      "GIT_CONFIG_NOSYSTEM" => "1",
      "GIT_CONFIG_GLOBAL" => "/dev/null",
      "GIT_CONFIG_COUNT" => nil,
      "GIT_CONFIG_PARAMETERS" => nil,
      "GIT_TERMINAL_PROMPT" => "0",
      "GIT_DIR" => nil,
      "GIT_WORK_TREE" => nil,
      "GIT_INDEX_FILE" => nil,
      "LC_ALL" => "C"
    }
    output, error, status = Open3.capture3(environment, "git", *arguments, chdir: chdir.to_s)
    assert_predicate status, :success?, "git #{arguments.join(" ")} failed:\n#{output}#{error}"
    output
  end

  def git_success?(*arguments, chdir: Rails.root)
    environment = {
      "GIT_CONFIG_NOSYSTEM" => "1",
      "GIT_CONFIG_GLOBAL" => "/dev/null",
      "GIT_CONFIG_COUNT" => nil,
      "GIT_CONFIG_PARAMETERS" => nil,
      "GIT_TERMINAL_PROMPT" => "0",
      "GIT_DIR" => nil,
      "GIT_WORK_TREE" => nil,
      "GIT_INDEX_FILE" => nil,
      "LC_ALL" => "C"
    }
    _output, _error, status = Open3.capture3(environment, "git", *arguments, chdir: chdir.to_s)
    status.success?
  end
end
