require "json"
require "open3"

worktree, expected_paths_json = ARGV
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
changed_paths = (run_git.call("diff", "--name-only", "HEAD").lines +
  run_git.call("ls-files", "--others", "--exclude-standard").lines).map(&:strip).uniq.sort
abort("review path set is incomplete") unless changed_paths == expected_paths
tracked_patch = run_git.call("diff", "--no-ext-diff", "--binary", "HEAD", "--", *expected_paths)
contents = expected_paths.to_h { |path| [ path, File.binread(File.join(worktree, path)) ] }

abort("review changed HEAD") unless head == run_git.call("rev-parse", "HEAD")
abort("review changed worktree status") unless status ==
  run_git.call("status", "--porcelain=v2", "--untracked-files=all", "-z")

puts JSON.generate(paths: changed_paths, tracked_patch:, contents:)
