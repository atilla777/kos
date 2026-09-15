require "json"
require "open3"
require "rails_helper"
require "tmpdir"

RSpec.describe Publications::RecoverBaseMoved, :aggregate_failures do
  def root = File.expand_path("../../..", __dir__)

  def run_script(environment, script)
    output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "runner", script)
    expect(status).to be_success, output
    JSON.parse(output.lines.last)
  end

  def prepare_state(environment, moved: true)
    helper = File.join(root, "spec/support/publication_preflight_helpers.rb")
    catalog = File.join(root, "spec/support/workflow_catalog_helpers.rb")
    workflow = File.join(root, "workflows/quick-fix/1.0.2.json")
    run_script(environment, <<~RUBY)
      require #{helper.dump}
      require #{catalog.dump}
      support = Object.new.extend(PublicationPreflightHelpers).extend(WorkflowCatalogHelpers)
      definition = JSON.parse(File.read(#{workflow.dump}))
      repository = Repository.create!(git_common_dir: "/tmp/recovery-process.git", task_prefix: "KOS",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      version = support.publish_workflow(definition)
      task = Task.create!(repository: repository, sequence: 1, title: "Concurrent recovery",
        task_input_schema_version: "1", approved_brief: "Recover moved publication once.",
        task_type: support.quick_fix_task_type, workflow_version: version,
        workflow_state: version.workflow_states.find_by!(initial: true))
      now = Time.current.change(usec: 0) - 5
      support.advance_to_publication(task: task, version: version, candidate_sha: "a" * 40, now: now)
      attempt = WorkflowAttempts::Claim.call(repository: repository, task_number: task.number,
        owner_id: "publisher", lease_seconds: 300, expected_lock_version: task.reload.lock_version,
        idempotency_key: "process-recovery-claim", now: now)
      reservation = WorktreeReservation.create!(repository: repository, task: task, workflow_attempt: attempt,
        branch: "kos/task-" + task.number, path: "/tmp/worktrees/" + task.number, state: "confirmed",
        fencing_token: attempt.fencing_token, head_sha: "a" * 40,
        git_common_dir_digest: "sha256:" + "d" * 64, confirmed_at: now)
      task.reload.update!(worktree_reservation: reservation)
      publication = Publications::Prepare.call(repository: repository, task_number: task.number,
        candidate_sha: "a" * 40, remote: "origin", base_ref: "refs/heads/main",
        expected_remote_oid: "b" * 40, attempt_id: attempt.id, fencing_token: attempt.fencing_token,
        expected_lock_version: task.reload.lock_version, now: now)
      WorkflowSteps::CaptureContext.call(repository: repository, attempt_id: attempt.id,
        fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now: now)
      if #{moved}
        begin
          Publications::Reconcile.call(repository: repository, publication_id: publication.id,
            candidate_sha: "a" * 40, observed_remote_tip: "c" * 40, candidate_reachable: false,
            observed_at: now + 1, evidence_digest: "sha256:" + "e" * 64, attempt_id: attempt.id,
            fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now: now + 2)
        rescue CommittedOperationError
        end
      end
      puts JSON.generate({ repository_id: repository.id, publication_id: publication.id,
        attempt_id: attempt.id, fencing_token: attempt.fencing_token, task_lock: task.reload.lock_version })
    RUBY
  end

  def recovery_script
    <<~'RUBY'
      begin
        sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
        repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
        Publications::RecoverBaseMoved.call(repository: repository,
          publication_id: ENV.fetch("PUBLICATION_ID"), attempt_id: ENV.fetch("ATTEMPT_ID"),
          fencing_token: ENV.fetch("FENCING_TOKEN").to_i,
          expected_lock_version: ENV.fetch("TASK_LOCK").to_i)
        puts JSON.generate("status" => "recovered")
      rescue OperationError => error
        puts JSON.generate("error" => error.code)
      end
    RUBY
  end

  def reconciliation_script
    <<~'RUBY'
      begin
        sleep 0.01 until File.exist?(ENV.fetch("START_FILE"))
        repository = Repository.find(ENV.fetch("REPOSITORY_ID"))
        Publications::Reconcile.call(repository: repository, publication_id: ENV.fetch("PUBLICATION_ID"),
          candidate_sha: "a" * 40, observed_remote_tip: "c" * 40, candidate_reachable: false,
          observed_at: Time.current, evidence_digest: "sha256:" + "e" * 64,
          attempt_id: ENV.fetch("ATTEMPT_ID"), fencing_token: ENV.fetch("FENCING_TOKEN").to_i,
          expected_lock_version: ENV.fetch("TASK_LOCK").to_i)
      rescue CommittedOperationError => error
        puts JSON.generate("status" => error.code)
      rescue OperationError => error
        puts JSON.generate("error" => error.code)
      end
    RUBY
  end

  def concurrency_summary
    Dir.mktmpdir("kos-base-moved-recovery") do |directory|
      environment = { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3") }
      output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "db:prepare")
      expect(status).to be_success, output
      state = prepare_state(environment)
      start = File.join(directory, "start")
      common = state.transform_keys { _1.upcase }.transform_values(&:to_s).merge("START_FILE" => start)
      processes = 2.times.map do
        Open3.popen3(environment.merge(common), File.join(root, "bin/rails"), "runner", recovery_script)
      end
      File.write(start, "start")
      results = processes.map do |stdin, stdout, stderr, wait|
        stdin.close
        value = JSON.parse(stdout.read.lines.last)
        expect(wait.value).to be_success, stderr.read
        value
      end
      persisted = run_script(environment, <<~'RUBY')
        task = Task.first
        puts JSON.generate([task.workflow_state.identifier, task.active_attempt_id,
          WorkflowAttempt.where(state: "succeeded", completed_transition_id: WorkflowTransition.joins(:to_state)
            .where(workflow_states: { identifier: "base-synchronization" }).select(:id)).count])
      RUBY
      [ results, persisted ]
    end
  end

  it "takes the recovery transition at most once across processes" do
    results, persisted = concurrency_summary
    expect(results.count { _1["status"] == "recovered" }).to eq(1)
    expect(results.filter_map { _1["error"] }.first).to be_in(%w[stale_lock_version fencing_token_stale])
    expect(persisted).to eq([ "base-synchronization", nil, 1 ])
  end

  it "serializes publication reconciliation against recovery without a partial transition" do
    results, persisted = reconcile_recovery_race
    expect(results).to include("status" => "base_moved")
    expect(results.count { _1["status"] == "recovered" }).to be <= 1
    expect([ %w[publication base-synchronization].include?(persisted.first), persisted.last ]).to eq([ true, 1 ])
  end

  def reconcile_recovery_race
    Dir.mktmpdir("kos-reconcile-recovery-race") do |directory|
      environment = { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3") }
      output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "db:prepare")
      expect(status).to be_success, output
      state = prepare_state(environment, moved: false)
      start = File.join(directory, "start")
      common = state.transform_keys { _1.upcase }.transform_values(&:to_s).merge("START_FILE" => start)
      processes = [ reconciliation_script, recovery_script ].map do |script|
        Open3.popen3(environment.merge(common), File.join(root, "bin/rails"), "runner", script)
      end
      File.write(start, "start")
      results = processes.map { |process| process_result(process) }
      persisted = run_script(environment, <<~'RUBY')
        task = Task.first
        puts JSON.generate([task.workflow_state.identifier, task.active_attempt_id,
          Publication.first.state == "superseded" ? 1 : 0])
      RUBY
      [ results, persisted ]
    end
  end

  def process_result(process)
    stdin, stdout, stderr, wait = process
    stdin.close
    value = JSON.parse(stdout.read.lines.last)
    expect(wait.value).to be_success, stderr.read
    value
  end
end
