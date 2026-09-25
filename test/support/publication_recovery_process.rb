require "digest"
require "json"
require "open3"
require "tmpdir"

worktree, source, task_id, review_artifact_path, push_mode = ARGV
artifact = File.binread(review_artifact_path)
match = artifact.match(/```json\s*\n(?<json>.*?)\n```/m)
abort("accepted review artifact has no exact-range evidence") unless match
review = JSON.parse(match[:json])
base = review.fetch("base")
reviewed_commits = review.fetch("commits")
tip = review.fetch("tip")
reviewed_trees = review.fetch("trees")
expected_paths = review.fetch("paths").sort
reviewed_diff_sha256 = review.fetch("diff_sha256")
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

capture_git = lambda do |directory, *arguments|
  Open3.capture3(environment, "git", *arguments, chdir: directory)
end
run_git = lambda do |directory, *arguments|
  output, error, status = capture_git.call(directory, *arguments)
  abort("git #{arguments.join(" ")} failed: #{output}#{error}") unless status.success?
  output
end

head = run_git.call(worktree, "rev-parse", "HEAD").strip
commits = run_git.call(worktree, "rev-list", "--reverse", "#{base}..#{head}").lines.map(&:strip)
abort("reviewed sequence changed") unless commits == reviewed_commits && head == tip && tip == reviewed_commits.last

previous = base
commits.each do |commit|
  parents = run_git.call(worktree, "rev-list", "--parents", "-n", "1", commit).split
  message_lines = run_git.call(worktree, "log", "-1", "--format=%B", commit).split("\n", -1)
  task_trailers = message_lines.select { |line| line.match?(/\A\s*(?i:kos-task)\s*:/) }
  canonical_trailer = "KOS-Task: #{task_id}"
  abort("commit verification failed") unless parents == [ commit, previous ] &&
    task_trailers == [ canonical_trailer ]
  previous = commit
end

trees = ([ base ] + commits).to_h do |commit|
  [ commit, run_git.call(worktree, "rev-parse", "#{commit}^{tree}").strip ]
end
paths = run_git.call(worktree, "diff", "--name-only", base, tip).lines.map(&:strip).sort
diff = run_git.call(worktree, "diff", "--no-ext-diff", "--no-textconv", "--binary", base, tip)
status = run_git.call(worktree, "status", "--porcelain")
abort("range verification failed") unless trees == reviewed_trees && paths == expected_paths &&
  Digest::SHA256.hexdigest(diff.b) == reviewed_diff_sha256 && status.empty?

remote_range_valid = lambda do |remote|
  next false unless remote == tip

  remote_commits = run_git.call(source, "rev-list", "--reverse", "#{base}..#{remote}").lines.map(&:strip)
  remote_trees = ([ base ] + remote_commits).to_h do |commit|
    [ commit, run_git.call(source, "rev-parse", "#{commit}^{tree}").strip ]
  end
  remote_commits == reviewed_commits && remote_trees == reviewed_trees
end

run_git.call(source, "fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main")
remote = run_git.call(source, "rev-parse", "origin/main").strip
pushed = false
push_success = nil
push_exitstatus = nil

if remote == tip
  abort("remote reviewed sequence is invalid") unless remote_range_valid.call(remote)
elsif remote != base
  abort("remote tip differs from reviewed base and tip")
else
  if push_mode == "nonzero-after-success"
    push_status = nil
    Dir.mktmpdir("kos-receive-pack") do |directory|
      wrapper = File.join(directory, "receive-pack")
      File.write(wrapper, <<~SH)
        #!/bin/sh
        git-receive-pack "$@"
        status=$?
        [ "$status" -eq 0 ] || exit "$status"
        exit 1
      SH
      File.chmod(0o700, wrapper)
      _push_output, _push_error, push_status = capture_git.call(worktree, "push", "--receive-pack=#{wrapper}",
        "origin", "#{tip}:refs/heads/main")
    end
    abort("receive-pack failure simulation unexpectedly succeeded") if push_status.success?
  else
    _push_output, _push_error, push_status = capture_git.call(worktree, "push", "origin",
      "#{tip}:refs/heads/main")
  end
  pushed = true
  push_success = push_status.success?
  push_exitstatus = push_status.exitstatus

  run_git.call(source, "fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main")
  remote = run_git.call(source, "rev-parse", "origin/main").strip
  unless remote_range_valid.call(remote)
    abort(push_success ? "publication was not observed" : "push failed and exact publication was not observed")
  end
end

puts JSON.generate(tip:, commits:, commit_count: run_git.call(worktree, "rev-list", "--count", "HEAD").strip,
  pushed:, push_success:, push_exitstatus:)
