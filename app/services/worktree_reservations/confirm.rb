module WorktreeReservations
  class Confirm < Base
    def self.call(repository:, reservation_id:, git_common_dir_digest:, head_sha:, attempt_id:, fencing_token:,
      expected_lock_version:, now: Time.current)
      WorktreeReservation.transaction do
        reservation, task = reservation_and_locked_task!(repository, reservation_id)
        check_lock!(task, expected_lock_version)
        owning_attempt!(repository, reservation, task, attempt_id, fencing_token, now)
        unless git_common_dir_digest == common_dir_digest(repository)
          raise OperationError.new("invalid_transition", "Git common directory does not match the repository")
        end
        if reservation.state == "confirmed"
          return reservation if reservation.git_common_dir_digest == git_common_dir_digest &&
            reservation.head_sha == head_sha

          raise OperationError.new("invalid_transition", "Worktree reservation was confirmed differently")
        end
        unless reservation.state == "reserved"
          raise OperationError.new("invalid_transition", "Worktree reservation cannot be confirmed")
        end

        reservation.update!(state: "confirmed", git_common_dir_digest:, head_sha:, confirmed_at: now)
        reservation
      end
    end
  end
end
