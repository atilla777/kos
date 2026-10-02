require "json"

# Only unused shared definitions can be replaced. Never change a task's workflow.
Workflow.transaction do
  definitions = Dir[Rails.root.join("config/workflows/*-v3.json")].sort.map do |path|
    definition = JSON.parse(File.read(path))
    steps = definition.fetch("steps")
    case definition.fetch("name")
    when "KOS Brief v3"
      steps[1]["instructions"] = steps[1].fetch("instructions").sub("Execution v3 tasks", "Execution v7 tasks")
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
      implementation["instructions"] += " When a review flags an untrusted input, check the applicable defect class, not only the reported literal: consider type, encoding, empty values, control characters and a subsequent valid request. Do not build an exhaustive input matrix. On overwriting test_report, keep a concise self-contained summary of earlier verified checks and their file state, then identify changed files, the new file state, affected reruns and why full CI was or was not repeated. A lock_version identifies the current artifact edition, not a readable history of overwritten text."
      implementation["templates"]["test_report"] += "\n\n## Current evidence after corrections\n<Concise self-contained summary of earlier checks, outcomes and verified Git base and uncommitted contents; changed files and current base/contents; affected reruns and results; reason full CI was required or earlier evidence still covers unchanged work. Do not rely on a prior lock_version to recover overwritten text. For an input defect, note applicable neighboring forms and a subsequent valid request.>"
      review["instructions"] += " After high or medium findings, require an independent new review of the corrected complete diff. On overwriting review_report, retain a concise self-contained summary of prior findings and verified evidence, the reviewed base and uncommitted contents before and after corrections, changed files, affected reruns and their results, remaining findings and the new independent verdict. A lock_version alone does not preserve previous report text."
      review["templates"]["review_report"] += "\n\n## Current independent verdict after corrections\n<Concise self-contained summary of earlier findings and evidence; reviewed Git base and uncommitted contents before and after changes, changed files, affected reruns and outcomes; open findings by severity and new independent review of the complete corrected diff. Do not cite a prior lock_version as if its text remained available.>"
    end
    if definition.fetch("name") != "KOS Brief v3"
      implementation = steps[definition.fetch("name") == "KOS Fix v3" ? 2 : 1]
      implementation["instructions"] += " During a sequence of small edits use focused checks; run the project's required complete checks once on the settled change before independent review. After later edits repeat affected checks, and full CI only if project rules require it or previous evidence no longer covers the result. Account for mandatory commit hooks without presenting skipped hooks as passed."
      implementation["templates"]["test_report"] = "# Implementation and checks\n\n## Checked state\n<Git base and one identifier for uncommitted contents including untracked files, changed files, current outcome.>\n\n## Checks and corrections\n<Actual commands and results with criterion coverage; brief earlier outcomes and findings, affected reruns, reason full CI was required or earlier evidence still covers unchanged work. For input defects note applicable neighboring forms and a subsequent valid request.>"
      review = steps[definition.fetch("name") == "KOS Fix v3" ? 3 : 2]
      review["instructions"] += " Keep the current report concise: previous findings and their resolution, current checked state, open findings and independent verdict; avoid copying previous check inventories or repeating state identifiers in every section."
      review["templates"]["review_report"] = "# Independent review\n\n## Checked state and verdict\n<Reviewed Git base and uncommitted contents, test_report lock_version, complete diff and independent current verdict.>\n\n## Findings and corrections\n<Earlier findings and evidence in brief, changed files and affected reruns, open findings by severity, new independent review after corrections; do not copy complete earlier inventories.>"
      documentation = steps[-2]
      publication = steps[-1]
      publication["name"] = "Check documentation, publish and verify"
      publication["instructions"] = "First perform the documentation check and save documentation_report under the active claim; then inspect its result, final diff and earlier independent review before publishing. " + documentation.fetch("instructions") + " " + publication.fetch("instructions") + " If documentation edits affect reviewed behavior, stop before publication and ask the orchestrator for affected checks and an independent review; resume this same step afterward. Verify git status after saving each report; remove only your own temporary report file and preserve all other files."
      publication["inputs"] = (documentation.fetch("inputs") + publication.fetch("inputs")).uniq.reject { |input| input["key"] == "documentation_report" }
      publication["outputs"] = documentation.fetch("outputs") + publication.fetch("outputs")
      publication["templates"] = documentation.fetch("templates").merge(publication.fetch("templates"))
      steps.delete_at(-2)
    end
    [ definition.fetch("name").sub(" v3", " v7"), steps ]
  end

  # Retain older shared editions while tasks use them; remove only unused ones.
  obsolete_names = %w[Brief Execution Fix].flat_map { |kind| %w[v1 v2 v3 v4 v5 v6].map { |edition| "KOS #{kind} #{edition}" } }
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
