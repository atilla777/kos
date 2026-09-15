class PublicationResult < ApplicationRecord
  include HasUuidPrimaryKey

  belongs_to :repository
  belongs_to :task
  belongs_to :publication
  belongs_to :producing_attempt, class_name: "WorkflowAttempt"
  belongs_to :approved_review_artifact, class_name: "TaskArtifact"

  validates :input_context_digest, :candidate_sha, :remote, :base_ref, :observed_remote_tip,
    :observation_digest, :observed_at, :approved_review_artifact_id, :passed_test_artifact_ids,
    :recorded_at, :result_manifest, presence: true

  def result_manifest=(value)
    super(value.is_a?(String) ? value : JSON.generate(value))
  end

  def result_manifest
    value = super
    value.present? ? JSON.parse(value) : value
  end

  def passed_test_artifact_ids=(value)
    super(value.is_a?(String) ? value : JSON.generate(value))
  end

  def passed_test_artifact_ids
    value = super
    value.present? ? JSON.parse(value) : value
  end
end
