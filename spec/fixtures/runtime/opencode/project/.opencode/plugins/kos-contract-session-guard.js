export const KosContractSessionGuard = async () => {
  const children = new Map()

  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "task") return

      const expected = children.get(input.sessionID)
      if ((expected && output.args.task_id !== expected) || (!expected && output.args.task_id)) {
        throw new Error("KOS runtime rejected an unretained child session")
      }
    },
    "tool.execute.after": async (input, output) => {
      if (input.tool !== "task" || input.args.task_id) return

      const child = output?.metadata?.sessionId
      if (!child) throw new Error("KOS runtime did not receive a child session")
      if (children.has(input.sessionID)) throw new Error("KOS runtime rejected child session rebinding")
      children.set(input.sessionID, child)
    },
  }
}
