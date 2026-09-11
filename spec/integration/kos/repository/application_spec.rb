require "digest"
require "fileutils"
require "json"
require "open3"
require "stringio"
require "tmpdir"
require "spec_helper"
require_relative "../../../../lib/kos/repository"

RSpec.describe Kos::Repository::Application do
  let(:directory) { File.realpath(Dir.mktmpdir("kos-repository-spec")) }
  let(:repository_path) { File.join(directory, "project") }
  let(:worktrees_path) { File.join(directory, "worktrees") }

  before do
    FileUtils.mkdir_p(repository_path)
    FileUtils.mkdir_p(worktrees_path)
    git(repository_path, "init", "--initial-branch=main")
    git(repository_path, "config", "user.name", "KOS Test")
    git(repository_path, "config", "user.email", "kos@example.test")
    File.write(File.join(repository_path, "README.md"), "initial\n")
    git(repository_path, "add", "README.md")
    git(repository_path, "commit", "-m", "Initial")
  end

  after do
    FileUtils.remove_entry(directory) if File.exist?(directory)
  end

  it "materializes and idempotently observes the reserved branch", :aggregate_failures do
    first = invoke(request("materialize", "reserved"))
    second = invoke(request("materialize", "reserved"))

    expect(first.fetch("observation").fetch("state")).to eq("clean")
    expect(second).to eq(first)
    expect(git(worktree_path, "symbolic-ref", "HEAD").strip).to eq("refs/heads/kos/task-KOS-000123")
  end

  it "reports tracked, untracked, and ignored files as dirty" do
    invoke(request("materialize", "reserved"))
    make_worktree_dirty

    result = invoke(request("observe", "confirmed"))

    expect(result.fetch("observation").fetch("state")).to eq("dirty")
  end

  it "reports an ignored-only worktree as dirty" do
    invoke(request("materialize", "reserved"))
    create_ignored_file

    result = invoke(request("observe", "confirmed").merge("expected_head_sha" => head_sha_for(worktree_path)))

    expect(result.fetch("observation").fetch("state")).to eq("dirty")
  end

  it "reports an unstaged tracked change as dirty" do
    invoke(request("materialize", "reserved"))
    File.write(File.join(worktree_path, "README.md"), "changed\n")

    result = invoke(request("observe", "confirmed"))

    expect(result.fetch("observation").fetch("state")).to eq("dirty")
  end

  it "reports a staged tracked change as dirty" do
    invoke(request("materialize", "reserved"))
    File.write(File.join(worktree_path, "README.md"), "changed\n")
    git(worktree_path, "add", "README.md")

    result = invoke(request("observe", "confirmed"))

    expect(result.fetch("observation").fetch("state")).to eq("dirty")
  end

  it "reports unfinished Git state as dirty" do
    invoke(request("materialize", "reserved"))
    File.write(git(worktree_path, "rev-parse", "--git-path", "MERGE_HEAD").strip, "#{head_sha}\n")

    result = invoke(request("observe", "confirmed"))

    expect(result.fetch("observation").fetch("state")).to eq("dirty")
  end

  it "does not remove a dirty worktree", :aggregate_failures do
    invoke(request("materialize", "reserved"))
    File.write(File.join(worktree_path, "untracked.txt"), "preserve\n")

    result = invoke(request("remove", "release_pending"))

    expect(result.fetch("observation").fetch("state")).to eq("dirty")
    expect(File.read(File.join(worktree_path, "untracked.txt"))).to eq("preserve\n")
  end

  it "removes a clean worktree without deleting its branch", :aggregate_failures do
    invoke(request("materialize", "reserved"))

    result = invoke(request("remove", "release_pending"))

    expect(result.fetch("observation").fetch("state")).to eq("absent")
    expect(File).not_to exist(worktree_path)
    expect(git(repository_path, "show-ref", "--verify", "refs/heads/kos/task-KOS-000123")).not_to be_empty
  end

  it "resumes removal after the worktree was already unlocked" do
    invoke(request("materialize", "reserved"))
    git(repository_path, "worktree", "unlock", worktree_path)

    result = invoke(request("remove", "release_pending"))

    expect(result.fetch("observation").fetch("state")).to eq("absent")
  end

  it "rejects an unproven worktree left at the reserved path", :aggregate_failures do
    git(repository_path, "worktree", "add", "-b", "kos/task-KOS-000123", worktree_path, head_sha)

    document, exit_status = run(request("materialize", "reserved"))

    expect(exit_status).to eq(6)
    expect(document.dig("error", "code")).to eq("worktree_mismatched")
    expect(File).to exist(worktree_path)
  end

  it "rejects a symlinked worktree parent", :aggregate_failures do
    replace_parent_with_symlink
    document, exit_status = run(request("materialize", "reserved"))

    expect(exit_status).to eq(2)
    expect(document.dig("error", "code")).to eq("worktree_path_invalid")
  end

  it "rejects a private linked-worktree git directory before mutation", :aggregate_failures do
    document, exit_status = run(private_common_dir_request)

    expect(exit_status).to eq(2)
    expect(document.dig("error", "code")).to eq("repository_invalid")
    expect(File).not_to exist(worktree_path)
  end

  it "reports symlinked linked-worktree metadata as mismatched" do
    invoke(request("materialize", "reserved"))
    replace_metadata_with_symlink

    result = invoke(request("observe", "confirmed"))

    expect(result.fetch("observation").fetch("state")).to eq("mismatched")
  end

  it "reports a symlinked common-directory pointer as mismatched" do
    invoke(request("materialize", "reserved"))
    replace_common_dir_pointer_with_symlink

    result = invoke(request("observe", "confirmed"))

    expect(result.fetch("observation").fetch("state")).to eq("mismatched")
  end

  it "reports a symlinked worktree pointer as mismatched" do
    invoke(request("materialize", "reserved"))
    replace_metadata_pointer_with_symlink("gitdir")

    result = invoke(request("observe", "confirmed"))

    expect(result.fetch("observation").fetch("state")).to eq("mismatched")
  end

  it "terminates a timed-out Git process" do
    operation = proc { Kos::Repository::Git.new.call("-c", "alias.pause=!sleep 5", "pause", timeout: 0.01) }

    expect(&operation).to raise_error(Kos::Repository::Error, "Git operation timed out")
  end

  it "disables a repository-configured filesystem monitor" do
    trigger = configure_filesystem_monitor

    invoke(request("materialize", "reserved"))

    expect(File).not_to exist(trigger)
  end

  it "returns stable evidence for the same observation" do
    first = invoke(request("observe", "reserved"))
    second = invoke(request("observe", "reserved"))

    expect(first.fetch("observation").fetch("evidence_digest")).to eq(
      second.fetch("observation").fetch("evidence_digest")
    )
  end

  it "serializes concurrent materialization", :aggregate_failures do
    expect(concurrent_materializations.map { |result| result.fetch("state") }.uniq).to eq([ "clean" ])
    expect(git(repository_path, "worktree", "list", "--porcelain").scan(/^worktree /).length).to eq(2)
  end

  it "rejects a moved base without creating the worktree", :aggregate_failures do
    input = request("materialize", "reserved").merge("expected_head_sha" => "1" * 40)

    document, exit_status = run(input)

    expect(exit_status).to eq(6)
    expect(document.dig("error", "code")).to eq("base_ref_moved")
    expect(File).not_to exist(worktree_path)
  end

  it "returns a closed failure without raw Git diagnostics", :aggregate_failures do
    document, exit_status = run(missing_repository_request)

    expect(exit_status).to eq(2)
    expect(document.dig("error", "code")).to eq("repository_invalid")
    expect(JSON.generate(document)).not_to include("missing-secret-directory")
  end

  def request(operation, state)
    { "schema_version" => "1", "operation" => operation,
      "repository" => { "id" => repository_id, "git_common_dir" => common_dir,
        "base_ref" => "refs/heads/main" },
      "reservation" => { "id" => reservation_id, "repository_id" => repository_id, "state" => state,
        "path" => worktree_path, "branch" => "kos/task-KOS-000123", "fencing_token" => 8 },
      "expected_head_sha" => head_sha }
  end

  def worktree_path
    File.join(worktrees_path, "KOS-000123")
  end

  def common_dir
    File.realpath(File.join(repository_path, ".git"))
  end

  def head_sha
    head_sha_for(repository_path)
  end

  def head_sha_for(path)
    git(path, "rev-parse", "HEAD").strip
  end

  def repository_id
    "33333333-3333-4333-8333-333333333333"
  end

  def reservation_id
    "55555555-5555-4555-8555-555555555555"
  end

  def make_worktree_dirty
    File.write(File.join(worktree_path, ".gitignore"), "ignored.log\n")
    File.write(File.join(worktree_path, "untracked.txt"), "data\n")
    File.write(File.join(worktree_path, "ignored.log"), "data\n")
  end

  def create_ignored_file
    File.write(File.join(worktree_path, ".gitignore"), "ignored.log\n")
    git(worktree_path, "add", ".gitignore")
    git(worktree_path, "commit", "-m", "Ignore generated file")
    File.write(File.join(worktree_path, "ignored.log"), "preserve\n")
  end

  def replace_parent_with_symlink
    real_parent = File.join(directory, "real-worktrees")
    FileUtils.mkdir_p(real_parent)
    FileUtils.rm_r(worktrees_path)
    File.symlink(real_parent, worktrees_path)
  end

  def create_secondary_worktree
    path = File.join(worktrees_path, "secondary")
    git(repository_path, "worktree", "add", "--detach", path, head_sha)
    git(path, "rev-parse", "--path-format=absolute", "--git-dir").strip
  end

  def private_common_dir_request
    request("materialize", "reserved").tap do |input|
      input.fetch("repository")["git_common_dir"] = create_secondary_worktree
    end
  end

  def replace_metadata_with_symlink
    metadata = git(worktree_path, "rev-parse", "--path-format=absolute", "--git-dir").strip
    moved = "#{metadata}-moved"
    File.rename(metadata, moved)
    File.symlink(moved, metadata)
  end

  def replace_common_dir_pointer_with_symlink
    replace_metadata_pointer_with_symlink("commondir")
  end

  def replace_metadata_pointer_with_symlink(name)
    metadata = git(worktree_path, "rev-parse", "--path-format=absolute", "--git-dir").strip
    pointer = File.join(metadata, name)
    moved = "#{pointer}-moved"
    File.rename(pointer, moved)
    File.symlink(moved, pointer)
  end

  def configure_filesystem_monitor
    trigger = File.join(directory, "fsmonitor-ran")
    script = File.join(directory, "fsmonitor")
    File.write(script, "#!/bin/sh\ntouch '#{trigger}'\n")
    File.chmod(0o700, script)
    git(repository_path, "config", "core.fsmonitor", script)
    trigger
  end

  def concurrent_materializations
    ready = Queue.new
    start = Queue.new
    workers = 2.times.map do
      Thread.new do
        ready << true
        start.pop
        Kos::Repository::Worktree.new(request("materialize", "reserved")).call
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    workers.map(&:value)
  end

  def missing_repository_request
    request("observe", "confirmed").tap do |input|
      input.fetch("repository")["git_common_dir"] = File.join(directory, "missing-secret-directory")
    end
  end

  def invoke(input)
    document, status = run(input)
    raise document.inspect unless status.zero?

    document
  end

  def run(input)
    stdout = StringIO.new
    status = described_class.new([ input.fetch("operation"), "--input", "-", "--json" ],
      input: StringIO.new(JSON.generate(input)), stdout: stdout, stderr: StringIO.new).run
    [ JSON.parse(stdout.string), status ]
  end

  def git(path, *arguments)
    stdout, stderr, status = Open3.capture3("git", "-C", path, *arguments)
    raise stderr unless status.success?

    stdout
  end
end
