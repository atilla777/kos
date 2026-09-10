class IdempotencyRecord < ApplicationRecord
  include HasUuidPrimaryKey

  KEY_FORMAT = /\A[A-Za-z0-9._:-]{8,255}\z/
  COMMAND_FORMAT = /\A[a-z][a-z0-9_.-]{0,127}\z/
  STATES = %w[in_progress completed].freeze

  belongs_to :repository, optional: true

  validates :command, :idempotency_key, :request_fingerprint, presence: true
  validates :command, format: { with: COMMAND_FORMAT }
  validates :idempotency_key, format: { with: KEY_FORMAT }
  validates :state, inclusion: { in: STATES }

  def response_data=(value)
    super(value.is_a?(String) ? value : JSON.generate(value))
  end

  def response_data
    value = super
    value.present? ? JSON.parse(value) : value
  end
end
