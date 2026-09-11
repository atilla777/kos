module WorkflowSteps
  class Complete < WorkflowAttempts::Base
    Result = Data.define(:task, :artifacts)

    def self.call(repository:, task_number:, to_status:, attempt_id:, fencing_token:,
      expected_lock_version:, manifest:, verified_evidence: nil, now: Time.current)
      unless manifest["outcome"] == "succeeded"
        raise OperationError.new("invalid_transition", "Successful step completion requires a succeeded manifest")
      end

      artifacts = manifest.fetch("artifacts")
      if artifacts.any? { _1["type"] == "publication" }
        raise OperationError.new("invalid_transition", "Publication artifacts require specialized completion")
      end
      verification = verified_evidence || RepositoryEvidence::VerifyArtifacts.call(
        repository:, task_number:, artifacts:)
      unless RepositoryEvidence::VerifyArtifacts.matches?(verification, repository:, task_number:, artifacts:)
        raise OperationError.new("invalid_artifact", "Artifact evidence verification does not match the manifest")
      end

      Task.transaction do
        attempt, task = attempt_and_locked_task!(repository, attempt_id)
        raise OperationError.new("task_not_found", "Task not found") unless task.number == task_number

        check_lock!(task, expected_lock_version)
        check_lease!(attempt, task, fencing_token, now)
        check_context!(attempt, manifest)
        transition = transition!(task, attempt, to_status)
        validate_contract!(task, attempt, transition, artifacts)

        records = register_artifacts!(task, attempt, repository, artifacts)
        task.update!(active_attempt: nil, workflow_state: transition.to_state)
        attempt.update!(state: "succeeded", heartbeat_at: now, lease_expires_at: nil,
          completed_at: now, result_manifest: manifest, completed_transition: transition)
        Result.new(task, records)
      end
    end

    def self.register_artifacts!(task, attempt, repository, artifacts)
      artifacts.map do |artifact|
        task.task_artifacts.create!(repository:, workflow_attempt: attempt,
          artifact_type: artifact.fetch("type"), state: artifact.fetch("state"),
          producer: artifact.fetch("producer"), metadata: artifact.fetch("metadata"))
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => error
      raise if error.is_a?(ActiveRecord::StatementInvalid) && error.cause.is_a?(SQLite3::BusyException)

      raise OperationError.new("invalid_artifact", "Artifact could not be registered")
    end
    private_class_method :register_artifacts!

    def self.transition!(task, attempt, to_status)
      unless attempt.workflow_state_id == task.workflow_state_id
        raise OperationError.new("invalid_transition", "Attempt does not own the current workflow state")
      end

      transition = WorkflowTransition.includes(:to_state, :workflow_transition_conditions)
        .find_by(workflow_version_id: task.workflow_version_id, from_state_id: task.workflow_state_id,
          to_state: { identifier: to_status })
      if !transition || task.workflow_state.identifier == "publication"
        raise OperationError.new("invalid_transition", "Workflow transition is not allowed")
      end

      transition
    end
    private_class_method :transition!

    def self.validate_contract!(task, attempt, transition, artifacts)
      requirements = task.workflow_state.artifact_requirements.includes(:artifact_requirement_states)
        .index_by(&:artifact_type)
      invalid!("Manifest contains an undeclared artifact") unless artifacts.all? {
        requirements.key?(_1.fetch("type"))
      }

      conditions = transition.workflow_transition_conditions.index_by(&:artifact_type)
      if requirements.empty?
        invalid!("Manifest contains an undeclared artifact") unless artifacts.empty?
        return
      end

      requirements.each_value do |requirement|
        condition = conditions[requirement.artifact_type]
        invalid!("Transition does not account for a required artifact") unless condition
        validate_requirement!(requirement, condition, artifacts)
      end
      validate_candidate_generation!(task, attempt, requirements, artifacts)
    end
    private_class_method :validate_contract!

    def self.validate_requirement!(requirement, condition, artifacts)
      matching = artifacts.select { _1.fetch("type") == requirement.artifact_type }
      allowed_states = requirement.artifact_requirement_states.map(&:state)
      invalid!("Artifact state is not allowed") unless matching.all? { allowed_states.include?(_1.fetch("state")) }

      if condition.condition_type == "not-applicable"
        invalid!("A waived artifact was supplied") unless matching.empty?
        return
      end

      invalid!("Artifact cardinality is not satisfied") unless cardinality_satisfied?(requirement, matching)
      expected = condition.condition_type == "artifact-state" ? [ condition.artifact_state ] : allowed_states
      evidenced = matching.select { expected.include?(_1.fetch("state")) }
      invalid!("Artifact transition state is not satisfied") unless cardinality_satisfied?(requirement, evidenced)
    end
    private_class_method :validate_requirement!

    def self.cardinality_satisfied?(requirement, artifacts)
      requirement.cardinality == "one" ? artifacts.one? : artifacts.any?
    end
    private_class_method :cardinality_satisfied?

    def self.validate_candidate_generation!(task, attempt, requirements, artifacts)
      supplied_candidate = artifacts.find { _1.fetch("type") == "candidate" }
      current = CurrentCandidate.call(task)
      candidate_sha = supplied_candidate&.dig("metadata", "candidate_sha") || current&.metadata&.fetch("candidate_sha")

      requirements.each_value do |requirement|
        next unless requirement.subject == "candidate"

        relevant = artifacts.select { _1.fetch("type") == requirement.artifact_type }
        invalid!("Candidate artifact does not match the current generation") unless candidate_sha && relevant.all? {
          _1.dig("metadata", "candidate_sha") == candidate_sha
        }
      end

      reviews = artifacts.select { _1.fetch("type") == "review" }
      reviews.each do |review|
        metadata = review.fetch("metadata")
        valid = metadata.fetch("review_attempt_id") == attempt.id && current &&
          current.workflow_attempt_id != attempt.id
        invalid!("Review attempt is not independent from its candidate") unless valid
      end
    end
    private_class_method :validate_candidate_generation!

    def self.invalid!(message)
      raise OperationError.new("invalid_artifact", message)
    end
    private_class_method :invalid!
  end
end
