class Task < ApplicationRecord
  class DependencyCycleError < StandardError; end
  class ClaimError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  STATUSES = %w[planned in_progress done].freeze
  LEASE_DURATION = 1.hour

  belongs_to :project
  belongs_to :workflow
  belongs_to :task_group, optional: true
  has_many :task_dependencies, dependent: :destroy
  has_many :blocking_tasks, through: :task_dependencies
  has_many :dependent_task_dependencies,
    class_name: "TaskDependency",
    foreign_key: :blocking_task_id,
    dependent: :restrict_with_error,
    inverse_of: :blocking_task
  has_many :dependent_tasks, through: :dependent_task_dependencies, source: :task
  has_many :task_artifacts, dependent: :destroy
  has_one :brief_plan, foreign_key: :brief_task_id, dependent: :restrict_with_error

  before_validation :initialize_planned_state, on: :create

  validates :kind, :title, :description, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :current_step, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :workflow_belongs_to_project
  validate :current_step_in_workflow
  validate :workflow_immutable, on: :update
  validate :task_group_belongs_to_project
  validate :structural_changes_require_planned_status, on: :update

  scope :ready_at, ->(time) {
    where("tasks.status = 'planned' OR (tasks.status = 'in_progress' AND tasks.lease_expires_at <= ?)", time)
      .where(<<~SQL.squish)
        NOT EXISTS (
          SELECT 1
          FROM task_dependencies dependencies
          INNER JOIN tasks blockers ON blockers.id = dependencies.blocking_task_id
          WHERE dependencies.task_id = tasks.id AND blockers.status != 'done'
        )
      SQL
  }

  def self.current_for(project:, session_id:, time: Time.current)
    project.tasks
      .where(status: "in_progress", session_id: session_id)
      .where("lease_expires_at > ?", time)
      .order(:id)
      .first
  end

  def self.claim_for!(project:, task_id:, session_id:)
    transaction do
      lock_project!(project)
      now = Time.current
      requested_task = project.tasks.find(task_id)
      active_task = current_for(project: project, session_id: session_id, time: now)

      if active_task
        raise ClaimError, "session_has_active_task" unless active_task.id == requested_task.id

        next [ active_task, true ]
      end

      ensure_claimable!(requested_task, now)
      [ assign_claim!(requested_task, session_id, now), false ]
    end
  end

  def self.claim_next_for!(project:, session_id:, kind: nil, task_group_id: nil)
    transaction do
      lock_project!(project)
      now = Time.current
      active_task = current_for(project: project, session_id: session_id, time: now)
      next [ active_task, true ] if active_task

      candidates = project.tasks.ready_at(now)
      candidates = candidates.where(kind: kind) if kind.present?
      candidates = candidates.where(task_group_id: task_group_id) if task_group_id
      candidate = candidates.order(:created_at, :id).first
      next [ nil, false ] unless candidate

      [ assign_claim!(candidate, session_id, now), false ]
    end
  end

  def self.ensure_claimable!(task, time)
    if task.status == "in_progress" && task.lease_expires_at > time
      raise ClaimError, "task_already_claimed"
    end
    raise ClaimError, "invalid_transition" unless task.status == "planned" || task.status == "in_progress"

    has_unfinished_blocker = task.blocking_tasks.where.not(status: "done").exists?
    raise ClaimError, "task_blocked" if has_unfinished_blocker
  end

  def self.assign_claim!(task, session_id, time)
    task.update!(
      status: "in_progress",
      session_id: session_id,
      claim_id: next_claim_id,
      claimed_at: time,
      lease_expires_at: time + LEASE_DURATION
    )
    task
  end

  def self.next_claim_id
    loop do
      claim_id = SecureRandom.hex(32)
      return claim_id unless exists?(claim_id: claim_id)
    end
  end

  def self.lock_project!(project)
    Project.where(id: project.id).update_all("id = id")
  end

  private_class_method :ensure_claimable!, :assign_claim!, :next_claim_id, :lock_project!

  def renew!(claim_id:)
    with_locked_project do
      now = Time.current
      ensure_active_claim!(claim_id, now)
      update!(lease_expires_at: now + LEASE_DURATION)
    end
  end

  def release!(claim_id:, work_summary: nil, work_summary_provided: false)
    finish_claim!(
      status: "planned",
      claim_id: claim_id,
      work_summary: work_summary,
      work_summary_provided: work_summary_provided
    )
  end

  def complete!(claim_id:, work_summary: nil, work_summary_provided: false)
    finish_claim!(
      status: "done",
      claim_id: claim_id,
      work_summary: work_summary,
      work_summary_provided: work_summary_provided
    )
  end

  def advance_step!(claim_id:, expected_step:)
    with_locked_project do
      ensure_active_claim!(claim_id, Time.current)
      raise ClaimError, "step_conflict" unless current_step == expected_step
      raise ClaimError, "invalid_transition" if current_step >= workflow.steps.length - 1

      @advancing_step = true
      begin
        update!(current_step: current_step + 1)
      ensure
        @advancing_step = false
      end
    end
  end

  def update_from_request!(attributes:, claim_id:)
    with_locked_project do
      case status
      when "planned"
        update!(attributes)
      when "in_progress"
        ensure_active_claim!(claim_id, Time.current)
        update!(attributes)
      else
        raise ClaimError, "invalid_transition"
      end
    end
  end

  def reopen!
    with_locked_project do
      raise ClaimError, "invalid_transition" unless status == "done"
      if dependent_tasks.where(status: %w[in_progress done]).exists?
        raise ClaimError, "task_has_started_dependents"
      end

      update!(status: "planned")
    end
  end

  def destroy_safely!
    with_locked_project do
      raise ClaimError, "task_already_claimed" if status == "in_progress" && lease_expires_at > Time.current
      raise ClaimError, "task_has_dependents" if dependent_tasks.exists? || brief_plan
      plan = BriefPlan.where("EXISTS (SELECT 1 FROM json_each(brief_plans.result) WHERE json_extract(value, '$.id') = ?)", id).first
      raise ClaimError, "task_has_dependents" if plan && plan.brief_task.status != "done"

      destroy!
    end
  end

  def put_artifact!(key:, content:, claim_id:, expected_lock_version:, expected_step: nil)
    result = nil
    with_locked_project do
      ensure_active_claim!(claim_id, Time.current)
      raise ClaimError, "step_conflict" if expected_step && current_step != expected_step
      artifact = task_artifacts.find_by(key: key)

      if artifact
        raise TaskArtifact::VersionConflict unless artifact.lock_version == expected_lock_version

        artifact.update!(content: content)
      else
        raise TaskArtifact::VersionConflict unless expected_lock_version.nil?

        artifact = task_artifacts.create!(key: key, content: content)
      end
      result = artifact
    rescue ActiveRecord::RecordNotUnique
      raise TaskArtifact::VersionConflict
    end
    result
  end

  def delete_artifact!(key:, claim_id:, expected_lock_version:)
    deleted_artifact = nil
    with_locked_project do
      ensure_active_claim!(claim_id, Time.current)
      artifact = task_artifacts.find_by(key: key)
      unless artifact && artifact.lock_version == expected_lock_version
        raise TaskArtifact::VersionConflict
      end

      deleted_artifact = artifact
      artifact.destroy!
    end
    deleted_artifact
  end

  def lease_expired?(time = Time.current)
    status == "in_progress" && lease_expires_at <= time
  end

  def availability_at(time = Time.current)
    reasons = []
    reasons << { code: "task_done" } if status == "done"
    reasons << { code: "active_claim" } if status == "in_progress" && lease_expires_at > time

    unfinished_blocker_count = blocking_tasks.where.not(status: "done").count
    if unfinished_blocker_count.positive?
      reasons << { code: "unfinished_blockers", count: unfinished_blocker_count }
    end

    { available: reasons.empty?, reasons: reasons }
  end

  def replace_blockers!(ids)
    transaction do
      Project.where(id: project_id).update_all(updated_at: Time.current)
      lock!
      validate_blocker_ids!(ids)
      raise DependencyCycleError if dependency_cycle?(ids)

      task_dependencies.where.not(blocking_task_id: ids).delete_all
      existing_ids = task_dependencies.where(blocking_task_id: ids).pluck(:blocking_task_id)
      (ids - existing_ids).each do |blocking_task_id|
        task_dependencies.create!(blocking_task_id: blocking_task_id, project_id: project_id)
      end
    end
  end

  private

  def with_locked_project
    transaction do
      self.class.send(:lock_project!, project)
      lock!
      yield
    end
    self
  end

  def ensure_active_claim!(provided_claim_id, time)
    raise ClaimError, "invalid_transition" unless status == "in_progress"
    raise ClaimError, "claim_mismatch" unless provided_claim_id.present? && claim_id == provided_claim_id
    raise ClaimError, "lease_expired" unless lease_expires_at > time
  end

  def finish_claim!(status:, claim_id:, work_summary:, work_summary_provided:)
    with_locked_project do
      ensure_active_claim!(claim_id, Time.current)
      if status == "done" && current_step != workflow.steps.length - 1
        raise ClaimError, "invalid_transition"
      end
      attributes = {
        status: status,
        session_id: nil,
        claim_id: nil,
        claimed_at: nil,
        lease_expires_at: nil
      }
      attributes[:work_summary] = work_summary if work_summary_provided
      update!(attributes)
    end
  end

  def task_group_belongs_to_project
    return unless task_group && task_group.project_id != project_id

    errors.add(:task_group, "must belong to the same project")
  end

  def structural_changes_require_planned_status
    return if status == "planned"

    errors.add(:kind, "can only be changed while the task is planned") if will_save_change_to_kind?
    errors.add(:task_group, "can only be changed while the task is planned") if will_save_change_to_task_group_id?
  end

  def workflow_belongs_to_project
    return unless workflow && workflow.project_id && workflow.project_id != project_id

    errors.add(:workflow, "must belong to the same project")
  end

  def current_step_in_workflow
    return unless workflow && current_step.is_a?(Integer)

    errors.add(:current_step, "must refer to a workflow step") unless current_step.between?(0, workflow.steps.length - 1)
  end

  def workflow_immutable
    errors.add(:workflow, "cannot be changed") if will_save_change_to_workflow_id?
    errors.add(:current_step, "must be advanced explicitly") if will_save_change_to_current_step? && !@advancing_step
  end

  def validate_blocker_ids!(ids)
    if ids.uniq.length != ids.length
      errors.add(:blocked_by_ids, "contains duplicates")
    elsif ids.include?(id)
      errors.add(:blocked_by_ids, "cannot include the task itself")
    elsif project.tasks.where(id: ids).count != ids.length
      errors.add(:blocked_by_ids, "must contain tasks from the same project")
    elsif status != "planned"
      errors.add(:blocked_by_ids, "can only be changed while the task is planned")
    elsif (plan = BriefPlan.where("EXISTS (SELECT 1 FROM json_each(brief_plans.result) WHERE json_extract(value, '$.id') = ?)", id).first) &&
        plan.brief_task.status != "done" && !ids.include?(plan.brief_task_id)
      errors.add(:blocked_by_ids, "must include the unfinished Brief")
    end

    raise ActiveRecord::RecordInvalid, self if errors.any?
  end

  def dependency_cycle?(ids)
    return false if ids.empty?

    sql = self.class.sanitize_sql_array([ <<~SQL.squish, { blocker_ids: ids, task_id: id } ])
      WITH RECURSIVE reachable(id) AS (
        SELECT id FROM tasks WHERE id IN (:blocker_ids)
        UNION
        SELECT dependencies.blocking_task_id
        FROM task_dependencies dependencies
        INNER JOIN reachable ON dependencies.task_id = reachable.id
      )
      SELECT 1 FROM reachable WHERE id = :task_id LIMIT 1
    SQL
    self.class.connection.select_value(sql).present?
  end

  def initialize_planned_state
    self.status = "planned"
    self.session_id = nil
    self.claim_id = nil
    self.claimed_at = nil
    self.lease_expires_at = nil
  end
end
