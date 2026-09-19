require "json"
require "open3"

worktree, source, task_id, title, expected_paths_json, reviewed_patch_path = ARGV
expected_paths = JSON.parse(expected_paths_json).sort
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

run_git = lambda do |directory, *arguments|
  output, error, status = Open3.capture3(environment, "git", *arguments, chdir: directory)
  abort("git #{arguments.join(" ")} failed: #{output}#{error}") unless status.success?
  output
end

candidate = run_git.call(worktree, "rev-parse", "HEAD").strip
parent = run_git.call(worktree, "rev-parse", "#{candidate}^").strip
parents = run_git.call(worktree, "rev-list", "--parents", "-n", "1", candidate).split
subject = run_git.call(worktree, "log", "-1", "--format=%s").strip
trailer = run_git.call(worktree, "log", "-1", "--format=%(trailers:key=KOS-Task,valueonly)").strip
paths = run_git.call(worktree, "diff-tree", "--no-commit-id", "--name-only", "-r", candidate).lines.map(&:strip).sort
patch = run_git.call(worktree, "diff", "--binary", parent, candidate)
status = run_git.call(worktree, "status", "--porcelain")
abort("candidate verification failed") unless parents == [ candidate, parent ] &&
  subject == "KOS task #{task_id}: #{title}" && trailer == task_id && paths == expected_paths &&
  patch == File.binread(reviewed_patch_path) && status.empty?

run_git.call(source, "fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main")
remote = run_git.call(source, "rev-parse", "origin/main").strip
published = system(environment, "git", "merge-base", "--is-ancestor", candidate, remote, chdir: worktree,
  out: File::NULL, err: File::NULL)
pushed = false
unless published
  abort("candidate parent is not the remote tip") unless parent == remote

  run_git.call(worktree, "push", "origin", "#{candidate}:refs/heads/main")
  pushed = true
end

run_git.call(source, "fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main")
observed = run_git.call(source, "rev-parse", "origin/main").strip
abort("publication was not observed") unless candidate == observed

puts JSON.generate(candidate:, commit_count: run_git.call(worktree, "rev-list", "--count", "HEAD").strip, pushed:)
