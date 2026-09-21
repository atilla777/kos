require "digest"
require "set"

class BriefTaskGraph
  class InvalidDefinition < StandardError; end

  REQUIRED_CHILD_KEYS = %w[key title description_markdown blocker_keys].freeze

  def validate!(parent:, children:)
    raise TaskLifecycle::Conflict, "brief task already has a materialized child graph" if parent.children.exists?

    normalized = normalize!(parent:, children:)
    { digest: definition_digest(normalized), children: normalized }
  end

  def materialize!(parent_id:, owner_id:, claim_version:, expected_digest:, children:)
    Task.transaction do
      parent = lock_parent!(parent_id)
      normalized = normalize!(parent:, children:)
      actual_digest = definition_digest(normalized)
      raise TaskLifecycle::Conflict, "child graph digest does not match the validated definition" unless
        expected_digest == actual_digest

      validate_claim!(parent, owner_id:, claim_version:)
      raise TaskLifecycle::Conflict, "brief task already has a materialized child graph" if parent.children.exists?

      task_type = TaskType.find_by!(key: "development")
      created = normalized.to_h do |definition|
        task = Task.create!(project: parent.project, task_type:, workflow: task_type.workflow, parent:,
          title: definition.fetch("title"), description_markdown: definition.fetch("description_markdown"),
          current_step: task_type.workflow.first_step_id)
        [ definition.fetch("key"), task ]
      end

      normalized.each do |definition|
        task = created.fetch(definition.fetch("key"))
        ([ parent ] + definition.fetch("blocker_keys").map { |key| created.fetch(key) }).each do |blocker|
          create_dependency!(task:, blocker:)
        end
      end

      { digest: actual_digest, children: created.values }
    end
  end

  def observe(parent:)
    raise InvalidDefinition, "task must be a built-in brief" unless parent.task_type.key == "brief"

    children = parent.children.includes(:task_type, :blockers).order(:id).to_a
    child_ids = children.map(&:id).to_set
    positions = children.each_with_index.to_h { |child, index| [ child.id, index ] }
    canonical = children.map do |child|
      external_blockers = child.blocker_ids.reject { |id| id == parent.id || child_ids.include?(id) }
      canonical_child(
        title: child.title,
        description_markdown: child.description_markdown,
        blocker_positions: child.blocker_ids.filter_map { |id| positions[id] }.sort,
        task_type_key: child.task_type.key,
        parent_blocker: child.blocker_ids.include?(parent.id),
        external_blocker_ids: external_blockers.sort
      )
    end
    {
      parent_id: parent.id,
      digest: children.any? ? digest(canonical) : nil,
      children: children.map do |child|
        {
          task: child,
          sibling_blocker_ids: child.blocker_ids.select { |id| child_ids.include?(id) }.sort
        }
      end
    }
  end

  private

  def lock_parent!(parent_id)
    # A write-first transaction serializes the parent on SQLite, where SELECT FOR UPDATE is ineffective.
    updated = Task.where(id: parent_id).update_all("updated_at = updated_at")
    raise ActiveRecord::RecordNotFound if updated.zero?

    Task.find(parent_id)
  end

  def normalize!(parent:, children:)
    raise InvalidDefinition, "task must be a built-in brief" unless parent.task_type.key == "brief"
    raise InvalidDefinition, "children must be a non-empty array" unless children.is_a?(Array) && children.any?

    normalized = children.map { |child| normalize_child!(child) }
    keys = normalized.map { |child| child.fetch("key") }
    raise InvalidDefinition, "child keys must be unique" unless keys.uniq.size == keys.size

    known_keys = keys.to_set
    normalized.each do |child|
      unknown = child.fetch("blocker_keys").reject { |key| known_keys.include?(key) }
      raise InvalidDefinition, "blocker_keys must reference children in the same graph" if unknown.any?
      raise InvalidDefinition, "a child cannot block itself" if child.fetch("blocker_keys").include?(child.fetch("key"))
    end
    reject_cycles!(normalized)

    normalized.sort_by { |child| child.fetch("key") }
  end

  def create_dependency!(task:, blocker:)
    TaskDependency.create!(task:, blocker:)
  end

  def normalize_child!(child)
    raise InvalidDefinition, "each child must be an object" unless child.is_a?(Hash)
    child = child.stringify_keys
    raise InvalidDefinition, "each child must contain exactly key, title, description_markdown, and blocker_keys" unless
      child.keys.sort == REQUIRED_CHILD_KEYS.sort

    %w[key title description_markdown].each do |name|
      raise InvalidDefinition, "#{name} must be a non-empty string" unless child[name].is_a?(String) && child[name].present?
    end
    blocker_keys = child.fetch("blocker_keys")
    unless blocker_keys.is_a?(Array) && blocker_keys.all? { |key| key.is_a?(String) && key.present? } &&
        blocker_keys.uniq.size == blocker_keys.size
      raise InvalidDefinition, "blocker_keys must be an array of unique non-empty strings"
    end

    child.slice(*REQUIRED_CHILD_KEYS).merge("blocker_keys" => blocker_keys.sort)
  end

  def reject_cycles!(children)
    blockers = children.to_h { |child| [ child.fetch("key"), child.fetch("blocker_keys") ] }
    visiting = Set.new
    visited = Set.new
    visit = lambda do |key|
      raise InvalidDefinition, "child graph cannot contain a dependency cycle" if visiting.include?(key)
      return if visited.include?(key)

      visiting.add(key)
      blockers.fetch(key).each { |blocker| visit.call(blocker) }
      visiting.delete(key)
      visited.add(key)
    end
    blockers.each_key { |key| visit.call(key) }
  end

  def validate_claim!(parent, owner_id:, claim_version:)
    valid = parent.status == "active" && parent.owner_id == owner_id && parent.claim_version == claim_version &&
      parent.current_step == "publish" && parent.lease_expires_at&.future?
    raise TaskLifecycle::Conflict, "brief claim is stale or not at the publication step" unless valid
  end

  def definition_digest(normalized)
    positions = normalized.each_with_index.to_h { |child, index| [ child.fetch("key"), index ] }
    canonical = normalized.map do |child|
      canonical_child(
        title: child.fetch("title"),
        description_markdown: child.fetch("description_markdown"),
        blocker_positions: child.fetch("blocker_keys").map { |key| positions.fetch(key) }.sort,
        task_type_key: "development",
        parent_blocker: true,
        external_blocker_ids: []
      )
    end
    digest(canonical)
  end

  def canonical_child(title:, description_markdown:, blocker_positions:, task_type_key:, parent_blocker:,
    external_blocker_ids:)
    {
      "title" => title,
      "description_markdown" => description_markdown,
      "blocker_positions" => blocker_positions,
      "task_type_key" => task_type_key,
      "parent_blocker" => parent_blocker,
      "external_blocker_ids" => external_blocker_ids
    }
  end

  def digest(canonical)
    "sha256:#{Digest::SHA256.hexdigest(JSON.generate(canonical))}"
  end
end
