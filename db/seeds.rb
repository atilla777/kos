require "json"

# These shared definitions are immutable. Change a name for a new edition;
# never silently replace the steps of an existing task's workflow.
Workflow.transaction do
  Dir[Rails.root.join("config/workflows/*.json")].sort.each do |path|
    definition = JSON.parse(File.read(path))
    name = definition.fetch("name")
    steps = definition.fetch("steps")
    existing = Workflow.where(project_id: nil, name: name).to_a

    raise "Multiple global workflows named #{name}" if existing.length > 1

    if existing.empty?
      Workflow.create!(name: name, steps: steps)
    elsif existing.first.steps != steps
      raise "Global workflow #{name} differs from #{path}; create a newly named edition instead"
    end
  end
end
