module RepositoryEffects
  class ReconcileRebase < Base
    Result = Data.define(:effect, :reservation)

    def self.call(repository:, effect_id:, head_sha:, rebase_evidence_digest:, worktree_evidence_digest:,
      attempt_id:, fencing_token:, expected_lock_version:, now: Time.current)
      RepositoryEffect.transaction do
        effect, task = effect_and_locked_task!(repository, effect_id)
        check_lock!(task, expected_lock_version)
        attempt = owning_attempt!(repository, effect, task, attempt_id, fencing_token, now)
        reservation = task.worktree_reservation&.lock!
        validate_reconciliation!(task, attempt, effect, reservation, head_sha,
          rebase_evidence_digest, worktree_evidence_digest)

        result = { "schema_version" => "1", "effect_intent_id" => effect.id,
          "request_attempt_id" => effect.prepared_attempt_id, "owner_attempt_id" => attempt.id,
          "input_context_digest" => effect.request.fetch("input_context_digest"),
          "effect_request_digest" => effect.request_digest,
          "result" => { "outcome" => "succeeded", "operation" => "rebase", "head_sha" => head_sha,
            "evidence_digest" => rebase_evidence_digest } }
        effect.update!(state: "succeeded", result:, reconciled_at: now)
        reservation.update!(head_sha:, observed_state: "clean", observation_digest: worktree_evidence_digest)
        Result.new(effect, reservation)
      end
    end

    def self.validate_reconciliation!(task, attempt, effect, reservation, head_sha,
      rebase_evidence_digest, worktree_evidence_digest)
      request = effect.request
      context = attempt.input_context
      fetches = attempt.owned_repository_effects.select { _1.request.dig("effect", "operation") == "fetch" }
      fetch = fetches.one? ? fetches.first : nil
      publication = task.publications.where(state: "superseded", candidate_sha: context&.fetch("candidate_sha", nil))
        .order(reconciled_at: :desc).first
      predecessor_rebase = completed_predecessor_rebase(task, attempt, reservation)
      retry_after_reconciled_rebase = predecessor_rebase.present? && head_sha == reservation&.head_sha
      expected_worktree_digest = if reservation
        Kos::WorktreeObservation.digest(repository_id: reservation.repository_id,
          reservation_id: reservation.id, fencing_token: attempt.fencing_token, path: reservation.path,
          branch: reservation.branch, state: "clean", head_sha:,
          git_common_dir_digest: reservation.git_common_dir_digest,
          input_context_digest: attempt.input_context_digest)
      end
      expected_rebase_digest = if fetch && reservation
        Kos::RebaseEvidence.digest(repository: repository_snapshot(task.repository),
          reservation: reservation_snapshot(reservation), effect: effect_snapshot(effect, attempt),
          fetch: fetch_snapshot(fetch, attempt),
          original_base_sha: predecessor_rebase&.request&.dig("effect", "onto_sha") ||
            publication&.expected_remote_oid,
          expected_head_sha: reservation.head_sha, onto_sha: request.dig("effect", "onto_sha"), head_sha:)
      end
      valid = task.workflow_state.identifier == "base-synchronization" && effect.state == "prepared" &&
        request.dig("effect", "operation") == "rebase" && request["input_context_digest"] ==
          attempt.input_context_digest && reservation&.state == "confirmed" &&
        reservation.workflow_attempt_id == attempt.id && reservation.fencing_token == attempt.fencing_token &&
        reservation.id == context&.dig("worktree", "reservation_id") &&
        reservation.head_sha == context&.dig("worktree", "head_sha") &&
        request.dig("effect", "reservation_id") == reservation.id &&
        request.dig("effect", "expected_head_sha") == reservation.head_sha &&
        fetch&.state == "succeeded" && request.dig("effect", "onto_sha") == fetch.result&.dig("result", "observed_oid") &&
        publication.present? && (head_sha != reservation.head_sha || retry_after_reconciled_rebase) &&
        rebase_evidence_digest == expected_rebase_digest && worktree_evidence_digest == expected_worktree_digest
      return if valid

      raise OperationError.new("invalid_transition", "Rebase reconciliation does not match the frozen worktree")
    end
    private_class_method :validate_reconciliation!

    def self.completed_predecessor_rebase(task, attempt, reservation)
      task.workflow_attempts.where(state: "interrupted").where("fencing_token < ?", attempt.fencing_token)
        .order(fencing_token: :desc).each do |previous|
        effects = task.repository_effects.where(current_owner_attempt: previous).to_a
        fetch = effects.find { _1.request.dig("effect", "operation") == "fetch" }
        rebase = effects.find { _1.request.dig("effect", "operation") == "rebase" }
        valid = effects.size == 2 && fetch&.state == "succeeded" && rebase&.state == "succeeded" &&
          rebase.result&.dig("result", "head_sha") == reservation&.head_sha
        return rebase if valid
      end
      nil
    end
    private_class_method :completed_predecessor_rebase

    def self.repository_snapshot(repository)
      { "id" => repository.id, "git_common_dir" => repository.git_common_dir,
        "trusted_remote" => repository.trusted_remote, "trusted_remote_url" => repository.trusted_remote_url,
        "base_ref" => repository.base_ref }
    end
    private_class_method :repository_snapshot

    def self.reservation_snapshot(reservation)
      reservation.attributes.slice("id", "repository_id", "state", "path", "branch", "fencing_token")
    end
    private_class_method :reservation_snapshot

    def self.effect_snapshot(effect, attempt)
      { "id" => effect.id, "repository_id" => effect.repository_id,
        "current_owner_attempt_id" => attempt.id, "fencing_token" => attempt.fencing_token,
        "request_digest" => effect.request_digest, "request" => effect.request }
    end
    private_class_method :effect_snapshot

    def self.fetch_snapshot(fetch, attempt)
      result = fetch.result.fetch("result")
      adapter_result = { "schema_version" => "1", "operation" => "fetch", "outcome" => "succeeded",
        "repository_id" => fetch.repository_id, "effect_id" => fetch.id,
        "current_owner_attempt_id" => attempt.id, "fencing_token" => attempt.fencing_token,
        "effect_request_digest" => fetch.request_digest }.merge(
          result.slice("remote", "ref", "observed_oid", "evidence_digest"))
      { "request" => { "schema_version" => "1", "operation" => "fetch",
        "repository" => repository_snapshot(fetch.repository), "effect" => effect_snapshot(fetch, attempt) },
        "result" => adapter_result }
    end
    private_class_method :fetch_snapshot
  end
end
