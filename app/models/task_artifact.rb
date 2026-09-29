class TaskArtifact < ApplicationRecord
  class VersionConflict < StandardError; end

  belongs_to :task

  validates :key, presence: true, uniqueness: { scope: :task_id }
end
