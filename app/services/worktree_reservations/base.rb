require "digest"
require "pathname"

module WorktreeReservations
  class Base < WorkflowAttempts::Base
    class << self
      private

      def reservation_and_locked_task!(repository, reservation_id)
        reservation = repository.worktree_reservations.find_by(id: reservation_id)
        raise OperationError.new("reservation_not_found", "Worktree reservation not found") unless reservation

        task = repository.tasks.lock.find(reservation.task_id)
        [ repository.worktree_reservations.lock.find(reservation.id), task ]
      end

      def owning_attempt!(repository, reservation, task, attempt_id, fencing_token, now)
        attempt = repository.workflow_attempts.lock.find_by(id: attempt_id)
        raise OperationError.new("attempt_not_found", "Attempt not found") unless attempt

        check_lease!(attempt, task, fencing_token, now)
        unless reservation.workflow_attempt_id == attempt.id && reservation.fencing_token == fencing_token
          raise OperationError.new("fencing_token_stale", "Worktree reservation ownership is stale")
        end
        attempt
      end

      def validate_path!(path)
        valid = path.is_a?(String) && path.bytesize.between?(2, 4096) && !path.include?("\0") &&
          Pathname.new(path).absolute? && Pathname.new(path).cleanpath.to_s == path
        return if valid

        raise OperationError.new("malformed_input", "Worktree path is not canonical")
      end

      def common_dir_digest(repository)
        "sha256:#{Digest::SHA256.hexdigest(repository.git_common_dir.encode(Encoding::UTF_8))}"
      end

      def validate_observation!(observed_state, head_sha)
        valid = observed_state == "clean" ? head_sha.present? : observed_state != "absent" || head_sha.nil?
        return if valid

        raise OperationError.new("malformed_input", "Worktree observation is malformed")
      end

      def record_observation!(reservation, observed_state, head_sha, evidence_digest, now, release:)
        validate_observation!(observed_state, head_sha)
        return replay_released!(reservation, observed_state, evidence_digest) if reservation.state == "released"

        attributes = { observed_state:, observation_digest: evidence_digest }
        case observed_state
        when "absent"
          release_if_materialized!(reservation, attributes, now)
        when "clean"
          record_clean!(reservation, attributes, head_sha, now, release:)
        else
          reservation.update!(attributes)
        end
        reservation
      end

      def replay_released!(reservation, observed_state, evidence_digest)
        if observed_state == "absent" && reservation.observation_digest == evidence_digest
          return reservation
        end

        raise OperationError.new("invalid_transition", "Worktree reservation is already released")
      end

      def release_if_materialized!(reservation, attributes, now)
        if reservation.state == "reserved"
          reservation.update!(attributes)
          return
        end

        reservation.task.update!(worktree_reservation: nil)
        reservation.update!(attributes.merge(state: "released", released_at: now))
      end

      def record_clean!(reservation, attributes, head_sha, now, release:)
        if reservation.state == "reserved"
          reservation.update!(attributes.merge(state: "confirmed", head_sha:,
            git_common_dir_digest: common_dir_digest(reservation.repository), confirmed_at: now))
        elsif release || reservation.state == "release_pending"
          unless reservation.head_sha == head_sha
            raise OperationError.new("invalid_transition", "Worktree HEAD does not match its reservation")
          end
          reservation.update!(attributes.merge(state: release ? "release_pending" : reservation.state))
        else
          reservation.update!(attributes.merge(head_sha:))
        end
      end
    end
  end
end
