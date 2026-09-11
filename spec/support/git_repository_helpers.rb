require "digest"
require "fileutils"
require "open3"

module GitRepositoryHelpers
  def initialize_git_repository(path, task_number:, files:)
    FileUtils.mkdir_p(path)
    git(path, "init", "--initial-branch=main")
    git(path, "config", "user.name", "KOS Test")
    git(path, "config", "user.email", "kos@example.test")
    files.each do |relative_path, content|
      absolute_path = File.join(path, relative_path)
      FileUtils.mkdir_p(File.dirname(absolute_path))
      File.binwrite(absolute_path, content)
    end
    git(path, "add", "--", *files.keys)
    git(path, "commit", "-m", "Test candidate", "-m", "KOS-Task: #{task_number}")
    git(path, "rev-parse", "HEAD").strip
  end

  def git(path, *arguments)
    stdout, stderr, status = Open3.capture3("git", "-C", path, *arguments)
    raise "git failed: #{stderr}" unless status.success?

    stdout.force_encoding(Encoding::UTF_8)
  end
end
