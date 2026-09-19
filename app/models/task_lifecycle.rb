class TaskLifecycle
  UNCHANGED = Object.new.freeze

  class Error < StandardError; end
  class Conflict < Error; end
  class InvalidTransition < Error; end

  PAUSED_STATUSES = %w[needs_human blocked].freeze

  def initialize(clock: -> { Time.current }, lease_duration: Rails.application.config.x.kos.lease_duration)
    raise ArgumentError, "lease_duration must be positive" unless lease_duration.positive?

    @clock = clock
    @lease_duration = lease_duration
  end

  def create!(project:, task_type:, title:, description_markdown:, parent: nil, blockers: [])
    Task.transaction do
      task_type = TaskType.find(task_type.id)
      task = Task.create!(project:, task_type:, workflow: task_type.workflow, parent:, title:, description_markdown:,
        current_step: task_type.workflow.first_step_id)
      blockers.each { |blocker| TaskDependency.create!(task:, blocker:) }
      task
    end
  end

  def show!(task_id)
    Task.find(task_id)
  end

  def update_definition!(task_id:, description_markdown: UNCHANGED, parent: UNCHANGED, blockers: UNCHANGED)
    Task.transaction do
      task = lock_editable_task!(task_id)

      task.description_markdown = description_markdown unless description_markdown.equal?(UNCHANGED)
      task.parent = parent unless parent.equal?(UNCHANGED)
      task.save! if task.changed?

      unless blockers.equal?(UNCHANGED)
        task.task_dependencies.each(&:destroy!)
        blockers.each { |blocker| TaskDependency.create!(task:, blocker:) }
      end

      task
    end
  end

  def claim_next!(project:, owner_id:)
    validate_owner!(owner_id)

    loop do
      now = @clock.call
      eligible = eligible_tasks(project)
      task_id = next_claimable_id(eligible)
      return if task_id.nil?

      claimed = Task.transaction do
        updated = eligible.where(id: task_id).update_all(
          status: "active",
          owner_id:,
          claim_version: Arel.sql("claim_version + 1"),
          lease_expires_at: now + @lease_duration,
          updated_at: now
        )
        Task.find(task_id) if updated == 1
      end
      return claimed if claimed
    end
  end

  def resume!(task_id:, owner_id:, takeover_confirmed: false)
    validate_owner!(owner_id)
    now = @clock.call
    resumable = Task.where(id: task_id, status: PAUSED_STATUSES)
    active = Task.where(id: task_id, status: "active")
    active = active.where("lease_expires_at <= ?", now) unless takeover_confirmed == true

    Task.transaction do
      updated = resumable.or(active).update_all(
        status: "active",
        owner_id:,
        claim_version: Arel.sql("claim_version + 1"),
        lease_expires_at: now + @lease_duration,
        updated_at: now
      )
      raise Conflict, "task cannot be resumed from its current state" unless updated == 1

      Task.find(task_id)
    end
  end

  def report_attempt!(task_id:, owner_id:, claim_version:, step:, outcome:)
    task = Task.includes(:workflow).find(task_id)
    action = task.workflow.action_for(step, outcome)
    raise InvalidTransition, "outcome is not allowed for the reported step" unless action

    now = @clock.call
    changes = transition_changes(action, task, now)
    current_claim = Task.where(id: task_id, status: "active", owner_id:, claim_version:, current_step: step)
      .where("lease_expires_at > ?", now)
    Task.transaction do
      updated = current_claim.update_all(changes)
      raise Conflict, "task claim is stale or does not match the current step" unless updated == 1

      Task.find(task_id)
    end
  end

  def cancel!(task_id:)
    now = @clock.call
    task = Task.where(id: task_id).where.not(status: %w[completed cancelled])
    Task.transaction do
      updated = task.update_all(
        status: "cancelled",
        owner_id: nil,
        lease_expires_at: nil,
        claim_version: Arel.sql("claim_version + CASE WHEN status = 'active' THEN 1 ELSE 0 END"),
        updated_at: now
      )
      raise Conflict, "task cannot be cancelled from its current state" unless updated == 1

      Task.find(task_id)
    end
  end

  private

  def lock_editable_task!(task_id)
    editable = Task.where(id: task_id, status: "pending", claim_version: 0)
    return Task.find(task_id) if editable.update_all("id = id") == 1

    Task.find(task_id)
    raise Conflict, "task definition can change only while the task is pending and unclaimed"
  end

  def eligible_tasks(project)
    incomplete = TaskDependency.where(blocker_id: Task.where.not(status: "completed")).select(:task_id)
    Task.where(project:, status: "pending").where.not(id: incomplete).order(:created_at, :id)
  end

  def next_claimable_id(eligible)
    eligible.pick(:id)
  end

  def transition_changes(action, task, now)
    changes = { claim_version: Arel.sql("claim_version + 1"), updated_at: now }
    if action.key?("next_step")
      changes[:current_step] = action["next_step"]
    elsif action["pause"]
      changes.merge!(status: action["pause"], owner_id: nil, lease_expires_at: nil)
    elsif action["complete_task"]
      changes.merge!(status: "completed", owner_id: nil, lease_expires_at: nil)
    else
      raise InvalidTransition, "workflow outcome has no supported action"
    end
    changes
  end

  def validate_owner!(owner_id)
    raise ArgumentError, "owner_id must be present" if owner_id.blank?
  end
end
