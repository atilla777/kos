class BuiltInCatalog
  COMMON_OUTCOMES = {
    "needs_human" => { "pause" => "needs_human" },
    "blocked" => { "pause" => "blocked" }
  }.freeze

  CATALOG = {
    "brief" => {
      name: "Brief",
      workflow_name: "Built-in brief",
      steps: [
        [ "brief", "Brief", "advanced", "Specify the requested product behavior and propose its development task graph.",
          "# Brief\n\n## Specification\n\n## Proposed task graph", { "specified" => { "next_step" => "review" } } ],
        [ "review", "Review", "advanced", "Independently review the product specification and proposed task graph without changing the worktree.",
          "# Review\n\n## Findings\n\n## Decision", { "approved" => { "next_step" => "publish" },
            "changes_requested" => { "next_step" => "brief" } } ],
        [ "publish", "Publish", "standard", "Publish the reviewed specification, observe the remote result, and materialize the validated child graph.",
          "# Publication\n\n## Git state\n\n## Child graph", { "published" => { "complete_task" => true },
            "review_invalid" => { "next_step" => "review" }, "base_moved" => { "next_step" => "brief" },
            "graph_invalid" => { "next_step" => "brief" } } ]
      ]
    },
    "development" => {
      name: "Development",
      workflow_name: "Built-in development",
      steps: [
        [ "plan", "Plan", "advanced", "Plan the smallest implementation that satisfies the task and its acceptance criteria.",
          "# Plan\n\n## Scope\n\n## Implementation\n\n## Verification", { "planned" => { "next_step" => "implement" } } ],
        [ "implement", "Implement", "standard", "Implement the plan and run every project-required check, fixing ordinary failures before returning.",
          "# Implementation\n\n## Changes\n\n## Checks", { "implemented" => { "next_step" => "document" },
            "plan_invalid" => { "next_step" => "plan" } } ],
        [ "document", "Document", "standard", "Update affected product specifications through OKF, or record why observable behavior did not change.",
          "# Documentation\n\n## Product behavior", { "documented" => { "next_step" => "review" },
            "implementation_invalid" => { "next_step" => "implement" } } ],
        [ "review", "Review", "advanced", "Independently review the complete uncommitted change without modifying the worktree.",
          "# Review\n\n## Findings\n\n## Decision", { "approved" => { "next_step" => "publish" },
            "changes_requested" => { "next_step" => "implement" }, "redesign_required" => { "next_step" => "plan" } } ],
        [ "publish", "Publish", "standard", "Verify the reviewed change, safely update its base, create one task commit, push, and observe the remote result.",
          "# Publication\n\n## Git state\n\n## Remote observation", { "published" => { "complete_task" => true },
            "review_invalid" => { "next_step" => "review" }, "base_moved" => { "next_step" => "implement" } } ]
      ]
    },
    "fix" => {
      name: "Fix",
      workflow_name: "Built-in fix",
      steps: [
        [ "diagnose", "Diagnose", "advanced", "Reproduce the reported problem, record evidence, and identify its root cause before planning.",
          "# Diagnosis\n\n## Reproduction\n\n## Evidence\n\n## Root cause", { "diagnosed" => { "next_step" => "plan" } } ],
        [ "plan", "Plan", "advanced", "Plan the smallest fix and a regression check that fails for the reproduced defect.",
          "# Plan\n\n## Fix\n\n## Regression check", { "planned" => { "next_step" => "implement" },
            "diagnosis_invalid" => { "next_step" => "diagnose" } } ],
        [ "implement", "Implement", "standard", "Implement the fix and regression check, then run every project-required check and correct ordinary failures.",
          "# Implementation\n\n## Changes\n\n## Checks", { "implemented" => { "next_step" => "document" },
            "plan_invalid" => { "next_step" => "plan" } } ],
        [ "document", "Document", "standard", "Update affected product specifications through OKF, or record why observable behavior did not change.",
          "# Documentation\n\n## Product behavior", { "documented" => { "next_step" => "review" },
            "implementation_invalid" => { "next_step" => "implement" } } ],
        [ "review", "Review", "advanced", "Independently review the diagnosis and complete uncommitted fix without modifying the worktree.",
          "# Review\n\n## Findings\n\n## Decision", { "approved" => { "next_step" => "publish" },
            "changes_requested" => { "next_step" => "implement" }, "redesign_required" => { "next_step" => "plan" } } ],
        [ "publish", "Publish", "standard", "Verify the reviewed fix, safely update its base, create one task commit, push, and observe the remote result.",
          "# Publication\n\n## Git state\n\n## Remote observation", { "published" => { "complete_task" => true },
            "review_invalid" => { "next_step" => "review" }, "base_moved" => { "next_step" => "implement" } } ]
      ]
    }
  }.freeze

  def self.install!
    TaskType.transaction do
      existing = TaskType.where(key: CATALOG.keys).index_by(&:key)
      unless existing.empty? || existing.keys.sort == CATALOG.keys.sort
        record = existing.values.first
        record.errors.add(:key, "built-in task type catalog is only partially installed")
        raise ActiveRecord::RecordInvalid, record
      end

      CATALOG.each do |key, entry|
        definition = definition_for(entry.fetch(:steps))
        task_type = existing[key]
        next if task_type&.workflow&.definition_json == definition

        workflow = Workflow.create!(name: entry.fetch(:workflow_name), definition_json: definition)
        if task_type
          task_type.update!(name: entry.fetch(:name), workflow:)
        else
          TaskType.create_builtin!(key:, name: entry.fetch(:name), workflow:)
        end
      end
    end
  end

  def self.definitions
    CATALOG.transform_values { |entry| definition_for(entry.fetch(:steps)) }
  end

  def self.definition_for(steps)
    { "steps" => steps.map do |id, name, model_tier, instruction, artifact_template, outcomes|
      {
        "id" => id,
        "name" => name,
        "model_tier" => model_tier,
        "instruction" => instruction,
        "artifact_template" => artifact_template,
        "outcomes" => outcomes.merge(COMMON_OUTCOMES)
      }
    end }
  end
  private_class_method :definition_for
end
