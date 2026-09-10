class WorktreeReservation < ApplicationRecord
  include HasUuidPrimaryKey

  STATES = %w[reserved confirmed release_pending released].freeze
  OBSERVED_STATES = %w[absent clean dirty mismatched].freeze

  belongs_to :repository
  belongs_to :task
  belongs_to :workflow_attempt

  validates :branch, :path, presence: true
  validates :state, inclusion: { in: STATES }
  validates :observed_state, inclusion: { in: OBSERVED_STATES }, allow_nil: true
  validates :fencing_token, numericality: { only_integer: true, greater_than: 0 }
end
