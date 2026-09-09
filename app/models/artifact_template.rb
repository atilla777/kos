class ArtifactTemplate < ApplicationRecord
  include HasUuidPrimaryKey

  belongs_to :workflow_state

  validates :identifier, :content, presence: true
  validates :identifier, uniqueness: { scope: :workflow_state_id }
  validates :identifier, format: { with: IDENTIFIER_FORMAT }
  validates :media_type, inclusion: { in: [ "text/markdown; charset=utf-8" ] }
end
