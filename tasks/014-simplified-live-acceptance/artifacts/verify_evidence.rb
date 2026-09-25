#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

ARTIFACTS = File.expand_path(__dir__)

def run(*command, chdir: nil)
  options = chdir ? { chdir: chdir } : {}
  output, error, status = Open3.capture3(*command, **options)
  raise "#{command.join(" ")} failed: #{error}" unless status.success?
  output
end

def assert(label, condition)
  raise "FAIL #{label}" unless condition
  puts "PASS #{label}"
end

def artifact(name)
  JSON.parse(File.read(File.join(ARTIFACTS, name)))
end

def parse_review(task_id)
  markdown = artifact("task-#{task_id}-review.json").fetch("markdown")
  base_match = markdown.match(/Base(?: tree)?:? `([0-9a-f]{40})`/)
  tip_match = markdown.match(/Tip: `([0-9a-f]{40})`/)
  raise "task #{task_id} review lacks base or tip" unless base_match && tip_match

  sequence = markdown[base_match.end(0)...tip_match.begin(0)].scan(/[0-9a-f]{40}/)
  tree_lines = markdown.lines.select do |line|
    line.match?(/tree:/i) || line.match?(/^  - (?:Base|`[0-9a-f]{40}`):/)
  end
  trees = tree_lines.filter_map { |line| line.scan(/[0-9a-f]{40}/).last }
  paths = markdown[/Changed paths?: (.+)$/, 1].scan(/`([^`]+)`/).flatten.sort
  digest = markdown[/binary diff SHA-256: `([0-9a-f]{64})`/i, 1]
  raise "task #{task_id} review is incomplete" if sequence.empty? || trees.empty? || paths.empty? || !digest

  { markdown: markdown, base: base_match[1], commits: sequence, tip: tip_match[1], trees: trees,
    paths: paths, digest: digest }
end

def git(repository, *arguments)
  run("git", "--no-pager", *arguments, chdir: repository)
end

Dir.mktmpdir("kos-014-evidence-") do |directory|
  inventory = File.read(File.join(ARTIFACTS, "installed-inventory.txt"))
  help = File.read(File.join(ARTIFACTS, "cli-help.txt"))
  launches = artifact("agent-launches.json")
  assert("installed inventory has no kos-verify", !inventory.include?("kos-verify"))
  assert("CLI help has no validate-children", !help.include?("validate-children"))
  assert("sanitized launch evidence has no verifier", launches.fetch("verifier_launches").zero? &&
    launches.fetch("calls").none? { |call| call.fetch("profile") == "kos-verify" })
  completed_launches = launches.fetch("calls").select { |call| call.fetch("status") == "completed" }
    .group_by { |call| call.fetch("prompt") }
    .transform_values { |calls| calls.map { |call| call.fetch("profile") } }
  assert("task 1 launch evidence reaches publication",
    completed_launches.fetch("1").tally == { "kos-brief" => 3, "kos-review" => 2, "kos-publish" => 1 })
  assert("task 2 launch evidence covers the complete workflow",
    completed_launches.fetch("2") == %w[kos-plan kos-implement kos-document kos-review kos-publish])
  assert("task 3 launch evidence covers the complete workflow",
    completed_launches.fetch("3") == %w[kos-diagnose kos-plan kos-implement kos-document kos-review kos-publish])
  timing_lines = File.read(File.join(ARTIFACTS, "timings.txt"))
  assert("timing evidence covers every command",
    %w[/kos-brief /kos /kos-fix].all? { |command| timing_lines.include?(command) } &&
      timing_lines.include?("Total active elapsed: 2699 seconds"))

  argument_observation = artifact("argument-observation.json")
  expected_payload = argument_observation.fetch("expected_payload")
  submitted_payload = JSON.parse(File.read(File.join(ARTIFACTS, "task-1-context.json")))
    .dig("task", "description_markdown").delete_prefix("# Request\n\n").delete_suffix("\n")
  assert("argument observation expected digest",
    Digest::SHA256.hexdigest(expected_payload.b) == argument_observation.dig("expected", "sha256"))
  assert("argument observation submitted digest",
    Digest::SHA256.hexdigest(submitted_payload.b) == argument_observation.dig("submitted", "sha256"))
  assert("argument observation isolates wrapper quotes", submitted_payload == "\"#{expected_payload}\"")

  repository = File.join(directory, "observer")
  run("git", "clone", "-q", File.join(ARTIFACTS, "fixture-remote.bundle"), repository)
  main = git(repository, "rev-parse", "refs/heads/main").strip

  reviews = (1..3).to_h { |task_id| [ task_id, parse_review(task_id) ] }
  assert("remote main is task 3 reviewed tip", main == reviews.fetch(3).fetch(:tip))

  reviews.each do |task_id, review|
    assert("task #{task_id} reviewed tip is on remote main",
      system("git", "merge-base", "--is-ancestor", review.fetch(:tip), main, chdir: repository))
    observed = git(repository, "rev-list", "--reverse", "#{review.fetch(:base)}..#{review.fetch(:tip)}").lines.map(&:strip)
    assert("task #{task_id} ordered SHAs", observed == review.fetch(:commits))

    expected_parent = review.fetch(:base)
    review.fetch(:commits).each do |commit|
      parents = git(repository, "show", "-s", "--format=%P", commit).split
      assert("task #{task_id} #{commit} parent", parents == [ expected_parent ])
      message = git(repository, "show", "-s", "--format=%B", commit)
      task_trailers = message.split("\n", -1).select { |line| line.match?(/kos-task/i) }
      assert("task #{task_id} #{commit} exact raw trailer", task_trailers == [ "KOS-Task: #{task_id}" ])
      expected_parent = commit
    end

    observed_trees = [ review.fetch(:base), *review.fetch(:commits) ].map do |commit|
      git(repository, "show", "-s", "--format=%T", commit).strip
    end
    assert("task #{task_id} trees", observed_trees == review.fetch(:trees))

    diff_arguments = [ "diff", "--binary", "--no-ext-diff", "--no-textconv", review.fetch(:base), review.fetch(:tip) ]
    diff = git(repository, *diff_arguments)
    assert("task #{task_id} binary diff SHA-256", Digest::SHA256.hexdigest(diff) == review.fetch(:digest))
    paths = git(repository, "diff", "--name-only", "--no-ext-diff", "--no-textconv",
      review.fetch(:base), review.fetch(:tip)).lines.map(&:strip).sort
    assert("task #{task_id} changed paths", paths == review.fetch(:paths))
  end

  children = artifact("task-1-children.json")
  definition = artifact("brief-graph-definition.json").fetch("children")
  expected = definition.sort_by { |child| child.fetch("key") }.map do |child|
    {
      "title" => child.fetch("title"),
      "description_markdown" => child.fetch("description_markdown"),
      "blocker_positions" => [],
      "task_type_key" => "development",
      "parent_blocker" => true,
      "external_blocker_ids" => []
    }
  end
  digest = "sha256:#{Digest::SHA256.hexdigest(JSON.generate(expected))}"
  observed = children.fetch("children")
  child = observed.fetch(0)
  task = child.fetch("task")
  assert("brief graph has exactly one child", observed.length == 1)
  assert("brief child title", task.fetch("title") == expected.fetch(0).fetch("title"))
  assert("brief child description", task.fetch("description_markdown") == expected.fetch(0).fetch("description_markdown"))
  assert("brief child type", task.fetch("task_type_key") == "development")
  assert("brief child parent/blockers", task.fetch("parent_id") == 1 && task.fetch("blocker_ids") == [ 1 ] &&
    child.fetch("sibling_blocker_ids").empty?)
  assert("brief graph digest", children.fetch("digest") == digest)

  brief = artifact("task-1-brief.json").fetch("markdown")
  brief_review = artifact("task-1-review.json").fetch("markdown")
  normalized_brief = brief.gsub(/\s+/, " ")
  source = definition.fetch(0)
  assert("accepted brief names exact child", brief.include?(source.fetch("title")))
  source.fetch("description_markdown").split(". ").each do |sentence|
    assert("accepted brief contains child requirement: #{sentence[0, 32]}",
      normalized_brief.include?(sentence.delete_suffix(".")))
  end
  assert("accepted brief records no sibling blockers", brief.include?("blocked_by: []"))
  assert("accepted review approves exact graph cardinality", brief_review.include?("exactly one development child with no sibling blockers"))

  (1..3).each do |task_id|
    context_response = artifact("task-#{task_id}-context.json")
    context = context_response.fetch("task")
    assert("task #{task_id} completed at publish with released ownership",
      context.fetch("status") == "completed" && context.fetch("current_step") == "publish" &&
      context["owner_id"].nil? && context["lease_expires_at"].nil?)
    expected_steps = task_id == 1 ? %w[brief review publish] :
      context_response.fetch("artifacts").map { |entry| entry.fetch("step") }
    expected_steps.each do |step|
      next unless File.exist?(File.join(ARTIFACTS, "task-#{task_id}-#{step}.json"))
      accepted = artifact("task-#{task_id}-#{step}.json")
      index = context_response.fetch("artifacts").find { |entry| entry.fetch("step") == step }
      assert("task #{task_id} #{step} response matches accepted index",
        accepted.fetch("outcome") == index.fetch("outcome") &&
        accepted.fetch("accepted_claim_version") == index.fetch("accepted_claim_version"))
    end
  end
end
