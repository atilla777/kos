require "json"

# Only unused shared definitions can be replaced. Never change a task's workflow.
Workflow.transaction do
  definitions = Dir[Rails.root.join("config/workflows/*.json")].sort.map do |path|
    definition = JSON.parse(File.read(path))
    [ definition.fetch("name"), definition.fetch("steps") ]
  end

  obsolete = Workflow.where(project_id: nil, name: %w[KOS\ Brief\ v2 KOS\ Execution\ v2 KOS\ Fix\ v2]).to_a
  replacements = definitions.filter_map do |name, steps|
    existing = Workflow.where(project_id: nil, name: name).to_a
    raise "Multiple global workflows named #{name}" if existing.length > 1

    existing.first if existing.first && existing.first.steps != steps
  end

  (obsolete + replacements).each do |workflow|
    raise "Global workflow #{workflow.name} is in use; cannot replace or remove it" if workflow.tasks.exists?
  end

  (obsolete + replacements).each(&:destroy!)
  definitions.each do |name, steps|
    Workflow.create!(name: name, steps: steps) unless Workflow.exists?(project_id: nil, name: name)
  end
end
