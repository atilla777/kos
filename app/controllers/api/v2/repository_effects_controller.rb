module Api
  module V2
    class RepositoryEffectsController < BaseController
      def reconcile_rebase
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["effect_id"] == params[:id]

        execute_mutation(body, status: :ok, serialize: Serializer.method(:rebase_reconciliation)) do
          preconditions = body.fetch("preconditions")
          RepositoryEffects::ReconcileRebase.call(repository:, effect_id: body.fetch("effect_id"),
            head_sha: body.fetch("head_sha"), rebase_evidence_digest: body.fetch("rebase_evidence_digest"),
            worktree_evidence_digest: body.fetch("worktree_evidence_digest"),
            attempt_id: preconditions.fetch("attempt_id"), fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"))
        end
      end
    end
  end
end
