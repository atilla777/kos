module Api
  module V2
    class Serializer
      class << self
        def publication_preflight(record)
          optional({
            "schema_version" => "2",
            "id" => record.id,
            "repository_id" => record.repository_id,
            "task_id" => record.task_id,
            "prepared_attempt_id" => record.prepared_attempt_id,
            "current_owner_attempt_id" => record.current_owner_attempt_id,
            "candidate_sha" => record.candidate_sha,
            "remote" => record.remote,
            "base_ref" => record.base_ref,
            "state" => record.state,
            "observed_remote_oid" => record.observed_remote_oid,
            "observation_digest" => record.observation_digest,
            "observed_at" => optional_timestamp(record.observed_at),
            "error" => record.error,
            "publication_id" => record.publication_id,
            "prepared_at" => timestamp(record.prepared_at),
            "reconciled_at" => optional_timestamp(record.reconciled_at),
            "consumed_at" => optional_timestamp(record.consumed_at),
            "updated_at" => timestamp(record.updated_at)
          })
        end

        def publication(record)
          Api::V1::Serializer.publication(record).merge("schema_version" => "2")
        end

        def base_moved_recovery(result)
          {
            "schema_version" => "2",
            "task_id" => result.task.id,
            "task_number" => result.task.number,
            "publication_id" => result.publication.id,
            "attempt_id" => result.attempt.id,
            "candidate_sha" => result.publication.candidate_sha,
            "from_status" => result.transition.from_state.identifier,
            "to_status" => result.transition.to_state.identifier,
            "recovered_at" => timestamp(result.recovered_at)
          }
        end

        def rebase_reconciliation(result)
          {
            "schema_version" => "2",
            "effect_id" => result.effect.id,
            "reservation_id" => result.reservation.id,
            "head_sha" => result.reservation.head_sha,
            "effect_state" => result.effect.state,
            "worktree_state" => result.reservation.observed_state,
            "reconciled_at" => timestamp(result.effect.reconciled_at)
          }
        end

        private

        def optional(value)
          value.compact
        end

        def optional_timestamp(value)
          timestamp(value) if value
        end

        def timestamp(value)
          value.utc.iso8601
        end
      end
    end
  end
end
