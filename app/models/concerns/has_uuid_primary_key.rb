module HasUuidPrimaryKey
  extend ActiveSupport::Concern

  UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  included do
    attribute :id, :string, default: -> { SecureRandom.uuid }
    validates :id, format: { with: UUID_FORMAT }
  end
end
