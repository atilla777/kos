module PublicationPreflightHelpers
  def advance_to_publication(task:, version:, candidate_sha:, now:)
    development = version.workflow_states.find_by!(identifier: "development")
    review = version.workflow_states.find_by!(identifier: "review")
    publication = version.workflow_states.find_by!(identifier: "publication")
    task.update!(workflow_state: development)
    candidate_attempt = complete_attempt(task:, state: development, target: review, token: 1, now:)
    TaskArtifact.create!(repository: task.repository, task:, workflow_attempt: candidate_attempt,
      artifact_type: "candidate", state: "produced", producer: "workflow-step",
      metadata: { "kind" => "candidate", "candidate_sha" => candidate_sha, "task_trailer" => task.number })
    review_attempt = complete_attempt(task:, state: review, target: publication, token: 2, now:)
    TaskArtifact.create!(repository: task.repository, task:, workflow_attempt: review_attempt,
      artifact_type: "review", state: "approved", producer: "workflow-step",
      metadata: { "kind" => "review", "candidate_sha" => candidate_sha, "verdict" => "approved",
        "review_attempt_id" => review_attempt.id })
  end

  def complete_attempt(task:, state:, target:, token:, now:)
    transition = task.workflow_version.workflow_transitions.find_by!(from_state: state, to_state: target)
    digest = "sha256:#{'c' * 64}"
    attempt = WorkflowAttempt.create!(repository: task.repository, task:, workflow_state: state,
      owner_id: "history-owner", idempotency_key: "history-#{token}", fencing_token: token,
      started_at: now, heartbeat_at: now, lease_expires_at: now + 5.minutes,
      input_context: { "schema_version" => "1" }, input_context_digest: digest)
    task.update!(active_attempt: attempt)
    task.update!(active_attempt: nil, workflow_state: target)
    attempt.update!(state: "succeeded", lease_expires_at: nil, completed_at: now,
      result_manifest: { "schema_version" => "1", "attempt_id" => attempt.id,
        "input_context_digest" => digest, "outcome" => "succeeded", "artifacts" => [] },
      completed_transition: transition)
    attempt
  end

  def publication_preflight_evidence(repository:, preflight:, attempt:, observed_remote_oid:, observed_at:)
    repository_document = { "id" => repository.id, "git_common_dir" => repository.git_common_dir,
      "trusted_remote" => repository.trusted_remote, "trusted_remote_url" => repository.trusted_remote_url,
      "base_ref" => repository.base_ref }
    preflight_document = { "id" => preflight.id, "repository_id" => repository.id,
      "task_id" => preflight.task_id, "candidate_sha" => preflight.candidate_sha,
      "current_owner_attempt_id" => attempt.id, "fencing_token" => attempt.fencing_token,
      "remote" => preflight.remote, "base_ref" => preflight.base_ref, "state" => preflight.state }
    Kos::PublicationPreflightEvidence.digest(repository: repository_document,
      publication_preflight: preflight_document, observed_remote_oid:, observed_at:)
  end
end
