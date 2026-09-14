require "json"
require "open3"
require "spec_helper"

module OpenCodeSessionGuardContract
  PLUGIN = File.expand_path("../../runtime/opencode/plugins/kos-session-guard.js", __dir__)

  module_function

  def probe_script
    File.read(PLUGIN) + <<~JAVASCRIPT
      let calls = 0;
      let messageAborted = false;
      const client = { session: { messages: async (request) => {
        if (request.path.id === "ses_cancel") return new Promise((_resolve, reject) =>
          request.signal.addEventListener("abort", () => { messageAborted = true; reject(new Error("aborted")); },
            { once: true }));
        if (request.path.id === "ses_bound") return { data: new Array(10001).fill("") };
        if (request.path.id === "ses_bytes") return { data: ["x".repeat(4 * 1024 * 1024 + 1)] };
        return { data: [{ parts: [{ type: "text", text: "source dialogue" }] }] };
      }, prompt: async (request) => {
        calls += 1;
        const invocation = JSON.parse(request.body.parts[0].text);
        const proposals = request.path.id === "ses_sensitive" ? [{ category: "project",
          problem: "prefix source dialogue suffix", observed_impact: "impact", sanitized_evidence: "evidence",
          proposed_outcome: "outcome", suggested_task_type: "quick-fix", uncertainties: [] }] : [];
        return { data: { parts: [{ type: "text", text: JSON.stringify({ schema_version: "1",
          session_id: invocation.session_id, source: invocation.source, primary_result_acknowledged: true,
          outcome: proposals.length ? "proposals" : "no_action", proposals }) }] } };
      } } };
      const hooks = await KosSessionGuard({ client });
      const oid = "b".repeat(40);
      const digest = `sha256:${"c".repeat(64)}`;
      const artifacts = [
        { schema_version: "1", type: "document", state: "produced", producer: "worker",
          metadata: { kind: "document", path: "docs/result.md", commit_sha: oid, content_digest: digest } },
        { schema_version: "1", type: "candidate", state: "produced", producer: "worker",
          metadata: { kind: "candidate", candidate_sha: oid, task_trailer: "KOS-000001" } },
        { schema_version: "1", type: "test", state: "passed", producer: "worker",
          metadata: { kind: "test", candidate_sha: oid, command: "bundle exec rspec", exit_code: 0,
            log_digest: digest } },
        { schema_version: "1", type: "review", state: "approved", producer: "reviewer",
          metadata: { kind: "review", candidate_sha: oid, verdict: "approved",
            review_attempt_id: "33333333-3333-4333-8333-333333333333" } },
        { schema_version: "1", type: "publication", state: "published", producer: "publisher",
          metadata: { kind: "publication", publication_id: "44444444-4444-4444-8444-444444444444",
            candidate_sha: oid, remote: "origin", base_ref: "refs/heads/main", observed_remote_tip: oid,
            reachable: true, observed_at: "2026-09-14T09:00:00Z" } }
      ];
      const manifestValue = { schema_version: "1", attempt_id: "22222222-2222-4222-8222-222222222222",
        input_context_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        outcome: "succeeded", artifacts };
      const manifest = JSON.stringify(manifestValue);
      const bind = async (parent, child, body = manifest, subagent_type = "kos-workflow-step") => {
        const input = { tool: "task", sessionID: parent, args: { subagent_type } };
        await hooks["tool.execute.before"](input, { args: { subagent_type } });
        await hooks["tool.execute.after"](input, { metadata: { sessionId: child },
          output: `<task id="${child}" state="completed">\n<task_result>\n${body}\n</task_result>\n</task>` });
      };

      const initial = { tool: "task", sessionID: "ses_parent", args: { subagent_type: "kos-workflow-step" } };
      await hooks["tool.execute.before"](initial, { args: initial.args });
      let concurrentInitialRejected = false;
      try { await hooks["tool.execute.before"](initial, { args: initial.args }); } catch { concurrentInitialRejected = true; }
      await hooks["tool.execute.after"](initial, { metadata: { sessionId: "ses_child" },
        output: `<task id="ses_child" state="completed">\n<task_result>\n${manifest}\n</task_result>\n</task>` });
      const context = { sessionID: "ses_parent", abort: new AbortController().signal };
      const args = { child_session_id: "ses_child" };
      let extraRejected = false;
      try { await hooks.tool.child_retrospective.execute({ ...args, extra: true }, context); } catch { extraRejected = true; }
      const delivery = JSON.parse(await hooks.tool.child_retrospective.execute(args, context));
      let duplicateRejected = false;
      try { await hooks.tool.child_retrospective.execute(args, context); } catch { duplicateRejected = true; }

      const rejectedManifest = async (parent, child, value) => {
        await bind(parent, child, value);
        try {
          await hooks.tool.child_retrospective.execute({ child_session_id: child },
            { sessionID: parent, abort: new AbortController().signal });
          return false;
        } catch { return true; }
      };
      const malformedManifestRejected = await rejectedManifest("parent_bad", "child_bad", "{}");
      const invalidArtifactRejected = await rejectedManifest("parent_artifact", "child_artifact",
        JSON.stringify({ ...manifestValue, artifacts: ["invalid"] }));
      const malformedMetadata = structuredClone(manifestValue);
      malformedMetadata.artifacts[0].metadata.commit_sha = "invalid";
      const malformedMetadataRejected = await rejectedManifest("parent_metadata", "child_metadata",
        JSON.stringify(malformedMetadata));
      await bind("parent_agent", "child_agent", manifest, "other-agent");
      let wrongAgentRejected = false;
      try { await hooks.tool.child_retrospective.execute({ child_session_id: "child_agent" },
        { sessionID: "parent_agent", abort: new AbortController().signal }); } catch { wrongAgentRejected = true; }

      await bind("parent_cancel", "ses_cancel");
      const cancelledController = new AbortController();
      cancelledController.abort();
      const cancelled = JSON.parse(await hooks.tool.child_retrospective.execute({ child_session_id: "ses_cancel" },
        { sessionID: "parent_cancel", abort: cancelledController.signal }));
      await bind("parent_sensitive", "ses_sensitive");
      const sensitive = JSON.parse(await hooks.tool.child_retrospective.execute({ child_session_id: "ses_sensitive" },
        { sessionID: "parent_sensitive", abort: new AbortController().signal }));
      const callsBeforeBound = calls;
      await bind("parent_bound", "ses_bound");
      const bounded = JSON.parse(await hooks.tool.child_retrospective.execute({ child_session_id: "ses_bound" },
        { sessionID: "parent_bound", abort: new AbortController().signal }));
      await bind("parent_bytes", "ses_bytes");
      const byteBounded = JSON.parse(await hooks.tool.child_retrospective.execute({ child_session_id: "ses_bytes" },
        { sessionID: "parent_bytes", abort: new AbortController().signal }));
      const boundPromptCalls = calls - callsBeforeBound;

      const multiOutcomes = [];
      for (let index = 0; index < 5; index += 1) {
        const child = `multi_${index}`;
        await bind("parent_multi", child);
        multiOutcomes.push(JSON.parse(await hooks.tool.child_retrospective.execute({ child_session_id: child },
          { sessionID: "parent_multi", abort: new AbortController().signal })).outcome);
      }
      await bind("parent_multi", "multi_limit");
      const limited = JSON.parse(await hooks.tool.child_retrospective.execute({ child_session_id: "multi_limit" },
        { sessionID: "parent_multi", abort: new AbortController().signal }));
      await hooks.event({ event: { type: "session.deleted", properties: { info: { id: "ses_parent" } } } });
      let deletedRejected = false;
      try { await hooks.tool.child_retrospective.execute(args, context); } catch { deletedRejected = true; }
      console.log(JSON.stringify({ outcome: delivery.outcome, calls, extra_rejected: extraRejected,
        duplicate_rejected: duplicateRejected, deleted_rejected: deletedRejected,
        malformed_manifest_rejected: malformedManifestRejected, invalid_artifact_rejected: invalidArtifactRejected,
        malformed_metadata_rejected: malformedMetadataRejected, wrong_agent_rejected: wrongAgentRejected,
        concurrent_initial_rejected: concurrentInitialRejected, cancellation_reason: cancelled.reason,
        messages_aborted: messageAborted, sanitation_reason: sensitive.reason, bound_reason: bounded.reason,
        byte_bound_reason: byteBounded.reason, bound_prompt_calls: boundPromptCalls,
        multi_results: multiOutcomes.length, limit_reason: limited.reason,
        source: delivery.invocation.source, timeout_seconds: delivery.invocation.timeout_seconds }));
    JAVASCRIPT
  end

  def timeout_probe_script
    File.read(PLUGIN).sub("const TIMEOUT_SECONDS = 30", "const TIMEOUT_SECONDS = 0.01") + <<~JAVASCRIPT
      let aborted = false;
      let prompts = 0;
      const client = { session: { messages: async (request) => new Promise((_resolve, reject) =>
        request.signal.addEventListener("abort", () => { aborted = true; reject(new Error("aborted")); },
          { once: true })), prompt: async () => { prompts += 1; return {}; } } };
      const hooks = await KosSessionGuard({ client });
      const input = { tool: "task", sessionID: "parent", args: { subagent_type: "kos-workflow-step" } };
      await hooks["tool.execute.before"](input, { args: input.args });
      const manifest = JSON.stringify({ schema_version: "1", attempt_id: "22222222-2222-4222-8222-222222222222",
        input_context_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        outcome: "succeeded", artifacts: [] });
      await hooks["tool.execute.after"](input, { metadata: { sessionId: "child" },
        output: `<task id="child" state="completed">\n<task_result>\n${manifest}\n</task_result>\n</task>` });
      const context = { sessionID: "parent", abort: new AbortController().signal };
      const delivery = JSON.parse(await hooks.tool.child_retrospective.execute({ child_session_id: "child" }, context));
      await new Promise((resolve) => setTimeout(resolve, 30));
      let lateRejected = false;
      try { await hooks.tool.child_retrospective.execute({ child_session_id: "child" }, context); }
      catch { lateRejected = true; }
      console.log(JSON.stringify({ reason: delivery.reason, aborted, prompts, late_rejected: lateRejected }));
    JAVASCRIPT
  end
end

RSpec.describe OpenCodeSessionGuardContract do
  it "validates lifecycle, manifests, privacy bounds, cancellation, concurrency, and result limits" do
    expect(probe_result(described_class.probe_script)).to eq(expected_probe_result)
  end

  it "bounds child message retrieval independently and absorbs late completion" do
    expect(probe_result(described_class.timeout_probe_script)).to eq([ true, "",
      { "reason" => "timeout", "aborted" => true, "prompts" => 0, "late_rejected" => true } ])
  end

  def expected_probe_result
    [ true, "", {
      "outcome" => "result", "calls" => 7, "extra_rejected" => true, "duplicate_rejected" => true,
      "deleted_rejected" => true, "malformed_manifest_rejected" => true, "invalid_artifact_rejected" => true,
      "malformed_metadata_rejected" => true, "wrong_agent_rejected" => true,
      "concurrent_initial_rejected" => true, "cancellation_reason" => "cancelled", "messages_aborted" => true,
      "sanitation_reason" => "malformed_result", "bound_reason" => "transport_failure", "bound_prompt_calls" => 0,
      "byte_bound_reason" => "transport_failure", "multi_results" => 5, "limit_reason" => "limit_reached",
      "source" => "workflow_step",
      "timeout_seconds" => 30
    } ]
  end

  def probe_result(script)
    stdout, stderr, status = Open3.capture3({ "KOS_RETROSPECTIVE_ENABLED" => "1" }, "node",
      "--input-type=module", stdin_data: script)
    [ status.success?, stderr, JSON.parse(stdout) ]
  end
end
