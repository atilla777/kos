require Rails.root.join("lib/kos/push_evidence")

module PublicationResults
  class Record < Publications::Base
    def self.call(repository:, publication_id:, result_manifest:, attempt_id:, fencing_token:,
      expected_lock_version:, now: Time.current)
      PublicationResult.transaction do
        publication, task = publication_and_locked_task!(repository, publication_id)
        check_lock!(task, expected_lock_version)
        attempt = owning_attempt!(repository, publication, task, attempt_id, fencing_token, now)
        existing = publication.publication_result
        return replay!(existing, result_manifest) if existing

        validate_publication!(repository, publication, task, attempt)
        validate_context!(repository, publication, task, attempt, result_manifest, now)
        artifact = validate_manifest!(publication, attempt, result_manifest)
        review, tests = validate_candidate_evidence!(task, publication)
        validate_push_evidence!(repository, publication, attempt, artifact.fetch("metadata"))

        publication.create_publication_result!(repository:, task:, producing_attempt: attempt,
          input_context_digest: attempt.input_context_digest, candidate_sha: publication.candidate_sha,
          remote: publication.remote, base_ref: publication.base_ref,
          observed_remote_tip: publication.observed_remote_tip,
          observation_digest: publication.observation_digest, observed_at: artifact.dig("metadata", "observed_at"),
          approved_review_artifact: review, passed_test_artifact_ids: tests.map(&:id).sort,
          result_manifest: JSON.parse(JSON.generate(result_manifest)), recorded_at: now)
      end
    rescue ActiveRecord::RecordNotUnique
      replay!(repository.publication_results.find_by!(publication_id:), result_manifest)
    end

    def self.replay!(result, manifest)
      return result if result.result_manifest == manifest

      raise OperationError.new("invalid_transition", "Publication already has a different result")
    end
    private_class_method :replay!

    def self.validate_publication!(repository, publication, task, attempt)
      valid = publication.state == "reconciled" && publication.candidate_reachable == true &&
        task.active_publication_id == publication.id && publication.observation_owner_attempt_id == attempt.id &&
        publication.repository_id == repository.id && publication.remote == repository.trusted_remote &&
        publication.base_ref == repository.base_ref
      raise OperationError.new("invalid_transition", "Publication is not a current reachable result") unless valid
    end
    private_class_method :validate_publication!

    def self.validate_context!(repository, publication, task, attempt, manifest, now)
      check_context!(attempt, manifest)
      context = WorkflowSteps::CaptureContext.call(repository:, attempt_id: attempt.id,
        fencing_token: attempt.fencing_token, expected_lock_version: task.lock_version, now:)
      valid = context["workflow_status"] == "publication" && context["candidate_sha"] == publication.candidate_sha &&
        context.dig("publication", "publication_id") == publication.id &&
        context.dig("worktree", "head_sha") == publication.candidate_sha
      raise OperationError.new("context_unavailable", "Publication context does not match its result") unless valid
    end
    private_class_method :validate_context!

    def self.validate_manifest!(publication, attempt, manifest)
      valid = manifest.is_a?(Hash) && manifest["schema_version"] == "1" && manifest["outcome"] == "succeeded" &&
        manifest["attempt_id"] == attempt.id && manifest["input_context_digest"] == attempt.input_context_digest &&
        manifest["artifacts"].is_a?(Array) && manifest["artifacts"].one? &&
        Kos::Cli::SchemaRegistry.new.valid?("workflow.json", "result_manifest", manifest)
      invalid!("Publication result manifest is invalid") unless valid

      artifact = manifest.fetch("artifacts").first
      metadata = artifact.is_a?(Hash) ? artifact["metadata"] : nil
      expected = { "kind" => "publication", "publication_id" => publication.id,
        "candidate_sha" => publication.candidate_sha, "remote" => publication.remote,
        "base_ref" => publication.base_ref, "observed_remote_tip" => publication.observed_remote_tip,
        "reachable" => true, "observed_at" => metadata&.fetch("observed_at", nil) }
      valid = artifact&.keys&.sort == %w[metadata producer schema_version state type] &&
        artifact["schema_version"] == "1" && artifact["type"] == "publication" &&
        artifact["state"] == "published" && artifact["producer"].to_s.match?(ApplicationRecord::IDENTIFIER_FORMAT) &&
        metadata&.keys&.sort == expected.keys.sort && metadata == expected &&
        Time.iso8601(metadata.fetch("observed_at")) == publication.observed_at
      invalid!("Publication artifact does not exactly match the observed publication") unless valid
      artifact
    rescue ArgumentError, KeyError
      invalid!("Publication artifact does not exactly match the observed publication")
    end
    private_class_method :validate_manifest!

    def self.validate_candidate_evidence!(task, publication)
      candidate = WorkflowSteps::CurrentCandidate.call(task)
      tests = task.task_artifacts.joins(:workflow_attempt).where(artifact_type: "test", state: "passed",
        workflow_attempts: { state: "succeeded" }).to_a
      tests.select! { _1.metadata["candidate_sha"] == publication.candidate_sha && _1.metadata["exit_code"] == 0 }
      review = task.task_artifacts.joins(workflow_attempt: :completed_transition)
        .where(artifact_type: "review", state: "approved", workflow_attempts: { state: "succeeded" },
          workflow_transitions: { to_state_id: task.workflow_state_id }).order(created_at: :desc).first
      review_metadata = review&.metadata
      valid_review = review_metadata&.fetch("candidate_sha", nil) == publication.candidate_sha &&
        review_metadata&.fetch("review_attempt_id", nil) == review&.workflow_attempt_id &&
        review&.workflow_attempt_id != candidate&.workflow_attempt_id
      valid = candidate&.metadata&.fetch("candidate_sha", nil) == publication.candidate_sha &&
        tests.any? && valid_review
      raise OperationError.new("invalid_transition", "Publication candidate lacks passed tests") unless valid

      [ review, tests ]
    end
    private_class_method :validate_candidate_evidence!

    def self.validate_push_evidence!(repository, publication, attempt, metadata)
      repository_snapshot = { "id" => repository.id, "git_common_dir" => repository.git_common_dir,
        "trusted_remote" => repository.trusted_remote, "trusted_remote_url" => repository.trusted_remote_url,
        "base_ref" => repository.base_ref }
      publication_snapshot = { "id" => publication.id, "repository_id" => repository.id,
        "current_owner_attempt_id" => attempt.id, "fencing_token" => attempt.fencing_token,
        "input_context_digest" => attempt.input_context_digest, "candidate_sha" => publication.candidate_sha,
        "remote" => publication.remote, "base_ref" => publication.base_ref,
        "expected_remote_oid" => publication.expected_remote_oid }
      expected = Kos::PushEvidence.digest(repository: repository_snapshot, publication: publication_snapshot,
        candidate_sha: publication.candidate_sha, remote: publication.remote, base_ref: publication.base_ref,
        observed_remote_tip: publication.observed_remote_tip, candidate_reachable: true,
        observed_at: metadata.fetch("observed_at"))
      invalid!("Publication push evidence is invalid") unless publication.observation_digest == expected
    end
    private_class_method :validate_push_evidence!

    def self.invalid!(message)
      raise OperationError.new("invalid_artifact", message)
    end
    private_class_method :invalid!
  end
end
