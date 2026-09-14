const TIMEOUT_SECONDS = 30
const MAX_RESULTS = 5
const MAX_PARENTS = 64
const MAX_DIALOGUE_NODES = 10000
const MAX_DIALOGUE_BYTES = 4 * 1024 * 1024
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const DIGEST = /^sha256:[0-9a-f]{64}$/
const OID = /^[0-9a-f]{40}$/
const IDENTIFIER = /^[a-z][a-z0-9_-]{0,127}$/
const TASK_NUMBER = /^[A-Z][A-Z0-9]{1,9}-[0-9]{6}$/
const SENSITIVE_TEXT = [/(?:api[_-]?key|token|secret|password)\s*[:=]\s*\S+/i,
  /\b[A-Z][A-Z0-9_]{2,}\s*=\s*\S+/, /(?:^|\s)\/(?:home|Users|root)\/\S+/, /[A-Za-z]:\\Users\\\S+/]

const exactKeys = (value, required, optional = []) => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false
  const keys = Object.keys(value)
  return required.every((key) => keys.includes(key)) && keys.every((key) => required.includes(key) || optional.includes(key))
}

const validText = (value, maximum) => typeof value === "string" && value.length > 0 && value.length <= maximum
const nonemptyText = (value) => typeof value === "string" && value.length > 0
const repositoryPath = (value) => nonemptyText(value) && !value.startsWith("/") && !value.includes("\0") &&
  !value.split("/").includes("..")
const timestamp = (value) => typeof value === "string" && value.endsWith("Z") &&
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value) && !Number.isNaN(Date.parse(value)) &&
  new Date(value).toISOString().slice(0, 10) === value.slice(0, 10)

const validMetadata = (type, state, value) => {
  if (!value || value.kind !== type) return false
  switch (type) {
    case "document":
      return state === "produced" && exactKeys(value, ["kind", "path", "commit_sha", "content_digest"]) &&
        repositoryPath(value.path) && OID.test(value.commit_sha) && DIGEST.test(value.content_digest)
    case "candidate":
      return state === "produced" && exactKeys(value, ["kind", "candidate_sha", "task_trailer"]) &&
        OID.test(value.candidate_sha) && TASK_NUMBER.test(value.task_trailer)
    case "test":
      return ["passed", "failed"].includes(state) &&
        exactKeys(value, ["kind", "candidate_sha", "command", "exit_code", "log_digest"]) &&
        OID.test(value.candidate_sha) && nonemptyText(value.command) && Number.isInteger(value.exit_code) &&
        ((state === "passed" && value.exit_code === 0) || (state === "failed" && value.exit_code >= 1)) &&
        DIGEST.test(value.log_digest)
    case "review":
      return ["approved", "changes_requested"].includes(state) &&
        exactKeys(value, ["kind", "candidate_sha", "verdict", "review_attempt_id"]) &&
        OID.test(value.candidate_sha) && value.verdict === state && UUID.test(value.review_attempt_id)
    case "publication":
      return state === "published" && exactKeys(value,
        ["kind", "publication_id", "candidate_sha", "remote", "base_ref", "observed_remote_tip", "reachable",
          "observed_at"]) && UUID.test(value.publication_id) && OID.test(value.candidate_sha) &&
        IDENTIFIER.test(value.remote) && /^refs\/heads\/[^ ]+$/.test(value.base_ref) &&
        OID.test(value.observed_remote_tip) && value.reachable === true && timestamp(value.observed_at)
    default:
      return false
  }
}

const validArtifact = (value) => exactKeys(value, ["schema_version", "type", "state", "producer", "metadata"]) &&
  value.schema_version === "1" && ["document", "candidate", "test", "review", "publication"].includes(value.type) &&
  ["produced", "passed", "failed", "approved", "changes_requested", "published"].includes(value.state) &&
  IDENTIFIER.test(value.producer) && validMetadata(value.type, value.state, value.metadata)

const utf8Length = (value) => {
  let length = 0
  for (const character of value) {
    const codepoint = character.codePointAt(0)
    length += codepoint <= 0x7f ? 1 : codepoint <= 0x7ff ? 2 : codepoint <= 0xffff ? 3 : 4
  }
  return length
}

const proposalText = (result) => result.proposals.flatMap((proposal) =>
  [proposal.problem, proposal.observed_impact, proposal.sanitized_evidence, proposal.proposed_outcome,
    ...proposal.uncertainties])

const validResult = (value, invocation) => {
  const fields = ["schema_version", "session_id", "source", "primary_result_acknowledged", "outcome", "proposals"]
  if (!exactKeys(value, fields) || value.schema_version !== "1" || value.session_id !== invocation.session_id ||
      value.source !== invocation.source || value.primary_result_acknowledged !== true ||
      !["no_action", "proposals"].includes(value.outcome) || !Array.isArray(value.proposals) ||
      value.proposals.length > 5 || (value.outcome === "no_action" && value.proposals.length !== 0) ||
      (value.outcome === "proposals" && value.proposals.length === 0)) return false

  return value.proposals.every((proposal) => {
    const required = ["category", "problem", "observed_impact", "sanitized_evidence", "proposed_outcome",
      "suggested_task_type", "uncertainties"]
    if (!exactKeys(proposal, required, ["workflow_version_id", "repository_id"])) return false
    if (!["kos_product", "kos_installation", "workflow", "project"].includes(proposal.category)) return false
    if (![proposal.problem, proposal.observed_impact, proposal.sanitized_evidence, proposal.proposed_outcome]
      .every((text) => validText(text, 4096))) return false
    if (!/^[a-z][a-z0-9_-]{0,127}$/.test(proposal.suggested_task_type)) return false
    if (!Array.isArray(proposal.uncertainties) || proposal.uncertainties.length > 10 ||
        !proposal.uncertainties.every((text) => validText(text, 1024))) return false
    return [proposal.workflow_version_id, proposal.repository_id].every((id) => id === undefined || UUID.test(id))
  })
}

const parseManifest = (output, child) => {
  const match = output?.match(/^<task id="([^"]+)" state="completed">\n<task_result>\n([\s\S]*)\n<\/task_result>\n<\/task>$/)
  if (!match || match[1] !== child) return
  try {
    const value = JSON.parse(match[2])
    const required = ["schema_version", "attempt_id", "input_context_digest", "outcome", "artifacts"]
    if (!exactKeys(value, required, ["summary"]) || value.schema_version !== "1" || !UUID.test(value.attempt_id) ||
        !DIGEST.test(value.input_context_digest) || !["succeeded", "failed", "needs_human"].includes(value.outcome) ||
        !Array.isArray(value.artifacts) || !value.artifacts.every(validArtifact) ||
        (value.summary !== undefined && !nonemptyText(value.summary))) return
    return { attemptID: value.attempt_id, inputContextDigest: value.input_context_digest, outcome: value.outcome }
  } catch {
    return
  }
}

const inspectDialogue = (value, texts = []) => {
  const stack = [value]
  let nodes = 0
  let bytes = 0
  while (stack.length) {
    const item = stack.pop()
    nodes += 1
    if (nodes > MAX_DIALOGUE_NODES) return { truncated: true, leaked: false }
    if (typeof item === "string") {
      bytes += utf8Length(item)
      if (bytes > MAX_DIALOGUE_BYTES) return { truncated: true, leaked: false }
      if (texts.some((text) => item.length >= 8 && (item.includes(text) || text.includes(item)))) {
        return { truncated: false, leaked: true }
      }
    } else if (Array.isArray(item)) {
      if (nodes + stack.length + item.length > MAX_DIALOGUE_NODES) return { truncated: true, leaked: false }
      for (const nested of item) stack.push(nested)
    } else if (item && typeof item === "object") {
      for (const key in item) {
        if (!Object.hasOwn(item, key)) continue
        if (nodes + stack.length + 1 > MAX_DIALOGUE_NODES) return { truncated: true, leaked: false }
        stack.push(item[key])
      }
    }
  }
  return { truncated: false, leaked: false }
}

const sanitized = (result, dialogue) => {
  const texts = proposalText(result)
  const inspection = inspectDialogue(dialogue, texts)
  return !texts.some((text) => SENSITIVE_TEXT.some((pattern) => pattern.test(text))) &&
    !inspection.leaked && !inspection.truncated
}

const noResult = (runtimeSessionID, invocation, reason) => JSON.stringify({
  schema_version: "1", runtime: "opencode", runtime_session_id: runtimeSessionID,
  invocation, outcome: "no_result", reason,
})

const retainBounded = (map, key, value) => {
  map.set(key, value)
  while (map.size > MAX_PARENTS) map.delete(map.keys().next().value)
}

export const KosSessionGuard = async ({ client, directory }) => {
  const children = new Map()
  const results = new Map()

  const removeSession = (sessionID) => {
    children.delete(sessionID)
    results.delete(sessionID)
    for (const [parent, child] of children) {
      if (child.id === sessionID) {
        children.delete(parent)
        results.delete(parent)
      }
    }
  }

  return {
    event: async ({ event }) => {
      if (event.type === "session.deleted") removeSession(event.properties.info.id)
    },
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "task") return

      const retained = children.get(input.sessionID)
      if (output.args.task_id) {
        if (!retained || retained.pending || output.args.task_id !== retained.id) {
          throw new Error("KOS runtime rejected an unretained child session")
        }
        return
      }
      if (retained) {
        throw new Error("KOS runtime rejected an unretained child session")
      }
      if (children.size >= MAX_PARENTS) throw new Error("KOS runtime child session limit reached")
      children.set(input.sessionID, { id: undefined,
        eligible: output.args.subagent_type === "kos-workflow-step", manifest: undefined, invoked: false, pending: true })
    },
    "tool.execute.after": async (input, output) => {
      if (input.tool !== "task") return

      const childID = output?.metadata?.sessionId
      if (!childID) throw new Error("KOS runtime did not receive a child session")
      if (input.args.task_id) {
        const retained = children.get(input.sessionID)
        if (!retained || retained.id !== childID) throw new Error("KOS runtime rejected an unretained child session")
        retained.manifest = parseManifest(output.output, childID)
        return
      }
      const retained = children.get(input.sessionID)
      if (!retained?.pending) throw new Error("KOS runtime rejected child session rebinding")
      retained.id = childID
      retained.manifest = parseManifest(output.output, childID)
      retained.pending = false
    },
    tool: {
      // OpenCode 1.18.26 supports these JSON Schema entries through its dependency-free plugin compatibility path.
      child_retrospective: {
        description: "Continue an acknowledged completed KOS workflow-step child for private retrospective analysis.",
        args: { child_session_id: { type: "string", minLength: 1, maxLength: 256 } },
        async execute(args, context) {
          const retained = children.get(context.sessionID)
          if (!exactKeys(args, ["child_session_id"]) || process.env.KOS_RETROSPECTIVE_ENABLED !== "1" ||
              process.env.KOS_RETROSPECTIVE_ACTIVE === "1" || !retained?.eligible || !retained.manifest ||
              retained.id !== args.child_session_id || retained.invoked) {
            throw new Error("KOS runtime rejected retrospective lifecycle input")
          }

          retained.invoked = true
          const invocation = {
            schema_version: "1", session_id: crypto.randomUUID(), source: "workflow_step",
            retrospective_enabled: true, lifecycle_eligible: true, recursion_suppressed: true,
            primary_result_acknowledged: true, timeout_seconds: TIMEOUT_SECONDS,
          }
          const retainedResults = results.get(context.sessionID) ?? []
          if (retainedResults.length >= MAX_RESULTS) {
            children.delete(context.sessionID)
            return noResult(retained.id, invocation, "limit_reached")
          }

          const controller = new AbortController()
          const operation = (async () => {
            const messages = await client.session.messages({ path: { id: retained.id },
              ...(directory ? { query: { directory } } : {}), signal: controller.signal })
            if (messages.error || !Array.isArray(messages.data)) throw new Error("child dialogue unavailable")
            if (inspectDialogue(messages.data).truncated) return { reason: "transport_failure" }
            const response = await client.session.prompt({ path: { id: retained.id },
              body: { agent: "kos-retrospective", parts: [{ type: "text", text: JSON.stringify(invocation) }] },
              signal: controller.signal })
            if (response.error) return { reason: "provider_failure" }
            const text = response.data?.parts?.filter((part) => part.type === "text").map((part) => part.text).join("")
            let result
            try { result = JSON.parse(text) } catch { return { reason: "malformed_result" } }
            if (!validResult(result, invocation) || !sanitized(result, messages.data)) {
              return { reason: "malformed_result" }
            }
            return { result }
          })()
          operation.catch(() => {})

          let timer
          let cancel
          const boundary = new Promise((resolve) => {
            timer = setTimeout(() => resolve({ reason: "timeout" }), TIMEOUT_SECONDS * 1000)
            cancel = () => resolve({ reason: "cancelled" })
            if (context.abort.aborted) cancel()
            else context.abort.addEventListener("abort", cancel, { once: true })
          })
          let settled
          try {
            settled = await Promise.race([operation, boundary])
          } catch {
            settled = { reason: "transport_failure" }
          } finally {
            clearTimeout(timer)
            context.abort.removeEventListener("abort", cancel)
          }
          if (settled.reason) {
            controller.abort()
            try {
              const abortRequest = client.session.abort?.({ path: { id: retained.id },
                ...(directory ? { query: { directory } } : {}) })
              abortRequest?.catch(() => {})
            } catch {}
            children.delete(context.sessionID)
            return noResult(retained.id, invocation, settled.reason)
          }

          retainedResults.push(settled.result)
          retainBounded(results, context.sessionID, retainedResults.slice(-MAX_RESULTS))
          children.delete(context.sessionID)
          return JSON.stringify({ schema_version: "1", runtime: "opencode", runtime_session_id: retained.id,
            invocation, outcome: "result", result: settled.result })
        },
      },
    },
  }
}
