module WorkflowSteps
  class CurrentCandidate
    def self.call(task)
      task.task_artifacts.joins(:workflow_attempt)
        .where(artifact_type: "candidate", workflow_attempts: { state: "succeeded" })
        .order("workflow_attempts.fencing_token DESC").first
    end
  end
end
