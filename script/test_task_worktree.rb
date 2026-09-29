require "minitest/autorun"
require "tmpdir"
require "open3"
require "fileutils"

class TaskWorktreeTest < Minitest::Test
  def test_two_projects_recovery_conflicts_and_cleanup
    Dir.mktmpdir("kos-worktree-check-") do |root|
      %w[shop notes].each do |project|
        checkout = File.join(root, project)
        FileUtils.mkdir_p(checkout)
        git(root, "init", "-b", "main", checkout)
        git(checkout, "config", "user.name", "Worktree Test")
        git(checkout, "config", "user.email", "worktree@example.invalid")
        git(checkout, "remote", "add", "origin", "https://github.com/example/#{project}.git")
        File.write(File.join(checkout, "README.md"), project)
        git(checkout, "add", "README.md")
        git(checkout, "commit", "-m", "Initial commit")

        occupied = File.join(root, "#{project}-task-43")
        File.write(occupied, "someone else's work")
        _output, status = run_git(checkout, "worktree", "add", "-b", "#{project}/task-43", occupied, "main")
        refute status.success?
        assert_equal "someone else's work", File.read(occupied)

        branch = "#{project}/task-42"
        worktree = File.join(root, "#{project}-task-42")
        refute File.exist?(worktree)
        git(checkout, "worktree", "add", "-b", branch, worktree, "main")
        assert_includes git(checkout, "worktree", "list", "--porcelain"), "worktree #{worktree}\n"
        assert_equal branch, git(worktree, "branch", "--show-current").strip
        assert_equal "https://github.com/example/#{project}.git", git(worktree, "remote", "get-url", "origin").strip

        # A resumed agent finds the same branch/path; Git refuses a second checkout.
        assert_includes git(checkout, "worktree", "list", "--porcelain"), "branch refs/heads/#{branch}\n"
        _output, status = run_git(checkout, "worktree", "add", "-b", branch, File.join(root, "duplicate-#{project}"), "main")
        refute status.success?
        refute File.exist?(File.join(root, "duplicate-#{project}"))

        File.write(File.join(worktree, "pending.txt"), "unsaved")
        refute_empty git(worktree, "status", "--porcelain", "--untracked-files=all")
        _output, status = run_git(checkout, "worktree", "remove", worktree)
        refute status.success?, "dirty worktree must be preserved"
        assert File.exist?(File.join(worktree, "pending.txt"))

        FileUtils.rm(File.join(worktree, "pending.txt"))
        File.write(File.join(worktree, "published.txt"), "task result")
        git(worktree, "add", "published.txt")
        git(worktree, "commit", "-m", "Task result")
        remote = File.join(root, "#{project}-publication.git")
        git(root, "init", "--bare", remote)
        git(checkout, "remote", "add", "publication", remote)
        git(checkout, "push", "publication", "main")
        _output, status = run_git(checkout, "push", "missing-publication", "main")
        refute status.success?
        assert File.directory?(worktree), "failed publication must preserve the task checkout"
        git(checkout, "merge", "--ff-only", branch)
        git(checkout, "push", "publication", "main")
        assert_equal git(checkout, "rev-parse", "main"), git(root, "--git-dir", remote, "rev-parse", "refs/heads/main")
        assert_empty git(worktree, "status", "--porcelain", "--untracked-files=all")
        git(checkout, "worktree", "remove", worktree)
        refute File.exist?(worktree)
        refute_includes git(checkout, "worktree", "list", "--porcelain"), "worktree #{worktree}\n"

        # The branch still exists: recovery requires reconciliation, not -b/reset.
        assert git(checkout, "show-ref", "--verify", "refs/heads/#{branch}")
      end
    end
  end

  private

  def run_git(directory, *args)
    output, status = Open3.capture2e("git", *args, chdir: directory)
    [ output, status ]
  end

  def git(directory, *args)
    output, status = run_git(directory, *args)
    assert status.success?, "git #{args.first} failed: #{output}"
    output
  end
end
