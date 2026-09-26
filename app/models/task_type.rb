class TaskType < ApplicationRecord
  RESERVED_KEYS = %w[brief development fix].freeze

  belongs_to :workflow

  has_many :tasks

  validates :key, presence: true, uniqueness: true
  validate :key_is_not_reserved, on: :create, unless: :installing_builtin?
  validate :key_is_immutable, on: :update
  validate :reserved_workflow_is_catalog_managed, on: :update, unless: :installing_builtin?

  def self.create_builtin!(attributes)
    new(attributes).tap do |task_type|
      task_type.instance_variable_set(:@installing_builtin, true)
      task_type.save!
    end
  end

  def update_builtin!(attributes)
    @installing_builtin = true
    update!(attributes)
  ensure
    @installing_builtin = false
  end

  private

  def installing_builtin?
    @installing_builtin == true
  end

  def key_is_not_reserved
    errors.add(:key, "is reserved for a built-in task type") if RESERVED_KEYS.include?(key)
  end

  def key_is_immutable
    errors.add(:key, "cannot be changed") if will_save_change_to_key?
  end

  def reserved_workflow_is_catalog_managed
    return unless RESERVED_KEYS.include?(key) && will_save_change_to_workflow_id?

    errors.add(:workflow, "for a built-in task type is managed by the catalog")
  end
end
