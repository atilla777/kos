class TaskGroup < ApplicationRecord
  KINDS = %w[epic].freeze

  belongs_to :project
  has_many :tasks, dependent: :restrict_with_error

  validates :kind, inclusion: { in: KINDS }
  validates :title, :description, presence: true

  def progress
    counts = tasks.group(:status).count
    total = counts.values.sum
    done = counts.fetch("done", 0)

    {
      completed: total.positive? && done == total,
      tasks_total: total,
      tasks_done: done,
      tasks_in_progress: counts.fetch("in_progress", 0)
    }
  end
end
