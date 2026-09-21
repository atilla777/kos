require "test_helper"
require "timeout"

class TaskLifecycleTest < ActiveSupport::TestCase
  setup do
    @now = Time.zone.local(2026, 9, 19, 12)
    @lifecycle = TaskLifecycle.new(clock: -> { @now }, lease_duration: 2.hours)
  end

  test "creates a task with the task type workflow and its first step" do
    project = create_project
    original_workflow = create_workflow
    task_type = create_task_type(workflow: original_workflow)

    task = @lifecycle.create!(project:, task_type:, title: "Lifecycle", description_markdown: "Description")

    assert_equal original_workflow, task.workflow
    assert_equal "develop", task.current_step
    assert_equal "pending", task.status
    assert_equal 0, task.claim_version
  end

  test "creates blockers atomically" do
    project = create_project
    workflow = create_workflow
    task_type = create_task_type(workflow:)
    blocker = create_task(project:, workflow:, task_type:)

    task = @lifecycle.create!(project:, task_type:, title: "Blocked", description_markdown: "Description",
      blockers: [ blocker ])

    assert_equal [ blocker ], task.blockers
  end

  test "rolls task creation back when a blocker is invalid" do
    project = create_project
    workflow = create_workflow
    task_type = create_task_type(workflow:)
    other_project_blocker = create_task

    assert_no_difference -> { project.tasks.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        @lifecycle.create!(project:, task_type:, title: "Invalid", description_markdown: "Description",
          blockers: [ other_project_blocker ])
      end
    end
  end

  test "snapshots the task type workflow at creation" do
    project = create_project
    original_workflow = create_workflow(name: "Original")
    replacement_workflow = create_workflow(name: "Replacement")
    task_type = create_task_type(workflow: original_workflow)

    first = @lifecycle.create!(project:, task_type:, title: "First", description_markdown: "Description")
    task_type.update!(workflow: replacement_workflow)
    second = @lifecycle.create!(project:, task_type:, title: "Second", description_markdown: "Description")

    assert_equal original_workflow, first.reload.workflow
    assert_equal replacement_workflow, second.workflow
  end

  test "show reads without changing ownership" do
    task = create_task

    shown = @lifecycle.show!(task.id)

    assert_equal task, shown
    assert_equal 0, shown.claim_version
    assert_nil shown.owner_id
  end

  test "claim next chooses the oldest available task and records a fenced lease" do
    project = create_project
    blocker = create_task(project:, title: "Blocker")
    @lifecycle.cancel!(task_id: blocker.id)
    blocked = create_task(project:, title: "Blocked")
    TaskDependency.create!(task: blocked, blocker:)
    available = create_task(project:, title: "Available")

    claimed = @lifecycle.claim_next!(project:, owner_id: "session-1")

    assert_equal available, claimed
    assert_equal "active", claimed.status
    assert_equal "session-1", claimed.owner_id
    assert_equal 1, claimed.claim_version
    assert_equal @now + 2.hours, claimed.lease_expires_at
    assert_nil @lifecycle.claim_next!(project:, owner_id: "session-2")
  end

  test "cancelled blockers remain incomplete" do
    project = create_project
    blocker = create_task(project:)
    blocked = create_task(project:)
    TaskDependency.create!(task: blocked, blocker:)
    @lifecycle.cancel!(task_id: blocker.id)

    assert_nil @lifecycle.claim_next!(project:, owner_id: "session")
  end

  test "a completed blocker makes its dependent available" do
    project = create_project
    blocker = create_task(project:)
    blocked = create_task(project:)
    TaskDependency.create!(task: blocked, blocker:)
    claim = @lifecycle.claim_next!(project:, owner_id: "session")
    advanced = @lifecycle.report_attempt!(task_id: claim.id, owner_id: "session", claim_version: claim.claim_version,
      step: "develop", outcome: "ready")
    @lifecycle.report_attempt!(task_id: claim.id, owner_id: "session", claim_version: advanced.claim_version,
      step: "check", outcome: "passed")

    assert_equal blocked, @lifecycle.claim_next!(project:, owner_id: "session-2")
  end

  test "reports next steps pauses and completion" do
    task = claim_task(owner_id: "session")

    advanced = @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
      step: "develop", outcome: "ready")
    assert_equal "check", advanced.current_step
    assert_equal 2, advanced.claim_version
    assert_equal "active", advanced.status
    assert_equal "session", advanced.owner_id

    paused = @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 2,
      step: "check", outcome: "blocked")
    assert_equal "blocked", paused.status
    assert_equal "check", paused.current_step
    assert_equal 3, paused.claim_version
    assert_nil paused.owner_id
    assert_nil paused.lease_expires_at

    resumed = @lifecycle.resume!(task_id: task.id, owner_id: "session-2")
    completed = @lifecycle.report_attempt!(task_id: task.id, owner_id: "session-2",
      claim_version: resumed.claim_version, step: "check", outcome: "passed")
    assert_equal "completed", completed.status
    assert_nil completed.owner_id
  end

  test "rejects stale identity expired leases wrong steps and unknown outcomes without mutation" do
    task = claim_task(owner_id: "session")
    original = task.attributes

    invalid_reports = [
      { owner_id: "stale", claim_version: 1, step: "develop", outcome: "ready" },
      { owner_id: "session", claim_version: 0, step: "develop", outcome: "ready" },
      { owner_id: "session", claim_version: 1, step: "check", outcome: "passed" }
    ]
    invalid_reports.each do |report|
      assert_raises(TaskLifecycle::Conflict) { @lifecycle.report_attempt!(task_id: task.id, **report) }
      assert_equal original, task.reload.attributes
    end

    assert_raises(TaskLifecycle::InvalidTransition) do
      @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
        step: "develop", outcome: "missing")
    end
    assert_equal original, task.reload.attributes

    @now += 2.hours
    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
        step: "develop", outcome: "ready")
    end
    assert_equal original, task.reload.attributes
  end

  test "resume replaces paused or expired ownership but requires confirmation for a live owner" do
    task = claim_task(owner_id: "session-1")

    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.resume!(task_id: task.id, owner_id: "session-2")
    end
    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.resume!(task_id: task.id, owner_id: "session-2", takeover_confirmed: "true")
    end

    replaced = @lifecycle.resume!(task_id: task.id, owner_id: "session-2", takeover_confirmed: true)
    assert_equal 2, replaced.claim_version
    assert_equal "develop", replaced.current_step

    @now += 2.hours
    resumed = @lifecycle.resume!(task_id: task.id, owner_id: "session-3")
    assert_equal 3, resumed.claim_version
    assert_equal "session-3", resumed.owner_id
  end

  test "cancelling an active task fences and releases its owner" do
    task = claim_task(owner_id: "session")

    cancelled = @lifecycle.cancel!(task_id: task.id)

    assert_equal "cancelled", cancelled.status
    assert_equal 2, cancelled.claim_version
    assert_nil cancelled.owner_id
    assert_nil cancelled.lease_expires_at
    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
        step: "develop", outcome: "ready")
    end
  end

  test "terminal tasks cannot be resumed or cancelled" do
    task = claim_task(owner_id: "session")
    @lifecycle.cancel!(task_id: task.id)

    assert_raises(TaskLifecycle::Conflict) { @lifecycle.resume!(task_id: task.id, owner_id: "new") }
    assert_raises(TaskLifecycle::Conflict) { @lifecycle.cancel!(task_id: task.id) }
  end

  test "requires a non-empty owner" do
    project = create_project
    create_task(project:)

    assert_raises(ArgumentError) { @lifecycle.claim_next!(project:, owner_id: "") }
  end

  test "the same report cannot be accepted twice for a self-transition" do
    definition = valid_workflow_definition
    definition["steps"][0]["outcomes"]["again"] = { "next_step" => "develop" }
    project = create_project
    workflow = create_workflow(definition:)
    task_type = create_task_type(workflow:)
    create_task(project:, workflow:, task_type:)
    task = @lifecycle.claim_next!(project:, owner_id: "session")

    accepted = @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
      step: "develop", outcome: "again")
    assert_equal "develop", accepted.current_step
    assert_equal 2, accepted.claim_version

    assert_raises(TaskLifecycle::Conflict) do
      @lifecycle.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
        step: "develop", outcome: "again")
    end
  end

  private

  def claim_task(owner_id:)
    project = create_project
    create_task(project:)
    @lifecycle.claim_next!(project:, owner_id:)
  end
end

class TaskLifecycleConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    TaskDependency.delete_all
    Task.delete_all
    TaskType.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  teardown do
    TaskDependency.delete_all
    Task.delete_all
    TaskType.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  test "two sessions cannot claim the same task" do
    project = create_project
    task = create_task(project:)
    selected = Queue.new
    release = Queue.new
    results = Queue.new

    coordinated_lifecycle = Class.new(TaskLifecycle) do
      define_method(:initialize) do
        super()
        @selected = selected
        @release = release
        @coordinated = false
      end

      private

      define_method(:next_claimable_id) do |eligible|
        task_id = super(eligible)
        return task_id if @coordinated

        @coordinated = true
        @selected << task_id
        @release.pop
        task_id
      end
    end

    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          result = coordinated_lifecycle.new.claim_next!(project:, owner_id: "session-#{index}")
        rescue StandardError => error
          result = error
        ensure
          results << result
        end
      end
    end
    chosen_ids = Timeout.timeout(5) { 2.times.map { selected.pop } }
    assert_equal [ task.id, task.id ], chosen_ids
    2.times { release << true }
    threads.each(&:join)
    outcomes = 2.times.map { results.pop }
    errors = outcomes.grep(StandardError)
    claims = outcomes.compact - errors

    assert_empty errors
    assert_equal [ task.id ], claims.map(&:id)
    assert_equal 1, task.reload.claim_version
    assert_includes %w[session-0 session-1], task.owner_id
  end

  test "the same claim cannot report one transition twice concurrently" do
    project = create_project
    create_task(project:)
    task = TaskLifecycle.new.claim_next!(project:, owner_id: "session")
    gate = Queue.new
    results = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          result = TaskLifecycle.new.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
            step: "develop", outcome: "ready")
        rescue StandardError => error
          result = error
        ensure
          results << result
        end
      end
    end
    2.times { gate << true }
    threads.each(&:join)
    outcomes = 2.times.map { results.pop }

    assert_equal 1, outcomes.grep(Task).size
    assert_equal 1, outcomes.grep(TaskLifecycle::Conflict).size
    assert_equal "check", task.reload.current_step
    assert_equal 2, task.claim_version
  end

  test "cancellation and reporting leave one fenced final state" do
    project = create_project
    create_task(project:)
    task = TaskLifecycle.new.claim_next!(project:, owner_id: "session")
    gate = Queue.new
    results = Queue.new
    operations = {
      report: -> {
        TaskLifecycle.new.report_attempt!(task_id: task.id, owner_id: "session", claim_version: 1,
          step: "develop", outcome: "ready")
      },
      cancel: -> { TaskLifecycle.new.cancel!(task_id: task.id) }
    }

    threads = operations.map do |name, operation|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          result = operation.call
        rescue StandardError => error
          result = error
        ensure
          results << [ name, result ]
        end
      end
    end
    2.times { gate << true }
    threads.each(&:join)
    outcomes = 2.times.to_h { results.pop }

    assert_instance_of Task, outcomes.fetch(:cancel)
    assert_includes [ Task, TaskLifecycle::Conflict ], outcomes.fetch(:report).class
    assert_equal "cancelled", task.reload.status
    assert_nil task.owner_id
    assert_operator task.claim_version, :>=, 2
  end

  test "definition editing serializes with a concurrent claim" do
    project = create_project
    task = create_task(project:)
    edit_locked = Queue.new
    release_edit = Queue.new
    claim_selected = Queue.new
    release_claim = Queue.new
    results = Queue.new

    editing_lifecycle = Class.new(TaskLifecycle) do
      define_method(:initialize) do
        super()
        @edit_locked = edit_locked
        @release_edit = release_edit
      end

      private

      define_method(:lock_editable_task!) do |task_id|
        editable_task = super(task_id)
        @edit_locked << true
        @release_edit.pop
        editable_task
      end
    end
    claiming_lifecycle = Class.new(TaskLifecycle) do
      define_method(:initialize) do
        super()
        @claim_selected = claim_selected
        @release_claim = release_claim
      end

      private

      define_method(:next_claimable_id) do |eligible|
        task_id = super(eligible)
        @claim_selected << true
        @release_claim.pop
        task_id
      end
    end

    editor = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        results << editing_lifecycle.new.update_definition!(task_id: task.id, description_markdown: "Updated")
      rescue StandardError => error
        results << error
      end
    end
    Timeout.timeout(5) { edit_locked.pop }
    claimant = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        results << claiming_lifecycle.new.claim_next!(project:, owner_id: "session")
      rescue StandardError => error
        results << error
      end
    end
    Timeout.timeout(5) { claim_selected.pop }
    release_claim << true
    assert_raises(Timeout::Error) { Timeout.timeout(0.1) { results.pop } }
    release_edit << true
    editor.join
    claimant.join
    outcomes = 2.times.map { results.pop }

    assert_empty outcomes.grep(StandardError)
    assert_equal "Updated", task.reload.description_markdown
    assert_equal "active", task.status
    assert_equal "session", task.owner_id
  end

  test "a definition edit conflicts when a concurrent claim wins" do
    project = create_project
    task = create_task(project:)
    claim_locked = Queue.new
    release_claim = Queue.new
    edit_started = Queue.new
    results = Queue.new

    claiming_lifecycle = Class.new(TaskLifecycle) do
      define_method(:initialize) do
        super()
        @claim_locked = claim_locked
        @release_claim = release_claim
      end

      define_method(:claim_next!) do |**arguments|
        Task.transaction do
          claimed = super(**arguments)
          @claim_locked << true
          @release_claim.pop
          claimed
        end
      end
    end

    claimant = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        results << claiming_lifecycle.new.claim_next!(project:, owner_id: "session")
      rescue StandardError => error
        results << error
      end
    end
    Timeout.timeout(5) { claim_locked.pop }
    editor = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        edit_started << true
        results << TaskLifecycle.new.update_definition!(task_id: task.id, description_markdown: "Too late")
      rescue StandardError => error
        results << error
      end
    end
    Timeout.timeout(5) { edit_started.pop }
    assert_raises(Timeout::Error) { Timeout.timeout(0.1) { results.pop } }
    release_claim << true
    claimant.join
    editor.join
    outcomes = 2.times.map { results.pop }

    assert_equal 1, outcomes.grep(Task).size
    assert_equal 1, outcomes.grep(TaskLifecycle::Conflict).size
    assert_equal "Description", task.reload.description_markdown
    assert_equal "active", task.status
  end
end
