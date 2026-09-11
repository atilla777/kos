module WorktreeReservations
  class Reconcile < Base
    def self.call(repository:, reservation_id:, observed_state:, head_sha:, evidence_digest:, attempt_id:,
      fencing_token:, expected_lock_version:, now: Time.current)
      WorktreeReservation.transaction do
        reservation, task = reservation_and_locked_task!(repository, reservation_id)
        check_lock!(task, expected_lock_version)
        owning_attempt!(repository, reservation, task, attempt_id, fencing_token, now)
        record_observation!(reservation, observed_state, head_sha, evidence_digest, now, release: false)
      end
    end
  end
end
