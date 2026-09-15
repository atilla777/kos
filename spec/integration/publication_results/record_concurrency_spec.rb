require "json"
require "open3"
require "rails_helper"
require "tmpdir"

RSpec.describe PublicationResults::Record, :aggregate_failures do
  def root = File.expand_path("../../..", __dir__)

  def run(environment, script)
    output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "runner", script)
    expect(status).to be_success, output
    JSON.parse(output.lines.last)
  end

  def prepare_state(environment)
    run(environment, <<~'RUBY')
      require Rails.root.join("lib/kos/push_evidence")
      require Rails.root.join("spec/support/publication_preflight_helpers")
      require Rails.root.join("spec/support/workflow_catalog_helpers")
      support = Object.new.extend(WorkflowCatalogHelpers).extend(PublicationPreflightHelpers)
      repository = Repository.create!(git_common_dir: "/tmp/publication-result-concurrency.git",
        task_prefix: "KOS", trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git",
        base_ref: "refs/heads/main")
      version = support.publish_workflow
      task = Task.create!(repository: repository, sequence: 1, title: "Concurrent result",
        task_input_schema_version: "1", approved_brief: "Record the publication result concurrently.",
        task_type: support.quick_fix_task_type, workflow_version: version,
        workflow_state: version.workflow_states.find_by!(initial: true))
      now = Time.current.change(usec: 0)
      candidate = "a" * 40
      support.advance_to_publication(task: task, version: version, candidate_sha: candidate, now: now)
      attempt = WorkflowAttempts::Claim.call(repository: repository, task_number: task.number,
        owner_id: "publisher", lease_seconds: 300, expected_lock_version: task.reload.lock_version,
        idempotency_key: "concurrent-result-claim", now: now)
      reservation = WorktreeReservation.create!(repository: repository, task: task, workflow_attempt: attempt,
        branch: "kos/task-#{task.number}", path: "/tmp/worktrees/#{task.number}", state: "confirmed",
        fencing_token: attempt.fencing_token, head_sha: candidate,
        git_common_dir_digest: "sha256:" + ("b" * 64), confirmed_at: now)
      task.reload.update!(worktree_reservation: reservation)
      publication = Publications::Prepare.call(repository: repository, task_number: task.number,
        candidate_sha: candidate, remote: repository.trusted_remote, base_ref: repository.base_ref,
        expected_remote_oid: "c" * 40, attempt_id: attempt.id, fencing_token: attempt.fencing_token,
        expected_lock_version: task.reload.lock_version, now: now)
      WorkflowSteps::CaptureContext.call(repository: repository, attempt_id: attempt.id,
        fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now: now)
      attempt.reload
      observed_at = (now + 1).utc.iso8601(6)
      repository_snapshot = { "id" => repository.id, "git_common_dir" => repository.git_common_dir,
        "trusted_remote" => repository.trusted_remote, "trusted_remote_url" => repository.trusted_remote_url,
        "base_ref" => repository.base_ref }
      publication_snapshot = { "id" => publication.id, "repository_id" => repository.id,
        "current_owner_attempt_id" => attempt.id, "fencing_token" => attempt.fencing_token,
        "input_context_digest" => attempt.input_context_digest, "candidate_sha" => candidate,
        "remote" => publication.remote, "base_ref" => publication.base_ref,
        "expected_remote_oid" => publication.expected_remote_oid }
      digest = Kos::PushEvidence.digest(repository: repository_snapshot, publication: publication_snapshot,
        candidate_sha: candidate, remote: publication.remote, base_ref: publication.base_ref,
        observed_remote_tip: "d" * 40, candidate_reachable: true, observed_at: observed_at)
      Publications::Reconcile.call(repository: repository, publication_id: publication.id,
        candidate_sha: candidate, observed_remote_tip: "d" * 40, candidate_reachable: true,
        observed_at: observed_at, evidence_digest: digest, attempt_id: attempt.id,
        fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now: now + 2)
      manifest = { "schema_version" => "1", "attempt_id" => attempt.id,
        "input_context_digest" => attempt.input_context_digest, "outcome" => "succeeded", "artifacts" => [
          { "schema_version" => "1", "type" => "publication", "state" => "published",
            "producer" => "workflow-step", "metadata" => { "kind" => "publication",
              "publication_id" => publication.id, "candidate_sha" => candidate,
              "remote" => publication.remote, "base_ref" => publication.base_ref,
              "observed_remote_tip" => "d" * 40, "reachable" => true, "observed_at" => observed_at } }
        ] }
      puts JSON.generate(repository_id: repository.id, publication_id: publication.id,
        attempt_id: attempt.id, fencing_token: attempt.fencing_token, lock_version: task.reload.lock_version,
        result_manifest: manifest)
    RUBY
  end

  def contender_script
    <<~'RUBY'
      sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
      state = JSON.parse(ENV.fetch("STATE"))
      result = PublicationResults::Record.call(repository: Repository.find(state.fetch("repository_id")),
        publication_id: state.fetch("publication_id"), result_manifest: state.fetch("result_manifest"),
        attempt_id: state.fetch("attempt_id"), fencing_token: state.fetch("fencing_token"),
        expected_lock_version: state.fetch("lock_version"))
      puts JSON.generate(id: result.id)
    RUBY
  end

  it "creates one immutable result when identical recordings race" do
    expect(concurrent_summary).to eq([ 1, 1 ])
  end

  def concurrent_summary
    Dir.mktmpdir("kos-publication-result-concurrency") do |directory|
      environment = { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3") }
      run(environment, "ActiveRecord::Tasks::DatabaseTasks.prepare_all; puts JSON.generate(true)")
      state = prepare_state(environment)
      start_file = File.join(directory, "start")
      contenders = 2.times.map do
        Open3.popen3(environment.merge("STATE" => JSON.generate(state), "START_FILE" => start_file),
          File.join(root, "bin/rails"), "runner", contender_script)
      end
      File.write(start_file, "start")
      ids = contenders.map { |stdin, stdout, stderr, wait| contender_result(stdin, stdout, stderr, wait) }
      [ ids.uniq.length, run(environment, "puts JSON.generate(PublicationResult.count)") ]
    end
  end

  def contender_result(stdin, stdout, stderr, wait)
    stdin.close
    output = stdout.read
    diagnostics = stderr.read
    expect(wait.value).to be_success, diagnostics
    JSON.parse(output.lines.last).fetch("id")
  end
end
