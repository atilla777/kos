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
  let(:remote_path) { File.join(directory, "trusted.git") }
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

  it "fetches only the trusted base ref with effect-bound evidence", :aggregate_failures do
    expect(successful_fetch_observation).to eq(successful_fetch_expectation)
  end

  it "fetches objects without changing refs, tags, worktrees, the index, or worktree files", :aggregate_failures do
    expect(fetch_side_effect_observation).to eq([ true, "commit\n", "" ])
  end

  it "rejects repository, remote, ref, and URL mismatches before fetch" do
    expect(fetch_mismatch_results).to eq(%w[repository_mismatch fetch_remote_mismatch fetch_ref_mismatch
      fetch_configuration_invalid].map { |code| [ 2, code ] } + [ false ])
  end

  it "rejects every durable fetch request digest mismatch before transport" do
    expect(fetch_digest_mismatch_results).to eq(Array.new(4, [ 2, "effect_request_mismatch" ]) + [ false, "" ])
  end

  it "rejects multiple configured remote URLs before fetch" do
    input = fetch_request
    git(repository_path, "config", "--add", "remote.origin.url", remote_url)

    document, status = run(input)

    expect([ status, document.dig("error", "code"), File.exist?(File.join(common_dir, "FETCH_HEAD")) ])
      .to eq([ 2, "fetch_configuration_invalid", false ])
  end

  it "rejects fetch.bundleURI before transport" do
    expect(bundle_uri_rejection).to eq([ "fetch_configuration_invalid", false, false ])
  end

  it "rejects related HTTP alternate-endpoint configuration before transport" do
    expect(http_endpoint_override_results).to eq(Array.new(3, "fetch_configuration_invalid") + [ false ])
  end

  it "rejects promisor and partial-clone object authority before fetch" do
    expect(promisor_configuration_results).to eq(Array.new(4, "fetch_configuration_invalid") + [ false ])
  end

  it "rejects configured URL and executable transport overrides without running them", :aggregate_failures do
    expect(configured_override_observation).to eq(Array.new(8, "fetch_configuration_invalid") + [ false, false ])
  end

  it "returns a retryable closed failure without paths, URLs, credentials, or Git diagnostics", :aggregate_failures do
    expect(closed_fetch_failure).to eq([ 8, "fetch_failed", true, false, false, false ])
  end

  it "supplies disabled HTTP redirects, credentials, and server promisors to Git fetch" do
    expect(fetch_process_overrides).to eq([ true, true, true ])
  end

  it "rejects encoded password separators and userinfo tricks before transport" do
    expect(invalid_trusted_url_results).to eq(Array.new(3, "fetch_configuration_invalid") + [ false ])
  end

  it "allows an SSH username in registered trust without making a real network request" do
    expect(ssh_username_result).to eq([ "fetch_failed", true ])
  end

  it "rejects a file URL authority without an absolute nonempty path before transport" do
    expect(invalid_file_url_result).to eq([ "fetch_configuration_invalid", false ])
  end

  it "rejects an ambiguous FETCH_HEAD observation" do
    input = fetch_request
    adapter = git_writing_ambiguous_fetch_head

    error = capture_operation_error(Kos::Repository::Fetch.new(input, git: adapter))

    expect([ error.category, error.code ]).to eq([ "internal", "fetch_result_invalid" ])
  end

  it "rejects a FETCH_HEAD observation for another source ref" do
    error = capture_operation_error(Kos::Repository::Fetch.new(fetch_request, git: git_rewriting_fetch_head_ref))

    expect([ error.category, error.code ]).to eq([ "internal", "fetch_result_invalid" ])
  end

  it "waits for the common adapter lock before validating and fetching", :aggregate_failures do
    expect(fetch_lock_observation).to eq([ true, "", true ])
  end

  it "does not create an adapter lock before proving Git repository identity" do
    expect(non_repository_lock_observation).to eq([ 2, "repository_invalid", false ])
  end

  it "rebases the exact task commit suffix onto verified fetched base evidence", :aggregate_failures do
    expect(successful_rebase_observation).to eq(
      [ true, true, true, [ "KOS-000123" ], "", true, true, true ]
    )
  end

  it "returns the existing HEAD when the task branch already uses the fetched base" do
    input, task_head = prepared_rebase_request(advance: false)

    result = invoke(input)

    expect(result.fetch("head_sha")).to eq(task_head)
  end

  it "aborts a content conflict and proves restoration before returning failure", :aggregate_failures do
    expect(conflicting_rebase_observation).to eq(
      [ 6, "rebase_conflict", false, true, "", true, true, true ]
    )
  end

  it "rejects changed fetch evidence and target before rewriting the task branch" do
    expect(rebase_provenance_mismatch_observation).to eq(
      [ [ 2, "fetch_evidence_mismatch" ], [ 2, "rebase_target_mismatch" ], true ]
    )
  end

  it "rejects a dirty worktree and executable rebase configuration before rebase" do
    expect(rebase_precondition_observation).to eq(
      [ "worktree_mismatched", "rebase_configuration_invalid", "rebase_configuration_invalid", true ]
    )
  end

  it "rejects staged, unfinished, and non-task history before rebase" do
    expect(rebase_state_rejection_observation).to eq(
      %w[index_not_clean unfinished_operation rebase_history_invalid]
    )
  end

  it "returns uncertain when conflict abort cannot restore the repository" do
    expect(unrestored_rebase_observation).to eq([ "transient", "rebase_state_uncertain", true ])
  end

  it "returns uncertain when post-effect observation raises unexpectedly" do
    expect(exceptional_rebase_observation).to eq([ "transient", "rebase_state_uncertain", true ])
  end

  it "returns uncertain when timeout recovery observation raises unexpectedly" do
    expect(exceptional_timeout_recovery_observation).to eq([ "transient", "rebase_state_uncertain", true ])
  end

  it "uses the same hardened configuration for rebase and conflict abort" do
    expect(rebase_configuration_observation).to eq([ true, true, true, true, true ])
  end

  it "rejects a fetched base that diverged from the task base" do
    expect(divergent_rebase_observation).to eq([ "rebase_base_moved", true ])
  end

  it "waits for the common adapter lock before rebasing" do
    expect(rebase_lock_observation).to eq([ true, true ])
  end

  it "commits exactly the requested files with one authoritative trailer", :aggregate_failures do
    result = commit_two_of_three_changes

    expect_successful_exact_commit(result)
  end

  it "rejects a supplied parsed task trailer without staging" do
    document, exit_status = run(changed_readme_request.merge("message" => "Change\n\nKOS-Task: OTHER-000001"))

    expect([ exit_status, document.dig("error", "code"), index_entries ]).to eq([ 2, "commit_message_invalid", [] ])
  end

  it "rejects a mismatched diff before staging" do
    input = changed_readme_request.merge("expected_diff_digest" => "sha256:#{'0' * 64}")

    document, exit_status = run(input)

    expect([ exit_status, document.dig("error", "code"), index_entries ]).to eq([ 6, "diff_mismatch", [] ])
  end

  it "commits an exact tracked-file deletion" do
    result = invoke(deleted_readme_request)

    expect([ committed_paths(result.fetch("commit_sha")), File.exist?(File.join(worktree_path, "README.md")) ])
      .to eq([ [ "README.md" ], false ])
  end

  it "commits a nested deletion after its parent directory disappeared" do
    result = invoke(nested_deletion_request)

    expect(committed_paths(result.fetch("commit_sha"))).to eq([ "nested/file.txt" ])
  end

  it "commits a legitimate nested regular file" do
    result = invoke(changed_nested_file_request)

    expect(committed_paths(result.fetch("commit_sha"))).to eq([ "nested/file.txt" ])
  end

  it "rejects an intermediate directory swapped to an outside symlink before staging" do
    input = changed_nested_file_request
    adapter, state = git_swapping_nested_directory_before_staging

    error = capture_commit_error(input, adapter)

    expect([ error.code, state.fetch(:hash_called), head_sha_for(worktree_path) ])
      .to eq([ "staging_failed", false, head_sha ])
  end

  it "rejects an intermediate symlink swapped back immediately after its open attempt" do
    error, state = commit_with_nested_swap_and_restore(changed_nested_file_request)

    expect([ error.code, state.fetch(:hash_called), state.fetch(:restored), head_sha_for(worktree_path) ])
      .to eq([ "staging_failed", false, true, head_sha ])
  end

  it "rejects a deleted tracked symlink" do
    document, exit_status = run(deleted_symlink_request)

    expect([ exit_status, document.dig("error", "code"), index_entries ]).to eq([ 2, "commit_path_invalid", [] ])
  end

  it "rejects a tracked symlink replaced by a regular file" do
    document, exit_status = run(replaced_symlink_request)

    expect([ exit_status, document.dig("error", "code"), index_entries ]).to eq([ 2, "commit_path_invalid", [] ])
  end

  it "rejects a task number that does not derive the reservation branch" do
    document, exit_status = run(changed_readme_request.merge("task_number" => "KOS-000124"))

    expect([ exit_status, document.dig("error", "code"), index_entries ]).to eq([ 2, "task_mismatch", [] ])
  end

  it "rejects a stale exact HEAD snapshot" do
    document, exit_status = run(changed_readme_request.merge("expected_head_sha" => "1" * 40))

    expect([ exit_status, document.dig("error", "code"), index_entries ]).to eq([ 6, "worktree_mismatched", [] ])
  end

  it "rejects a mismatched reservation marker" do
    input = changed_readme_request.tap { corrupt_reservation_marker }
    document, exit_status = run(input)

    expect([ exit_status, document.dig("error", "code"), index_entries ]).to eq([ 6, "worktree_mismatched", [] ])
  end

  it "rejects an existing staged change before touching the index", :aggregate_failures do
    input = prepare_with_unrelated_staged_change

    document, exit_status = run(input)

    expect(exit_status).to eq(6)
    expect(document.dig("error", "code")).to eq("index_not_clean")
    expect(index_entries).to include("staged.txt")
  end

  it "restores the index after an expected index mismatch while preserving files", :aggregate_failures do
    input = changed_readme_request.merge("expected_index_digest" => "sha256:#{'0' * 64}")

    document, exit_status = run(input)

    expect([ exit_status, document.dig("error", "code"), index_entries ]).to eq([ 6, "index_mismatch", [] ])
    expect_preserved_changed_readme
  end

  it "restores the index after Git cannot create the commit", :aggregate_failures do
    input = changed_readme_without_identity

    document, exit_status = run(input)

    expect([ exit_status, document.dig("error", "code"), index_entries ]).to eq([ 6, "commit_failed", [] ])
    expect_preserved_changed_readme
  end

  it "rejects directories, symlink aliases, pathspec magic, and overlapping paths" do
    unsafe_commit_paths.each do |paths, code|
      document, exit_status = run(commit_request(paths).merge("expected_diff_digest" => "sha256:#{'0' * 64}",
        "expected_index_digest" => "sha256:#{'0' * 64}"))
      expect([ exit_status, document.dig("error", "code") ]).to eq([ 2, code ])
    end
  end

  it "rejects unfinished Git operations before staging", :aggregate_failures do
    document, exit_status = run(changed_readme_with_unfinished_merge)

    expect([ exit_status, document.dig("error", "code"), index_entries ]).to eq([ 6, "unfinished_operation", [] ])
  end

  it "does not invoke configured hooks, signing, editors, or external diff" do
    materialize
    File.write(File.join(worktree_path, "README.md"), "changed\n")
    trigger = configure_commit_traps

    invoke(prepared_commit_request([ "README.md" ]))

    expect(File).not_to exist(trigger)
  end

  it "does not invoke a configured textconv driver" do
    trigger = configure_textconv_trap
    materialize
    File.write(File.join(worktree_path, "README.md"), "changed\n")

    invoke(prepared_commit_request([ "README.md" ]))

    expect(File).not_to exist(trigger)
  end

  it "rejects a configured clean filter without executing it" do
    input, trigger = filtered_readme_request

    document, exit_status = run(input)

    expect([ exit_status, document.dig("error", "code"), File.exist?(trigger) ])
      .to eq([ 6, "commit_filter_unsupported", false ])
  end

  it "does not execute a clean filter introduced after the initial policy check" do
    input = changed_readme_request
    adapter, trigger = git_injecting_filter_after_initial_check

    error = capture_commit_error(input, adapter)

    expect([ error.code, File.exist?(trigger) ]).to eq([ "commit_filter_unsupported", false ])
  end

  it "honors an executable-bit change when core.filemode is enabled" do
    result = invoke(executable_readme_request(filemode: true))

    expect(tree_mode(result.fetch("commit_sha"), "README.md")).to eq("100755")
  end

  it "preserves the tracked mode when core.filemode is disabled" do
    result = invoke(executable_readme_request(filemode: false))

    expect(tree_mode(result.fetch("commit_sha"), "README.md")).to eq("100644")
  end

  it "excludes a concurrently staged unrelated file and preserves its index entry", :aggregate_failures do
    result = commit_with_concurrent_unrelated_stage

    expect(committed_paths(result.fetch("commit_sha"))).to eq([ "README.md" ])
    expect(index_entries).to eq([ "unrelated.txt" ])
    expect(git(worktree_path, "diff", "--name-only", "--", "README.md")).to be_empty
  end

  it "reports success when a failed ref-update response nevertheless advanced the branch" do
    input = changed_readme_request

    result = Kos::Repository::Commit.new(input, git: git_losing_ref_update_response).call

    expect(result.fetch("commit_sha")).to eq(head_sha_for(worktree_path))
  end

  it "reports success when update-ref times out after advancing the branch" do
    input = changed_readme_request

    result = Kos::Repository::Commit.new(input, git: git_timing_out_after_ref_update).call

    expect(result.fetch("commit_sha")).to eq(head_sha_for(worktree_path))
  end

  it "returns an uncertain result when a failed ref update cannot be observed" do
    error = capture_commit_error(changed_readme_request, git_hiding_failed_ref_update)

    expect([ error.category, error.code, error.retryable ]).to eq([ "transient", "ref_update_uncertain", true ])
  end

  it "does not observe the branch after a definitive successful CAS" do
    input = changed_readme_request

    result = Kos::Repository::Commit.new(input, git: git_failing_post_cas_observation).call

    expect(result.fetch("commit_sha")).to eq(head_sha_for(worktree_path))
  end

  it "does not replace an occupied real index lock after successful CAS", :aggregate_failures do
    result, index_path, index_bytes, lock_path, lock_bytes = commit_with_occupied_index_lock

    expect(result.fetch("commit_sha")).to eq(head_sha_for(worktree_path))
    expect(File.binread(index_path)).to eq(index_bytes)
    expect(File.binread(lock_path)).to eq(lock_bytes)
  end

  it "does not overwrite a concurrently advanced reserved branch" do
    input = changed_readme_request
    other_commit = create_concurrent_commit

    error = capture_commit_error(input, git_advancing_reserved_ref(other_commit))

    expect([ error.code, head_sha_for(worktree_path) ]).to eq([ "ref_moved", other_commit ])
  end

  it "serializes commits and rejects the stale expected HEAD", :aggregate_failures do
    results = concurrent_commits(changed_readme_request)

    expect(results.count { |document, status| status.zero? && document.fetch("outcome") == "succeeded" }).to eq(1)
    expect(results.count { |document, status| status == 6 && document.dig("error", "code") == "worktree_mismatched" })
      .to eq(1)
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

  def commit_request(paths)
    request("commit", "confirmed").merge("expected_diff_digest" => "sha256:#{'0' * 64}",
      "expected_index_digest" => "sha256:#{'0' * 64}", "paths" => paths,
      "message" => "Implement exact commit", "task_number" => "KOS-000123")
  end

  def fetch_request
    prepare_remote
    durable_request = durable_fetch_request
    { "schema_version" => "1", "operation" => "fetch",
      "repository" => { "id" => repository_id, "git_common_dir" => common_dir,
        "trusted_remote" => "origin", "trusted_remote_url" => remote_url, "base_ref" => "refs/heads/main" },
      "effect" => { "id" => "66666666-6666-4666-8666-666666666666", "repository_id" => repository_id,
        "current_owner_attempt_id" => "77777777-7777-4777-8777-777777777777", "fencing_token" => 9,
        "request_digest" => digest(canonical_json(durable_request)), "request" => durable_request } }
  end

  def durable_fetch_request
    { "schema_version" => "1", "attempt_id" => "88888888-8888-4888-8888-888888888888",
      "input_context_digest" => "sha256:#{'a' * 64}",
      "effect" => { "operation" => "fetch", "remote" => "origin", "ref" => "refs/heads/main" } }
  end

  def prepared_rebase_request(advance: true, conflict: false)
    task_commit = invoke(changed_readme_request).fetch("commit_sha")
    prepare_remote
    onto = if advance
      conflict ? advance_remote_readme : advance_remote
    else
      head_sha
    end
    fetch_input = fetch_request
    fetch_result = invoke(fetch_input)
    raise "unexpected fetch target" unless fetch_result.fetch("observed_oid") == onto

    [ build_rebase_request(task_commit, onto, fetch_input, fetch_result), task_commit, onto ]
  end

  def build_rebase_request(task_commit, onto, fetch_input, fetch_result)
    durable = { "schema_version" => "1", "attempt_id" => "88888888-8888-4888-8888-888888888888",
      "input_context_digest" => "sha256:#{'c' * 64}",
      "effect" => { "operation" => "rebase", "reservation_id" => reservation_id,
        "expected_head_sha" => task_commit, "onto_sha" => onto } }
    { "schema_version" => "1", "operation" => "rebase", "repository" => fetch_input.fetch("repository"),
      "reservation" => request("observe", "confirmed").fetch("reservation").merge("fencing_token" => 9),
      "effect" => { "id" => "99999999-9999-4999-8999-999999999999", "repository_id" => repository_id,
        "current_owner_attempt_id" => "77777777-7777-4777-8777-777777777777", "fencing_token" => 9,
        "request_digest" => digest(canonical_json(durable)), "request" => durable },
      "fetch" => { "request" => fetch_input, "result" => fetch_result } }
  end

  def successful_rebase_observation
    input, task_head, onto = prepared_rebase_request
    main_before = primary_worktree_state
    result = invoke(input)
    resulting_head = result.fetch("head_sha")
    evidence = { "schema_version" => "1", "repository" => input.fetch("repository"),
      "reservation" => input.fetch("reservation"), "effect" => input.fetch("effect"),
      "fetch" => input.fetch("fetch"), "original_base_sha" => head_sha, "expected_head_sha" => task_head,
      "onto_sha" => onto, "head_sha" => resulting_head }
    [ resulting_head == head_sha_for(worktree_path), resulting_head != task_head,
      git(worktree_path, "merge-base", "--is-ancestor", onto, resulting_head).empty?, task_trailers(resulting_head),
      git(worktree_path, "status", "--porcelain=v2", "--untracked-files=all", "--ignored=matching"),
      result.fetch("evidence_digest") == digest(canonical_json(evidence)), primary_worktree_state == main_before,
      rebase_metadata_paths.none? { |path| File.exist?(path) } ]
  end

  def conflicting_rebase_observation
    input, task_head = prepared_rebase_request(conflict: true)
    refs_before = git(repository_path, "for-each-ref", "--format=%(refname) %(objectname)")
    index_before = git(worktree_path, "ls-files", "--stage", "-z")
    document, status = run(input)
    [ status, document.dig("error", "code"), document.dig("error", "retryable"),
      head_sha_for(worktree_path) == task_head,
      git(worktree_path, "status", "--porcelain=v2", "--untracked-files=all", "--ignored=matching"),
      rebase_metadata_paths.none? { |path| File.exist?(path) },
      git(repository_path, "for-each-ref", "--format=%(refname) %(objectname)") == refs_before,
      git(worktree_path, "ls-files", "--stage", "-z") == index_before ]
  end

  def rebase_provenance_mismatch_observation
    input, task_head = prepared_rebase_request
    changed_evidence = Marshal.load(Marshal.dump(input))
    changed_evidence.dig("fetch", "result")["evidence_digest"] = "sha256:#{'0' * 64}"
    changed_target = Marshal.load(Marshal.dump(input))
    changed_target.dig("effect", "request", "effect")["onto_sha"] = head_sha
    changed_target.fetch("effect")["request_digest"] = digest(canonical_json(changed_target.dig("effect", "request")))
    results = [ changed_evidence, changed_target ].map do |value|
      run(value).then { |document, status| [ status, document.dig("error", "code") ] }
    end
    results << (head_sha_for(worktree_path) == task_head)
  end

  def rebase_precondition_observation
    input, task_head = prepared_rebase_request
    File.write(File.join(worktree_path, "untracked.txt"), "dirty\n")
    dirty = run(input).first
    File.unlink(File.join(worktree_path, "untracked.txt"))
    git(repository_path, "config", "merge.kos.driver", File.join(directory, "unsafe-driver"))
    configured = run(input).first
    git(repository_path, "config", "--unset-all", "merge.kos.driver")
    git(repository_path, "config", "rebase.strategy", "ours")
    strategy = run(input).first
    [ dirty.dig("error", "code"), configured.dig("error", "code"), strategy.dig("error", "code"),
      head_sha_for(worktree_path) == task_head ]
  end

  def rebase_state_rejection_observation
    input, = prepared_rebase_request
    File.write(File.join(worktree_path, "staged.txt"), "staged\n")
    git(worktree_path, "add", "staged.txt")
    staged = run(input).first.dig("error", "code")
    git(worktree_path, "reset", "--hard", input.dig("effect", "request", "effect", "expected_head_sha"))
    operation_path = rebase_metadata_paths.first
    File.write(operation_path, "unfinished\n")
    unfinished = run(input).first.dig("error", "code")
    File.unlink(operation_path)
    git(worktree_path, "commit", "--allow-empty", "-m", "Foreign commit")
    change_rebase_expected_head!(input, head_sha_for(worktree_path))
    [ staged, unfinished, run(input).first.dig("error", "code") ]
  end

  def change_rebase_expected_head!(input, head)
    input.dig("effect", "request", "effect")["expected_head_sha"] = head
    input.fetch("effect")["request_digest"] = digest(canonical_json(input.dig("effect", "request")))
  end

  def unrestored_rebase_observation
    input, = prepared_rebase_request(conflict: true)
    adapter = Kos::Repository::Git.new
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      if arguments.each_cons(2).include?([ "rebase", "--abort" ])
        Kos::Repository::Git::Result.new("", false)
      else
        original.call(*arguments, **options)
      end
    end
    error = capture_operation_error(Kos::Repository::Rebase.new(input, git: adapter))
    [ error.category, error.code, error.retryable ]
  end

  def exceptional_timeout_recovery_observation
    input, = prepared_rebase_request
    adapter = Kos::Repository::Git.new
    timed_out = false
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      raise Errno::EIO if timed_out

      result = original.call(*arguments, **options)
      if arguments.include?("--onto")
        timed_out = true
        raise Kos::Repository::Error.new("transient", "git_timeout", "Git operation timed out", retryable: true)
      end
      result
    end
    error = capture_operation_error(Kos::Repository::Rebase.new(input, git: adapter))
    [ error.category, error.code, error.retryable ]
  end

  def exceptional_rebase_observation
    input, = prepared_rebase_request
    adapter = Kos::Repository::Git.new
    refs_calls = 0
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      refs_calls += 1 if arguments.include?("for-each-ref")
      raise Errno::EIO if refs_calls == 2

      original.call(*arguments, **options)
    end
    error = capture_operation_error(Kos::Repository::Rebase.new(input, git: adapter))
    [ error.category, error.code, error.retryable ]
  end

  def rebase_configuration_observation
    input, = prepared_rebase_request(conflict: true)
    adapter, calls = recording_git
    capture_operation_error(Kos::Repository::Rebase.new(input, git: adapter))
    rebase_calls = calls.select { |arguments| arguments.include?("rebase") }
    normal = rebase_calls.find { |arguments| arguments.include?("--onto") }
    abort = rebase_calls.find { |arguments| arguments.include?("--abort") }
    expected = Kos::Repository::Rebase::REBASE_CONFIGURATION
    [ expected.each_cons(2).all? { |pair| normal.each_cons(2).include?(pair) },
      expected.each_cons(2).all? { |pair| abort.each_cons(2).include?(pair) }, normal.include?("--no-fork-point"),
      normal.include?("--strategy=ort"), normal.include?("--no-update-refs") ]
  end

  def rebase_lock_observation
    input, = prepared_rebase_request
    lock = File.open(File.join(common_dir, "kos-repository.lock"), File::RDWR | File::CREAT, 0o600)
    lock.flock(File::LOCK_EX)
    worker = Thread.new { Kos::Repository::Rebase.new(input).call }
    sleep 0.05
    blocked = worker.alive?
    lock.flock(File::LOCK_UN)
    [ blocked, worker.value.fetch("head_sha") == head_sha_for(worktree_path) ]
  ensure
    lock&.close
  end

  def divergent_rebase_observation
    prepare_remote
    add_base_file("local-base.txt", "local base\n")
    task_commit = invoke(changed_readme_request).fetch("commit_sha")
    onto = advance_remote
    fetch_input = fetch_request
    input = build_rebase_request(task_commit, onto, fetch_input, invoke(fetch_input))
    document = run(input).first
    [ document.dig("error", "code"), head_sha_for(worktree_path) == task_commit ]
  end

  def primary_worktree_state
    { head: head_sha_for(repository_path), index: File.binread(File.join(common_dir, "index")),
      status: git(repository_path, "status", "--porcelain=v2", "--untracked-files=all", "--ignored=matching"),
      readme: File.binread(File.join(repository_path, "README.md")) }
  end

  def successful_fetch_observation
    remote_oid = advance_remote
    input = fetch_request
    result = invoke(input)
    evidence = { "schema_version" => "1", "repository" => input.fetch("repository"),
      "effect" => input.fetch("effect"), "remote" => "origin", "ref" => "refs/heads/main",
      "observed_oid" => remote_oid }
    [ result.slice("remote", "ref", "observed_oid"), result.fetch("evidence_digest") ]
      .zip([ { "remote" => "origin", "ref" => "refs/heads/main", "observed_oid" => remote_oid },
        digest(canonical_json(evidence)) ]).map { |actual, expected| actual == expected }
  end

  def successful_fetch_expectation
    [ true, true ]
  end

  def fetch_side_effect_observation
    remote_oid = advance_remote
    configure_fetch_side_effect_traps
    before = repository_state
    invoke(fetch_request)
    [ repository_state == before, git(repository_path, "cat-file", "-t", remote_oid),
      git(repository_path, "show-ref", "--verify", "--quiet", "refs/heads/hijacked/main", allow_failure: true) ]
  end

  def fetch_mismatch_results
    base = fetch_request
    inputs = [ base.merge("effect" => base.fetch("effect").merge("repository_id" => reservation_id)),
      fetch_request_with("remote" => "upstream"), fetch_request_with("ref" => "refs/heads/other"),
      base.merge("repository" => base.fetch("repository").merge(
        "trusted_remote_url" => "file:///not-the-configured-remote.git")) ]
    inputs.map do |input|
      document, status = run(input)
      [ status, document.dig("error", "code") ]
    end + [ File.exist?(File.join(common_dir, "FETCH_HEAD")) ]
  end

  def fetch_request_with(effect_fields)
    input = fetch_request
    durable = input.dig("effect", "request")
    durable["effect"] = durable.fetch("effect").merge(effect_fields)
    input.fetch("effect")["request_digest"] = digest(canonical_json(durable))
    input
  end

  def fetch_digest_mismatch_results
    remote_oid = advance_remote
    base = fetch_request
    durable = base.dig("effect", "request")
    requests = [ durable.merge("attempt_id" => reservation_id),
      durable.merge("input_context_digest" => "sha256:#{'b' * 64}"),
      durable.merge("effect" => durable.fetch("effect").merge("remote" => "upstream")),
      durable.merge("effect" => durable.fetch("effect").merge("ref" => "refs/heads/other")) ]
    results = requests.map do |changed|
      document, status = run(base.merge("effect" => base.fetch("effect").merge("request" => changed)))
      [ status, document.dig("error", "code") ]
    end
    results + [ File.exist?(File.join(common_dir, "FETCH_HEAD")),
      git(repository_path, "cat-file", "-t", remote_oid, allow_failure: true) ]
  end

  def closed_fetch_failure
    input = fetch_request
    missing_url = "file://#{File.join(directory, 'missing-secret-remote.git')}"
    git(repository_path, "config", "--replace-all", "remote.origin.url", missing_url)
    input.fetch("repository")["trusted_remote_url"] = missing_url
    document, status = run(input)
    serialized = JSON.generate(document)
    [ status, document.dig("error", "code"), document.dig("error", "retryable"),
      serialized.include?(directory), serialized.include?(missing_url), serialized.include?("fatal:") ]
  end

  def bundle_uri_rejection
    input = fetch_request
    trap_uri = "file://#{File.join(directory, 'untrusted-bundle-list')}"
    git(repository_path, "config", "fetch.bundleURI", trap_uri)
    adapter, calls = recording_git
    error = capture_operation_error(Kos::Repository::Fetch.new(input, git: adapter))
    [ error.code, fetch_called?(calls), File.exist?(File.join(common_dir, "FETCH_HEAD")) ]
  end

  def http_endpoint_override_results
    input = fetch_request
    adapter, calls = recording_git
    values = { "http.proxy" => "file:///untrusted-proxy", "http.curloptResolve" => "host:443:127.0.0.2",
      "http.followRedirects" => "true" }
    results = values.map do |key, value|
      git(repository_path, "config", key, value)
      error = capture_operation_error(Kos::Repository::Fetch.new(input, git: adapter))
      git(repository_path, "config", "--unset-all", key)
      error.code
    end
    results + [ fetch_called?(calls) ]
  end

  def promisor_configuration_results
    input = fetch_request
    adapter, calls = recording_git
    values = { "promisor.acceptFromServer" => "all", "remote.origin.promisor" => "true",
      "remote.origin.partialCloneFilter" => "blob:none", "extensions.partialClone" => "origin" }
    results = values.map do |key, value|
      git(repository_path, "config", "core.repositoryFormatVersion", "1") if key == "extensions.partialClone"
      git(repository_path, "config", key, value)
      error = capture_operation_error(Kos::Repository::Fetch.new(input, git: adapter))
      git(repository_path, "config", "--unset-all", key)
      error.code
    end
    results + [ fetch_called?(calls) ]
  end

  def fetch_process_overrides
    advance_remote
    adapter, calls = recording_git
    Kos::Repository::Fetch.new(fetch_request, git: adapter).call
    arguments = calls.find { |call| call.include?("fetch") }
    [ arguments.each_cons(2).include?([ "-c", "http.followRedirects=false" ]),
      arguments.each_cons(2).include?([ "-c", "credential.helper=" ]),
      arguments.each_cons(2).include?([ "-c", "promisor.acceptFromServer=none" ]) ]
  end

  def invalid_trusted_url_results
    urls = [ "ssh://user%3Asecret@example.test/repo.git", "ssh://user%40other@example.test/repo.git",
      "https://user@example.test/repo.git" ]
    adapter, calls = recording_git
    results = urls.map do |url|
      input = fetch_request
      git(repository_path, "config", "--replace-all", "remote.origin.url", url)
      input.fetch("repository")["trusted_remote_url"] = url
      capture_operation_error(Kos::Repository::Fetch.new(input, git: adapter)).code
    end
    results + [ fetch_called?(calls) ]
  end

  def ssh_username_result
    url = "ssh://git@example.test/repo.git"
    input = fetch_request
    git(repository_path, "config", "--replace-all", "remote.origin.url", url)
    input.fetch("repository")["trusted_remote_url"] = url
    adapter, calls = recording_git(fetch_success: false)
    error = capture_operation_error(Kos::Repository::Fetch.new(input, git: adapter))
    [ error.code, fetch_called?(calls) ]
  end

  def invalid_file_url_result
    input = fetch_request
    url = "file://mirror.example.test"
    git(repository_path, "config", "--replace-all", "remote.origin.url", url)
    input.fetch("repository")["trusted_remote_url"] = url
    adapter, calls = recording_git
    error = capture_operation_error(Kos::Repository::Fetch.new(input, git: adapter))
    [ error.code, fetch_called?(calls) ]
  end

  def non_repository_lock_observation
    path = File.join(directory, "not-a-git-repository")
    FileUtils.mkdir_p(path)
    input = fetch_request
    input.fetch("repository")["git_common_dir"] = path
    document, status = run(input)
    [ status, document.dig("error", "code"), File.exist?(File.join(path, "kos-repository.lock")) ]
  end

  def recording_git(fetch_success: nil)
    adapter = Kos::Repository::Git.new
    calls = []
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      calls << arguments
      if !fetch_success.nil? && arguments.include?("fetch")
        Kos::Repository::Git::Result.new("", fetch_success)
      else
        original.call(*arguments, **options)
      end
    end
    [ adapter, calls ]
  end

  def fetch_called?(calls)
    calls.any? { |arguments| arguments.include?("fetch") }
  end

  def fetch_lock_observation
    remote_oid = advance_remote
    lock = File.open(File.join(common_dir, "kos-repository.lock"), File::RDWR | File::CREAT, 0o600)
    lock.flock(File::LOCK_EX)
    worker = Thread.new { Kos::Repository::Fetch.new(fetch_request).call }
    sleep 0.05
    blocked = worker.alive?
    object_before_unlock = git(repository_path, "cat-file", "-t", remote_oid, allow_failure: true)
    lock.flock(File::LOCK_UN)
    [ blocked, object_before_unlock, worker.value.fetch("observed_oid") == remote_oid ]
  ensure
    lock&.close
  end

  def prepare_remote
    return if File.directory?(remote_path)

    FileUtils.mkdir_p(remote_path)
    git(remote_path, "init", "--bare", "--initial-branch=main")
    git(repository_path, "remote", "add", "origin", remote_url)
    git(repository_path, "push", "origin", "refs/heads/main:refs/heads/main")
  end

  def advance_remote
    prepare_remote
    publisher = File.join(directory, "publisher")
    git(directory, "clone", remote_url, publisher)
    git(publisher, "config", "user.name", "KOS Remote Test")
    git(publisher, "config", "user.email", "remote@example.test")
    File.write(File.join(publisher, "remote.txt"), "remote change\n")
    git(publisher, "add", "remote.txt")
    git(publisher, "commit", "-m", "Advance remote")
    git(publisher, "tag", "remote-only-tag")
    git(publisher, "push", "origin", "refs/heads/main:refs/heads/main", "refs/tags/remote-only-tag")
    head_sha_for(publisher)
  end

  def advance_remote_readme
    prepare_remote
    publisher = File.join(directory, "conflicting-publisher")
    git(directory, "clone", remote_url, publisher)
    git(publisher, "config", "user.name", "KOS Remote Test")
    git(publisher, "config", "user.email", "remote@example.test")
    File.write(File.join(publisher, "README.md"), "remote conflict\n")
    git(publisher, "add", "README.md")
    git(publisher, "commit", "-m", "Conflict remotely")
    git(publisher, "push", "origin", "refs/heads/main:refs/heads/main")
    head_sha_for(publisher)
  end

  def rebase_metadata_paths
    Kos::Repository::Worktree::OPERATION_PATHS.map do |name|
      git(worktree_path, "rev-parse", "--git-path", name).strip
    end
  end

  def remote_url
    "file://#{remote_path}"
  end

  def configure_fetch_side_effect_traps
    git(repository_path, "config", "--replace-all", "remote.origin.fetch",
      "+refs/heads/*:refs/heads/hijacked/*")
    git(repository_path, "config", "remote.origin.tagOpt", "--tags")
    git(repository_path, "config", "fetch.prune", "true")
    git(repository_path, "config", "fetch.pruneTags", "true")
    git(repository_path, "config", "fetch.recurseSubmodules", "true")
    git(repository_path, "config", "maintenance.auto", "1")
  end

  def repository_state
    { refs: git(repository_path, "for-each-ref", "--format=%(refname) %(objectname)"),
      worktrees: git(repository_path, "worktree", "list", "--porcelain"),
      index: File.binread(File.join(common_dir, "index")),
      status: git(repository_path, "status", "--porcelain=v2", "--untracked-files=all", "--ignored=matching"),
      readme: File.binread(File.join(repository_path, "README.md")) }
  end

  def configured_override_observation
    input = fetch_request
    git(repository_path, "config", "url.file:///redirected/.insteadOf", remote_url)
    redirected = run(input).first
    git(repository_path, "config", "--unset-all", "url.file:///redirected/.insteadOf")
    executable_results = executable_fetch_override_results(input)
    [ redirected.dig("error", "code"), *executable_results,
      File.exist?(File.join(common_dir, "FETCH_HEAD")) ]
  end

  def executable_fetch_override_results(input)
    trigger = executable_fetch_trap
    keys = %w[remote.origin.uploadpack remote.origin.vcs core.gitProxy core.sshCommand remote.origin.proxy
      core.alternateRefsCommand core.askPass]
    results = keys.map do |key|
      git(repository_path, "config", key, trigger.fetch("script"))
      document = run(input).first
      git(repository_path, "config", "--unset-all", key)
      document.dig("error", "code")
    end
    results + [ File.exist?(trigger.fetch("path")) ]
  end

  def executable_fetch_trap
    path = File.join(directory, "transport-override-ran")
    script = File.join(directory, "transport-override")
    File.write(script, "#!/bin/sh\ntouch '#{path}'\nexit 1\n")
    File.chmod(0o700, script)
    { "path" => path, "script" => script }
  end

  def git_writing_ambiguous_fetch_head
    adapter = Kos::Repository::Git.new
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      result = original.call(*arguments, **options)
      if arguments.include?("fetch") && result.success
        fetch_head = File.join(common_dir, "FETCH_HEAD")
        File.binwrite(fetch_head, File.binread(fetch_head) * 2)
      end
      result
    end
    adapter
  end

  def git_rewriting_fetch_head_ref
    adapter = Kos::Repository::Git.new
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      result = original.call(*arguments, **options)
      if arguments.include?("fetch") && result.success
        oid = File.binread(File.join(common_dir, "FETCH_HEAD")).split("\t", 2).first
        File.binwrite(File.join(common_dir, "FETCH_HEAD"), "#{oid}\t\tbranch 'other' of hidden\n")
      end
      result
    end
    adapter
  end

  def canonical_json(value)
    case value
    when Hash
      "{#{value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(',')}}"
    when Array then "[#{value.map { |item| canonical_json(item) }.join(',')}]"
    else JSON.generate(value)
    end
  end

  def prepared_commit_request(paths)
    sorted = paths.sort_by(&:b)
    diff = isolated_git("--literal-pathspecs", "-C", worktree_path, "diff", "--binary", "--full-index",
      "--no-ext-diff", "--no-textconv", head_sha, "--", *sorted)
    git(worktree_path, "add", "--all", "--", *sorted)
    entries = normalized_index_entries(sorted)
    git(worktree_path, "reset", "--mixed", head_sha)
    commit_request(paths).merge("expected_diff_digest" => digest(diff), "expected_index_digest" => digest(entries))
  end

  def materialize
    invoke(request("materialize", "reserved"))
  end

  def changed_readme_request
    materialize
    File.write(File.join(worktree_path, "README.md"), "changed\n")
    prepared_commit_request([ "README.md" ])
  end

  def executable_readme_request(filemode:)
    materialize
    git(worktree_path, "config", "core.filemode", filemode.to_s)
    File.write(File.join(worktree_path, "README.md"), "executable\n")
    File.chmod(0o755, File.join(worktree_path, "README.md"))
    prepared_commit_request([ "README.md" ])
  end

  def deleted_readme_request
    materialize
    FileUtils.rm(File.join(worktree_path, "README.md"))
    prepared_commit_request([ "README.md" ])
  end

  def nested_deletion_request
    add_base_file("nested/file.txt", "nested\n")
    materialize
    FileUtils.rm_r(File.join(worktree_path, "nested"))
    prepared_commit_request([ "nested/file.txt" ])
  end

  def changed_nested_file_request
    add_base_file("nested/file.txt", "nested\n")
    materialize
    File.write(File.join(worktree_path, "nested", "file.txt"), "changed nested\n")
    prepared_commit_request([ "nested/file.txt" ])
  end

  def deleted_symlink_request
    add_base_symlink
    materialize
    File.unlink(File.join(worktree_path, "linked.txt"))
    commit_request([ "linked.txt" ])
  end

  def replaced_symlink_request
    add_base_symlink
    materialize
    File.unlink(File.join(worktree_path, "linked.txt"))
    File.write(File.join(worktree_path, "linked.txt"), "regular\n")
    commit_request([ "linked.txt" ])
  end

  def add_base_symlink
    File.symlink("README.md", File.join(repository_path, "linked.txt"))
    git(repository_path, "add", "linked.txt")
    git(repository_path, "commit", "-m", "Add symlink")
  end

  def add_base_file(path, content)
    absolute = File.join(repository_path, path)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, content)
    git(repository_path, "add", path)
    git(repository_path, "commit", "-m", "Add #{path}")
  end

  def corrupt_reservation_marker
    metadata = git(worktree_path, "rev-parse", "--path-format=absolute", "--git-dir").strip
    marker = File.join(metadata, Kos::Repository::Worktree::MARKER_NAME)
    File.write(marker, JSON.generate("schema_version" => "1"))
  end

  def changed_readme_without_identity
    changed_readme_request.tap do
      git(repository_path, "config", "--unset-all", "user.name")
      git(repository_path, "config", "--unset-all", "user.email")
    end
  end

  def changed_readme_with_unfinished_merge
    changed_readme_request.tap do
      File.write(git(worktree_path, "rev-parse", "--git-path", "MERGE_HEAD").strip, "#{head_sha}\n")
    end
  end

  def expect_preserved_changed_readme
    expect(File.read(File.join(worktree_path, "README.md"))).to eq("changed\n")
    expect(head_sha_for(worktree_path)).to eq(head_sha)
  end

  def unsafe_commit_paths
    materialize
    FileUtils.mkdir_p(File.join(worktree_path, "directory"))
    File.write(File.join(worktree_path, "directory", "file.txt"), "content\n")
    File.symlink("README.md", File.join(worktree_path, "alias"))
    { [ "directory" ] => "commit_path_invalid", [ "alias" ] => "commit_path_invalid",
      [ ":(glob)*" ] => "malformed_input", [ "directory", "directory/file.txt" ] => "commit_path_invalid" }
  end

  def prepare_with_unrelated_staged_change
    input = changed_readme_request
    File.write(File.join(worktree_path, "staged.txt"), "unrelated\n")
    git(worktree_path, "add", "staged.txt")
    input
  end

  def commit_two_of_three_changes
    materialize
    File.write(File.join(worktree_path, "README.md"), "committed\n")
    File.write(File.join(worktree_path, "new.txt"), "new\n")
    File.write(File.join(worktree_path, "unrequested.txt"), "preserve\n")
    invoke(prepared_commit_request([ "new.txt", "README.md" ]))
  end

  def commit_with_concurrent_unrelated_stage
    input = changed_readme_request
    File.write(File.join(worktree_path, "unrelated.txt"), "concurrent\n")
    Kos::Repository::Commit.new(input, git: git_injecting_unrelated_stage).call
  end

  def commit_with_occupied_index_lock
    input = changed_readme_request
    index_path = git(worktree_path, "rev-parse", "--git-path", "index").strip
    index_bytes = File.binread(index_path)
    lock_path = "#{index_path}.lock"
    lock_bytes = "competing index lock\n"
    File.binwrite(lock_path, lock_bytes)
    result = Kos::Repository::Commit.new(input).call
    [ result, index_path, index_bytes, lock_path, lock_bytes ]
  end

  def filtered_readme_request
    trigger = configure_clean_filter_trap
    File.write(File.join(worktree_path, "README.md"), "changed\n")
    [ commit_request([ "README.md" ]), trigger ]
  end

  def expect_successful_exact_commit(result)
    commit_sha = result.fetch("commit_sha")
    expect(commit_sha).to eq(head_sha_for(worktree_path))
    expect(git(worktree_path, "rev-parse", "#{commit_sha}^").strip).to eq(head_sha)
    expect(committed_paths(commit_sha)).to eq([ "README.md", "new.txt" ])
    expect(task_trailers(commit_sha)).to eq([ "KOS-000123" ])
    expect(git(worktree_path, "diff", "--cached", "--quiet")).to be_empty
    expect(File.read(File.join(worktree_path, "unrequested.txt"))).to eq("preserve\n")
    expect(result.fetch("evidence_digest")).to match(/\Asha256:[0-9a-f]{64}\z/)
  end

  def committed_paths(commit_sha)
    git(worktree_path, "diff-tree", "--no-commit-id", "--name-only", "-r", commit_sha).lines.map(&:strip).sort
  end

  def task_trailers(commit_sha)
    git(worktree_path, "show", "-s", "--format=%(trailers:key=KOS-Task,valueonly)", commit_sha)
      .lines.map(&:strip).reject(&:empty?)
  end

  def tree_mode(commit_sha, path)
    git(worktree_path, "ls-tree", commit_sha, "--", path).split.first
  end

  def normalized_index_entries(paths)
    git(worktree_path, "ls-files", "--stage", "-z", "--", *paths).split("\0", -1).reject(&:empty?).map do |entry|
      mode, oid, stage_and_path = entry.split(" ", 3)
      stage, path = stage_and_path.split("\t", 2)
      raise "unexpected index stage #{stage}" unless stage == "0"

      "#{mode} #{oid}\t#{path}"
    end.sort_by(&:b).join("\0").then { |entries| entries.empty? ? entries : "#{entries}\0" }
  end

  def digest(value)
    "sha256:#{Digest::SHA256.hexdigest(value)}"
  end

  def isolated_git(*arguments)
    result = Kos::Repository::Git.new.call(*arguments)
    raise "isolated git failed" unless result.success

    result.stdout
  end

  def index_entries
    git(worktree_path, "diff", "--cached", "--name-only").lines.map(&:strip)
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

  def configure_commit_traps
    trigger = File.join(directory, "forbidden-command-ran")
    script = File.join(directory, "forbidden-command")
    File.write(script, "#!/bin/sh\ntouch '#{trigger}'\nexit 1\n")
    File.chmod(0o700, script)
    hooks = File.join(directory, "hooks")
    FileUtils.mkdir_p(hooks)
    FileUtils.cp(script, File.join(hooks, "pre-commit"))
    git(repository_path, "config", "core.hooksPath", hooks)
    git(repository_path, "config", "core.editor", script)
    git(repository_path, "config", "diff.external", script)
    git(repository_path, "config", "commit.gpgSign", "true")
    git(repository_path, "config", "gpg.program", script)
    trigger
  end

  def configure_textconv_trap
    trigger = File.join(directory, "textconv-ran")
    script = File.join(directory, "textconv")
    File.write(script, "#!/bin/sh\ntouch '#{trigger}'\ncat \"$1\"\n")
    File.chmod(0o700, script)
    File.write(File.join(repository_path, ".gitattributes"), "README.md diff=kos-trap\n")
    git(repository_path, "add", ".gitattributes")
    git(repository_path, "commit", "-m", "Configure attributes")
    git(repository_path, "config", "diff.kos-trap.textconv", script)
    File.write(File.join(repository_path, "README.md"), "textconv probe\n")
    isolated_git("-C", repository_path, "diff", "--textconv", "HEAD", "--", "README.md")
    raise "textconv trap was not configured" unless File.exist?(trigger)

    File.unlink(trigger)
    File.write(File.join(repository_path, "README.md"), "initial\n")
    trigger
  end

  def configure_clean_filter_trap
    trigger = File.join(directory, "clean-filter-ran")
    script = File.join(directory, "clean-filter")
    File.write(script, "#!/bin/sh\ntouch '#{trigger}'\ncat\n")
    File.chmod(0o700, script)
    File.write(File.join(repository_path, ".gitattributes"), "README.md filter=kos-trap\n")
    git(repository_path, "add", ".gitattributes")
    git(repository_path, "commit", "-m", "Configure filter attributes")
    materialize
    git(repository_path, "config", "filter.kos-trap.clean", script)
    trigger
  end

  def git_injecting_unrelated_stage
    adapter = Kos::Repository::Git.new
    injected = false
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      if options.fetch(:environment, {}).key?("GIT_INDEX_FILE") && !injected
        injected = true
        git(worktree_path, "add", "unrelated.txt")
      end
      original.call(*arguments, **options)
    end
    adapter
  end

  def git_injecting_filter_after_initial_check
    trigger = File.join(directory, "late-clean-filter-ran")
    script = File.join(directory, "late-clean-filter")
    File.write(script, "#!/bin/sh\ntouch '#{trigger}'\ncat\n")
    File.chmod(0o700, script)
    adapter = Kos::Repository::Git.new
    injected = false
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      result = original.call(*arguments, **options)
      if arguments.include?("check-attr") && !injected
        injected = true
        File.write(File.join(worktree_path, ".gitattributes"), "README.md filter=late-trap\n")
        git(repository_path, "config", "filter.late-trap.clean", script)
      end
      result
    end
    [ adapter, trigger ]
  end

  def git_swapping_nested_directory_before_staging
    outside = File.join(directory, "outside")
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, "file.txt"), "outside content\n")
    state = { hash_called: false, swapped: false }
    adapter = Kos::Repository::Git.new
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      result = original.call(*arguments, **options)
      state[:hash_called] = true if arguments.include?("hash-object")
      swap_nested_directory(outside, state) if options.fetch(:environment, {}).key?("GIT_INDEX_FILE") &&
        arguments.include?("read-tree") && !state.fetch(:swapped)
      result
    end
    [ adapter, state ]
  end

  def commit_with_nested_swap_and_restore(input)
    outside = File.join(directory, "swap-outside")
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, "file.txt"), "outside swap content\n")
    state = { hash_called: false, restored: false }
    adapter = Kos::Repository::Git.new
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      state[:hash_called] = true if arguments.include?("hash-object")
      original.call(*arguments, **options)
    end
    operation = Kos::Repository::Commit.new(input, git: adapter)
    allow(operation).to receive(:open_relative_component).and_wrap_original do |original, parent, component, directory:|
      next original.call(parent, component, directory: directory) unless component == "nested"

      swap_nested_directory(outside, state)
      begin
        original.call(parent, component, directory: directory)
      ensure
        restore_nested_directory(state)
      end
    end
    [ capture_operation_error(operation), state ]
  end

  def swap_nested_directory(outside, state)
    nested = File.join(worktree_path, "nested")
    File.rename(nested, File.join(worktree_path, "nested-original"))
    File.symlink(outside, nested)
    state[:swapped] = true
  end

  def restore_nested_directory(state)
    nested = File.join(worktree_path, "nested")
    File.unlink(nested)
    File.rename(File.join(worktree_path, "nested-original"), nested)
    state[:restored] = true
  end

  def git_losing_ref_update_response
    adapter = Kos::Repository::Git.new
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      result = original.call(*arguments, **options)
      arguments.include?("update-ref") ? Kos::Repository::Git::Result.new(result.stdout, false) : result
    end
    adapter
  end

  def git_timing_out_after_ref_update
    adapter = Kos::Repository::Git.new
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      result = original.call(*arguments, **options)
      raise Kos::Repository::Error.new("transient", "git_timeout", "Git operation timed out", retryable: true) if
        arguments.include?("update-ref") && result.success

      result
    end
    adapter
  end

  def git_hiding_failed_ref_update
    adapter = Kos::Repository::Git.new
    update_failed = false
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      if arguments.include?("update-ref")
        update_failed = true
        Kos::Repository::Git::Result.new("", false)
      elsif update_failed && arguments.include?("#{reserved_ref}^{commit}")
        Kos::Repository::Git::Result.new("", false)
      else
        original.call(*arguments, **options)
      end
    end
    adapter
  end

  def git_failing_post_cas_observation
    adapter = Kos::Repository::Git.new
    updated = false
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      raise Kos::Repository::Error.new("internal", "internal_error", "Observation failed") if
        updated && arguments.include?("#{reserved_ref}^{commit}")

      original.call(*arguments, **options).tap { |result| updated = true if arguments.include?("update-ref") && result.success }
    end
    adapter
  end

  def git_advancing_reserved_ref(commit_sha)
    adapter = Kos::Repository::Git.new
    advanced = false
    allow(adapter).to receive(:call).and_wrap_original do |original, *arguments, **options|
      if arguments.include?("update-ref") && !advanced
        advanced = true
        git(repository_path, "update-ref", "refs/heads/kos/task-KOS-000123", commit_sha, head_sha)
      end
      original.call(*arguments, **options)
    end
    adapter
  end

  def create_concurrent_commit
    tree = git(worktree_path, "rev-parse", "#{head_sha}^{tree}").strip
    git(worktree_path, "commit-tree", tree, "-p", head_sha, "-m", "Concurrent commit").strip
  end

  def capture_commit_error(input, adapter)
    Kos::Repository::Commit.new(input, git: adapter).call
  rescue Kos::Repository::Error => error
    error
  end


  def capture_operation_error(operation)
    operation.call
  rescue Kos::Repository::Error => error
    error
  end

  def reserved_ref
    "refs/heads/kos/task-KOS-000123"
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

  def concurrent_commits(input)
    ready = Queue.new
    start = Queue.new
    workers = 2.times.map do
      Thread.new do
        ready << true
        start.pop
        run(input)
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

  def git(path, *arguments, allow_failure: false)
    stdout, stderr, status = Open3.capture3("git", "-C", path, *arguments)
    raise stderr unless status.success? || allow_failure

    stdout
  end
end
