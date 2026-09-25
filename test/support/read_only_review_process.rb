require "digest"
require "json"
require "open3"

worktree, base, task_id, expected_paths_json = ARGV
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

run_git = lambda do |*arguments|
  output, error, status = Open3.capture3(environment, "git", *arguments, chdir: worktree)
  abort("git #{arguments.join(" ")} failed: #{output}#{error}") unless status.success?
  output
end

head = run_git.call("rev-parse", "HEAD")
status = run_git.call("status", "--porcelain=v2", "--untracked-files=all", "-z")
abort("review requires a clean worktree") unless status.empty?
commits = run_git.call("rev-list", "--reverse", "#{base}..HEAD").lines.map(&:strip)
previous = base
trees = { base => run_git.call("rev-parse", "#{base}^{tree}").strip }
commits.each do |commit|
  parents = run_git.call("rev-list", "--parents", "-n", "1", commit).split
  message_lines = run_git.call("log", "-1", "--format=%B", commit).split("\n", -1)
  task_trailers = message_lines.select { |line| line.match?(/\A\s*(?i:kos-task)\s*:/) }
  canonical_trailer = "KOS-Task: #{task_id}"
  abort("invalid task commit") unless parents == [ commit, previous ] && task_trailers == [ canonical_trailer ]
  trees[commit] = run_git.call("rev-parse", "#{commit}^{tree}").strip
  previous = commit
end
abort("empty reviewed sequence") if commits.empty?
changed_paths = run_git.call("diff", "--name-only", base, "HEAD").lines.map(&:strip).sort
abort("review path set is incomplete") unless changed_paths == expected_paths
reviewed_diff = run_git.call("diff", "--no-ext-diff", "--no-textconv", "--binary", base, "HEAD")

abort("review changed HEAD") unless head == run_git.call("rev-parse", "HEAD")
abort("review changed worktree status") unless status ==
  run_git.call("status", "--porcelain=v2", "--untracked-files=all", "-z")

puts JSON.generate(base:, commits:, tip: commits.last, trees:, paths: changed_paths,
  diff_sha256: Digest::SHA256.hexdigest(reviewed_diff.b))
