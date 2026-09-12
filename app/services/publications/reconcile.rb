module Publications
  class Reconcile < Base
    MAX_OBSERVATION_CLOCK_SKEW = 5.minutes

    def self.call(repository:, publication_id:, candidate_sha:, observed_remote_tip:, candidate_reachable:,
      observed_at:, evidence_digest:, attempt_id:, fencing_token:, expected_lock_version:, now: Time.current)
      committed_error = nil
      publication = Publication.transaction do
        publication, task = publication_and_locked_task!(repository, publication_id)
        check_lock!(task, expected_lock_version)
        attempt = owning_attempt!(repository, publication, task, attempt_id, fencing_token, now)
        unless publication.state.in?(Publication::UNRESOLVED_STATES) &&
            task.active_publication_id == publication.id
          raise OperationError.new("invalid_transition", "Publication is already terminal")
        end
        unless candidate_sha == publication.candidate_sha
          raise OperationError.new("invalid_transition", "Publication observation does not match its intent")
        end
        observed_at = Time.iso8601(observed_at) if observed_at.is_a?(String)
        if observed_at < publication.prepared_at || observed_at > now + MAX_OBSERVATION_CLOCK_SKEW
          raise OperationError.new("invalid_transition", "Publication observation timestamp is invalid")
        end
        if publication.observed_at && observed_at <= publication.observed_at
          raise OperationError.new("invalid_transition", "Publication observation is not newer")
        end

        moved = !candidate_reachable && observed_remote_tip != publication.expected_remote_oid
        task.update!(active_publication: nil) if moved
        publication.update!(state: moved ? "superseded" : "reconciled", observed_remote_tip:,
          candidate_reachable:, observed_at:, observation_digest: evidence_digest,
          observation_owner_attempt: attempt, reconciled_at: now)
        if moved
          committed_error = CommittedOperationError.new("base_moved", "Publication base ref moved",
            details: { "resource_id" => publication.id })
        end
        publication
      end
      raise committed_error if committed_error

      publication
    end
  end
end
