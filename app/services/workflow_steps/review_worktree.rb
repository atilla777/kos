module WorkflowSteps
  module ReviewWorktree
    module_function

    def current_clean?(reservation, attempt, candidate_sha, input_context_digest: nil)
      return false unless reservation&.state == "confirmed" && reservation.workflow_attempt_id == attempt.id &&
        reservation.fencing_token == attempt.fencing_token && reservation.head_sha == candidate_sha &&
        reservation.observed_state == "clean" && reservation.git_common_dir_digest.present?

      expected = Kos::WorktreeObservation.digest(repository_id: reservation.repository_id,
        reservation_id: reservation.id, fencing_token: attempt.fencing_token, path: reservation.path,
        branch: reservation.branch, state: "clean", head_sha: candidate_sha,
        git_common_dir_digest: reservation.git_common_dir_digest, input_context_digest:)
      reservation.observation_digest == expected
    end
  end
end
