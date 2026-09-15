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
        check_no_unresolved_effects!(attempt)
        transition = transition!(task, attempt, to_status)
        validate_contract!(task, attempt, transition, artifacts)
        validate_synchronized_worktree!(task, attempt, artifacts)
        validate_base_synchronization!(task, attempt, artifacts)
        validate_review_worktree!(task, attempt, artifacts)

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

    def self.validate_synchronized_worktree!(task, attempt, artifacts)
      return unless attempt.input_context&.key?("worktree")

      expected_head = case task.workflow_state.identifier
      when "implementation-planning"
        artifacts.find { _1.fetch("type") == "document" }&.dig("metadata", "commit_sha")
      when "development"
        artifacts.find { _1.fetch("type") == "candidate" }&.dig("metadata", "candidate_sha")
      when "base-synchronization"
        artifacts.find { _1.fetch("type") == "candidate" }&.dig("metadata", "candidate_sha")
      end
      return unless expected_head

      reservation = task.worktree_reservation
      context = attempt.input_context.fetch("worktree")
      operation = task.workflow_state.identifier == "base-synchronization" ? "rebase" : "commit"
      effects = attempt.owned_repository_effects.to_a.select { _1.request.dig("effect", "operation") == operation }
      effect = effects.one? ? effects.first : nil
      valid = reservation&.id == context.fetch("reservation_id") && reservation.state == "confirmed" &&
        reservation.head_sha == expected_head &&
        ReviewWorktree.current_clean?(reservation, attempt, expected_head,
          input_context_digest: task.workflow_state.identifier == "base-synchronization" ?
            attempt.input_context_digest : nil)
      valid &&= effect&.state == "succeeded" && effect.prepared_attempt_id == attempt.id &&
        effect.request["input_context_digest"] == attempt.input_context_digest &&
        effect.request.dig("effect", "reservation_id") == reservation.id &&
        effect.result.dig("result", operation == "rebase" ? "head_sha" : "commit_sha") == expected_head
      invalid!("Worktree HEAD is not synchronized with transition evidence") unless valid
    end
    private_class_method :validate_synchronized_worktree!

    def self.validate_base_synchronization!(task, attempt, artifacts)
      return unless task.workflow_state.identifier == "base-synchronization"

      effects = attempt.owned_repository_effects.to_a
      fetches = effects.select { _1.request.dig("effect", "operation") == "fetch" }
      rebases = effects.select { _1.request.dig("effect", "operation") == "rebase" }
      fetch = fetches.one? ? fetches.first : nil
      rebase = rebases.one? ? rebases.first : nil
      candidate_sha = artifacts.find { _1.fetch("type") == "candidate" }&.dig("metadata", "candidate_sha")
      context = attempt.input_context
      fetch_result = fetch&.result&.fetch("result", nil)
      rebase_result = rebase&.result&.fetch("result", nil)
      valid = effects.size == 2 && fetch&.state == "succeeded" && rebase&.state == "succeeded" &&
        fetch.prepared_attempt_id == attempt.id && rebase.prepared_attempt_id == attempt.id &&
        fetch.request["input_context_digest"] == attempt.input_context_digest &&
        rebase.request["input_context_digest"] == attempt.input_context_digest &&
        fetch.request.dig("effect", "remote") == task.repository.trusted_remote &&
        fetch.request.dig("effect", "ref") == task.repository.base_ref &&
        fetch_result&.fetch("remote", nil) == task.repository.trusted_remote &&
        fetch_result&.fetch("ref", nil) == task.repository.base_ref &&
        rebase.request.dig("effect", "onto_sha") == fetch_result&.fetch("observed_oid", nil) &&
        rebase.request.dig("effect", "expected_head_sha") == context&.dig("worktree", "head_sha") &&
        rebase.request.dig("effect", "reservation_id") == context&.dig("worktree", "reservation_id") &&
        rebase_result&.fetch("head_sha", nil) == candidate_sha && candidate_sha.present? &&
        candidate_sha != context&.fetch("candidate_sha", nil) && fetch.prepared_at <= rebase.prepared_at
      invalid!("Base synchronization does not match its trusted fetch and rebase") unless valid
    end
    private_class_method :validate_base_synchronization!

    def self.validate_review_worktree!(task, attempt, artifacts)
      return unless task.workflow_state.identifier == "review"

      review = artifacts.find { _1.fetch("type") == "review" }
      candidate_sha = review&.dig("metadata", "candidate_sha")
      context = attempt.input_context
      reservation = task.worktree_reservation
      valid = context&.fetch("review_observation_nonce", nil).present? &&
        context&.fetch("candidate_sha", nil) == candidate_sha &&
        context&.dig("worktree", "reservation_id") == reservation&.id &&
        context&.dig("worktree", "head_sha") == candidate_sha &&
        attempt.owned_repository_effects.none? &&
        ReviewWorktree.current_clean?(reservation, attempt, candidate_sha,
          input_context_digest: attempt.input_context_digest)
      invalid!("Review does not match the freshly observed clean candidate") unless valid
    end
    private_class_method :validate_review_worktree!

    def self.invalid!(message)
      raise OperationError.new("invalid_artifact", message)
    end
    private_class_method :invalid!
  end
end
