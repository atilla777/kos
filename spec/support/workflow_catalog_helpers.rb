module WorkflowCatalogHelpers
  def workflow_definition(version: "1.0.0")
    path = Rails.root.join("spec/fixtures/workflow_definitions/v1/valid/quick-fix.json")
    JSON.parse(File.read(path)).merge("version" => version)
  end

  def quick_fix_task_type
    TaskType.find_or_create_by!(id: "quick-fix") do |record|
      record.name = "quick-fix"
      record.workflow_id = "quick-fix"
    end
  end

  def import_workflow(definition = workflow_definition, expected_lock_version: 0)
    quick_fix_task_type
    WorkflowCatalog::ImportDraft.call(workflow_id: "quick-fix", definition: definition,
      expected_lock_version: expected_lock_version)
  end

  def publish_workflow(definition = workflow_definition)
    draft = import_workflow(definition)
    WorkflowCatalog::PublishDraft.call(workflow_id: "quick-fix", expected_lock_version: draft.lock_version)
  end

  def deep_copy(value)
    JSON.parse(JSON.generate(value))
  end
end
