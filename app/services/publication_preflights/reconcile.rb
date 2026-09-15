require Rails.root.join("lib/kos/publication_preflight_evidence")

module PublicationPreflights
  class Reconcile < Base
    def self.call(repository:, preflight_id:, attempt_id:, fencing_token:, expected_lock_version:,
      observed_remote_oid: nil, observed_at: nil, evidence_digest: nil, unknown: nil, now: Time.current)
      PublicationPreflight.transaction do
        preflight, task = preflight_and_locked_task!(repository, preflight_id)
        check_lock!(task, expected_lock_version)
        attempt = owning_attempt!(repository, preflight, task, attempt_id, fencing_token, now)
        unless preflight.state.in?(PublicationPreflight::UNRESOLVED_STATES)
          raise OperationError.new("invalid_transition", "Publication preflight is already resolved")
        end

        if unknown
          preflight.update!(state: "unknown", error: JSON.parse(JSON.generate(unknown)), reconciled_at: now)
        else
          reconcile_concrete!(preflight, task, attempt, observed_remote_oid, observed_at, evidence_digest, now)
        end
        preflight
      end
    end

    def self.reconcile_concrete!(preflight, task, attempt, observed_remote_oid, observed_at, evidence_digest, now)
      observed_at_text = observed_at
      observed_at = Time.iso8601(observed_at) if observed_at.is_a?(String)
      if !observed_at || observed_at < preflight.prepared_at || observed_at > now + MAX_OBSERVATION_CLOCK_SKEW
        raise OperationError.new("invalid_transition", "Publication preflight observation timestamp is invalid")
      end
      repository_evidence = { "id" => preflight.repository_id, "git_common_dir" => preflight.repository.git_common_dir,
        "trusted_remote" => preflight.repository.trusted_remote,
        "trusted_remote_url" => preflight.repository.trusted_remote_url, "base_ref" => preflight.repository.base_ref }
      preflight_evidence = { "id" => preflight.id, "repository_id" => preflight.repository_id,
        "task_id" => task.id, "candidate_sha" => preflight.candidate_sha,
        "current_owner_attempt_id" => attempt.id, "fencing_token" => attempt.fencing_token,
        "remote" => preflight.remote, "base_ref" => preflight.base_ref, "state" => preflight.state }
      expected = Kos::PublicationPreflightEvidence.digest(repository: repository_evidence,
        publication_preflight: preflight_evidence, observed_remote_oid:, observed_at: observed_at_text)
      valid = observed_remote_oid && evidence_digest == expected
      unless valid
        raise OperationError.new("invalid_transition", "Publication preflight evidence is invalid")
      end

      preflight.update!(state: "reconciled", observed_remote_oid:, observation_digest: evidence_digest,
        observed_at:, observation_owner_attempt: attempt, error: nil, reconciled_at: now)
    rescue ArgumentError
      raise OperationError.new("invalid_transition", "Publication preflight observation timestamp is invalid")
    end
    private_class_method :reconcile_concrete!
  end
end
