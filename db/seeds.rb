require "json"

# Only unused shared definitions can be replaced. Never change a task's workflow.
Workflow.transaction do
  definitions = Dir[Rails.root.join("config/workflows/*-v3.json")].sort.map do |path|
    definition = JSON.parse(File.read(path))
    steps = definition.fetch("steps")
    case definition.fetch("name")
    when "KOS Brief v3"
      steps[1]["instructions"] = steps[1].fetch("instructions").sub("Execution v3 tasks", "Execution v5 tasks")
    when "KOS Execution v3", "KOS Fix v3"
      planning = steps[definition.fetch("name") == "KOS Fix v3" ? 1 : 0]
      planning["instructions"] += " Send product questions to the orchestrator, who obtains separate explicit human agreement and relays the decision back. You may save a technical plan with an open product question, its owner and resolution point, but saving it does not approve or resolve the question: do not update the norm or implement behavior depending on that answer until the human agrees. Then update the affected concept before implementation."
      implementation = steps[definition.fetch("name") == "KOS Fix v3" ? 2 : 1]
      implementation["instructions"] += " After a correction rerun affected checks; rerun full CI if project rules require it or the earlier result no longer covers the change."
    end
    if definition.fetch("name") != "KOS Brief v3"
      implementation = steps[definition.fetch("name") == "KOS Fix v3" ? 2 : 1]
      implementation["instructions"] += " In test_report identify the checked Git base revision and uncommitted change set (including untracked files), the full CI result if run, and the checks actually performed. After each correction distinguish new edits and their affected reruns from earlier evidence; do not claim the previous CI covers changed files without checking."
      implementation["templates"]["test_report"] += "\n\n## Verified state and reuse\n<Git base revision, identifiable uncommitted changes including untracked files, full CI result or reason not run; after corrections name changed files, affected reruns and what prior evidence still covers.>"
      review = steps[definition.fetch("name") == "KOS Fix v3" ? 3 : 2]
      review["instructions"] += " Record the reviewed Git base and uncommitted change set including untracked files, cite the test_report lock_version and its verified state. Review the complete current diff independently; rerun affected checks when necessary, not unchanged full CI merely for review. After corrections independently re-review the resulting diff and record new evidence."
      review["templates"]["review_report"] += "\n\n## Verified state\n<Base revision, uncommitted change set reviewed, test_report lock_version and checked state; changes since previous verdict, independent re-review and any additional checks.>"
      publication = steps.last
      publication["instructions"] += " Compare final base revision and uncommitted change set including untracked files to those in test_report and review_report; cite their lock_versions. If files changed, rerun affected checks and renew independent review when reviewed behavior changed. Repeat full CI only when project rules require it or previous evidence no longer covers the final change. Report what was rerun and why, without copying the full test list."
      publication["templates"]["publication_report"] += "\n\n## Evidence at publication\n<Final base revision and uncommitted change set, test_report and review_report lock_versions, changes since review, affected reruns or why no rerun was needed; verified destination.>"
    end
    [ definition.fetch("name").sub(" v3", " v5"), steps ]
  end

  # Retain older shared editions while tasks use them; remove only unused ones.
  obsolete_names = %w[Brief Execution Fix].flat_map { |kind| %w[v1 v2 v3 v4].map { |edition| "KOS #{kind} #{edition}" } }
  obsolete = Workflow.where(project_id: nil, name: obsolete_names).reject { |workflow| workflow.tasks.exists? }
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
