class RuntimeConfig < ApplicationRecord
  validates :retrospective_enabled, inclusion: { in: [ true, false ] }

  def self.current
    create_or_find_by!(id: 1)
  end
end
