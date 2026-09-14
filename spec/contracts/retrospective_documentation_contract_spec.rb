require "spec_helper"

module RetrospectiveDocumentationContract
  ROOT = File.expand_path("../..", __dir__)

  DOCUMENT_CONTRACTS = {
    "README.md" => [ "kos-opencode", "KOS_RETROSPECTIVE_FD", "fixed 30-second budget", "managed upgrade",
      "not a semantic privacy guarantee", "Custom OpenCode config-file, config-content, and config-directory overrides" ],
    "docs/specs/retrospective.md" => [ "samples that setting once", "`child_retrospective`", "fixed 30-second budget",
      "`no_result`", "`no_action`", "at most five sanitized child results", "same OpenCode session",
      "`subagent_type` is exactly `kos-workflow-step`", "with only the retained `child_session_id`",
      "deterministically rejects obvious", "rather than a semantic privacy guarantee" ],
    "docs/specs/runtime-integration.md" => [ "production `kos-opencode`", "second external", "`KOS_RETROSPECTIVE_FD`",
      "five sanitized child results", "managed upgrade", "calls `child_retrospective` with only `child_session_id`",
      "structural backstop does not claim semantic detection", "embeds the complete procedure",
      "exact ten-file managed inventory", "launcher-controlled empty `XDG_CONFIG_HOME`" ],
    "docs/specs/initialization.md" => [ "including retrospective lifecycle transport", "managed upgrade",
      "`kos-opencode` process adapter", "embeds the complete procedure and closed result instructions" ],
    "docs/specs/workflow-execution.md" => [ "exact `kos-workflow-step` Task route", "only the retained `child_session_id`",
      "external second prompt", "valid `no_action`", "cannot prove" ],
    "docs/specs/cli-protocol.md" => [ "`runtime_config.get` returns", "disabled by default", "samples this resource once" ],
    "docs/decisions/0008-opencode-runtime-adapter.md" => [ "currently executing root session", "`kos-opencode` process adapter",
      "fixed 30-second budget", "No more than five sanitized child results", "managed installation plan",
      "with only the retained `child_session_id`", "do not claim to infer arbitrary prose semantics" ],
    "docs/decisions/0009-runtime-bundle-installation.md" => [ "restrictive orchestrator, workflow-step, and retrospective",
      "embeds the complete analysis, sanitization, and closed result procedure", "even when retrospective is disabled" ],
    "runtime/opencode/agents/kos-retrospective.md" => [ "concrete evidence", "Do not speculate",
      "systemic issue from a one-off", "smallest independently useful outcome", "Split independent findings",
      "Preserve every material uncertainty", "kos_product", "kos_installation", "workflow", "project",
      "Return `no_action`", "exactly one JSON object" ]
  }.freeze

  OBSOLETE_CLAIMS = [
    "does not yet provide the required graceful-end hook",
    "does not provide or claim graceful-end invocation",
    "Retrospective hooks and post-primary delivery require a separate adapter increment"
  ].freeze

  module_function

  def missing_phrases
    DOCUMENT_CONTRACTS.flat_map do |path, phrases|
      content = File.read(File.join(ROOT, path))
      phrases.reject { |phrase| content.include?(phrase) }.map { |phrase| [ path, phrase ] }
    end
  end

  def obsolete_claims
    paths = DOCUMENT_CONTRACTS.keys + %w[
      skills/kos-retrospective/SKILL.md skills/kos-orchestrate/SKILL.md skills/kos-initialize/SKILL.md
    ]
    paths.product(OBSOLETE_CLAIMS).select do |path, claim|
      File.read(File.join(ROOT, path)).include?(claim)
    end
  end
end

RSpec.describe RetrospectiveDocumentationContract do
  it "documents the implemented lifecycle in every durable user and behavior surface" do
    expect(described_class.missing_phrases).to be_empty
  end

  it "removes obsolete unavailable-transport claims from current documentation" do
    expect(described_class.obsolete_claims).to be_empty
  end
end
