require "digest"

module WorkflowSteps
  class CaptureContext < WorkflowAttempts::Base
    class InvariantError < StandardError; end

    def self.call(repository:, attempt_id:, fencing_token:, expected_lock_version:, now: Time.current)
      Task.transaction do
        attempt, task = attempt_and_locked_task!(repository, attempt_id)
        check_lock!(task, expected_lock_version)
        check_lease!(attempt, task, fencing_token, now)
        check_task_state!(task, attempt)
        return validated_frozen_context!(repository, task, attempt) if attempt.input_context

        context = build_context(repository, task, attempt)
        digest = context_digest(context)
        context["input_context_digest"] = digest
        validate_context!(context)
        attempt.update!(input_context: context, input_context_digest: digest)
        attempt.input_context
      end
    end

    def self.check_task_state!(task, attempt)
      valid = attempt.workflow_state_id == task.workflow_state_id &&
        task.workflow_state.workflow_version_id == task.workflow_version_id && !task.workflow_state.terminal?
      unavailable!("Attempt context is unavailable for the current workflow state") unless valid
    end
    private_class_method :check_task_state!

    def self.build_context(repository, task, attempt)
      definition = verified_definition!(task.workflow_version)
      status = definition.fetch("statuses").find { _1.fetch("id") == task.workflow_state.identifier }
      raise InvariantError, "Current workflow status is absent from its pinned definition" unless status

      context = {
        "schema_version" => "1",
        "task_id" => task.id,
        "task_number" => task.number,
        "attempt_id" => attempt.id,
        "repository_id" => repository.id,
        "workflow_version_id" => task.workflow_version_id,
        "workflow_status" => task.workflow_state.identifier,
        "instruction" => status.fetch("instruction"),
        "artifact_templates" => status.fetch("artifact_templates"),
        "expected_lock_version" => task.lock_version,
        "fencing_token" => attempt.fencing_token,
        "base_ref" => repository.base_ref,
        "required_artifacts" => status.fetch("required_artifacts"),
        "allowed_repository_effects" => status.fetch("allowed_repository_effects"),
        "retrospective_enabled" => RuntimeConfig.current.retrospective_enabled
      }
      add_worktree!(context, task, status)
      candidate = CurrentCandidate.call(task)
      context["candidate_sha"] = candidate.metadata.fetch("candidate_sha") if candidate
      add_publication!(context, task, attempt) if task.workflow_state.identifier == "publication"
      JSON.parse(JSON.generate(context))
    end
    private_class_method :build_context

    def self.verified_definition!(workflow_version)
      definition = WorkflowCatalog::CanonicalDefinition.from_record(workflow_version)
      errors = WorkflowCatalog::DefinitionValidator.new(definition, task_type: workflow_version.task_type).errors
      valid = errors.empty? && WorkflowCatalog::CanonicalDefinition.digest(definition) == workflow_version.content_digest
      raise InvariantError, "Pinned workflow definition failed integrity validation" unless valid

      definition
    end
    private_class_method :verified_definition!

    def self.add_worktree!(context, task, status)
      return unless status.fetch("worktree") == "required"

      reservation = task.worktree_reservation
      expected_branch = "kos/task-#{task.number}"
      valid = reservation&.state == "confirmed" && reservation.task_id == task.id &&
        reservation.repository_id == task.repository_id && reservation.branch == expected_branch &&
        reservation.path.present? && reservation.head_sha.present?
      unavailable!("Required worktree is not confirmed") unless valid

      context["worktree"] = {
        "reservation_id" => reservation.id,
        "path" => reservation.path,
        "branch" => reservation.branch,
        "head_sha" => reservation.head_sha
      }
    end
    private_class_method :add_worktree!

    def self.add_publication!(context, task, attempt)
      publication = task.active_publication
      valid = publication&.state.in?(Publication::UNRESOLVED_STATES) &&
        publication.current_owner_attempt_id == attempt.id && publication.task_id == task.id &&
        publication.repository_id == task.repository_id && context["candidate_sha"] == publication.candidate_sha &&
        task.worktree_reservation&.head_sha == publication.candidate_sha
      unavailable!("Publication context requires an owned publication") unless valid

      context["publication"] = {
        "publication_id" => publication.id,
        "candidate_sha" => publication.candidate_sha,
        "remote" => publication.remote,
        "base_ref" => publication.base_ref,
        "expected_remote_oid" => publication.expected_remote_oid
      }
    end
    private_class_method :add_publication!

    def self.validated_frozen_context!(repository, task, attempt)
      context = attempt.input_context
      digest = attempt.input_context_digest
      bindings = {
        "task_id" => task.id,
        "task_number" => task.number,
        "attempt_id" => attempt.id,
        "repository_id" => repository.id,
        "workflow_version_id" => task.workflow_version_id,
        "workflow_status" => task.workflow_state.identifier,
        "expected_lock_version" => task.lock_version,
        "fencing_token" => attempt.fencing_token,
        "base_ref" => repository.base_ref
      }
      valid = context.is_a?(Hash) && digest.present? && context["input_context_digest"] == digest &&
        bindings.all? { |key, value| context[key] == value } && context_digest(context) == digest
      raise InvariantError, "Frozen workflow context failed integrity validation" unless valid

      validate_context!(context)
      context
    end
    private_class_method :validated_frozen_context!

    def self.context_digest(context)
      value = context.except("input_context_digest")
      "sha256:#{Digest::SHA256.hexdigest(WorkflowCatalog::CanonicalDefinition.canonical_json(value))}"
    end
    private_class_method :context_digest

    def self.validate_context!(context)
      return if Kos::Cli::SchemaRegistry.new.valid?("workflow.json", "context", context)

      raise InvariantError, "Workflow context failed schema validation"
    end
    private_class_method :validate_context!

    def self.unavailable!(message)
      raise OperationError.new("context_unavailable", message)
    end
    private_class_method :unavailable!
  end
end
