require "json"

# The checked-in base definitions are complete. Installing them never edits a
# definition assigned to a task or a project's copy.
Workflow.transaction do
  %w[brief execution fix].each do |kind|
    definition = JSON.parse(Rails.root.join("config/workflows/#{kind}-base-v1.json").read)
    name = definition.fetch("name")
    steps = definition.fetch("steps")
    current = Workflow.find_by(project_id: nil, name: name)
    next if current&.steps == steps

    if current&.tasks&.exists? || (current && Workflow.exists?(base_workflow_id: current.id))
      raise "Base workflow #{name} is in use; cannot replace it"
    end

    current&.destroy!
    Workflow.create!(name: name, steps: steps)
  end
end
