require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe WorkflowCatalog::DefinitionValidator, :aggregate_failures do
  include WorkflowCatalogHelpers

  subject(:errors) { described_class.new(definition, task_type: quick_fix_task_type).errors }

  let(:definition) { workflow_definition }

  it "accepts the complete quick-fix workflow" do
    expect(errors).to be_empty
  end

  it "reports deterministic errors" do
    add_duplicate_status_and_unknown_endpoint

    expect(errors).to eq(errors.sort_by { |error| error.values_at("field", "message") })
    expect(errors.map { |error| error.fetch("message") }).to include(
      a_string_starting_with("Duplicate status identifier"), "Transition endpoint is unknown"
    )
  end

  it "rejects a non-executable initial status and executable terminal status" do
    definition["initial_status"] = "missing"
    definition["terminal_status"] = definition.fetch("statuses").first.fetch("id")

    expect(errors.map { |error| error.fetch("field") }).to include("/initial_status", "/terminal_status")
  end

  it "rejects terminal outgoing, duplicate, self, unknown, missing, and unreachable transitions" do
    add_invalid_transitions

    messages = errors.map { |error| error.fetch("message") }
    expect(messages).to include(a_string_starting_with("Duplicate transition"),
      "Transition endpoints must be distinct", "A transition cannot leave the terminal status",
      "Executable status must have an outgoing transition", "Status is unreachable from the initial status")
  end

  it "enforces always and per-edge condition uniqueness" do
    add_invalid_edge_conditions

    expect(errors.map { |error| error.fetch("message") }).to include(
      "Always must be the sole condition and requires no artifact output",
      "Duplicate artifact condition: document", "A decision has multiple values on one edge: ready"
    )
  end

  it "rejects ambiguous decision branches" do
    definition.fetch("transitions").select { |transition| transition.fetch("from") == "review" }.each do |transition|
      transition.fetch("conditions") << { "type" => "decision", "decision" => "ready", "value" => "yes" }
    end

    expect(errors.map { |error| error.fetch("message") }).to include("Decision branch is ambiguous for ready=yes")
  end

  it "requires declared artifact evidence or waiver on every edge" do
    replace_first_edge_with_undeclared_artifact

    expect(errors.map { |error| error.fetch("message") }).to include(
      "Required artifact lacks evidence or waiver: document",
      "Artifact condition is not declared by the source status: review"
    )
  end

  it "requires allowed artifact states to have evidence-bearing routes" do
    review_edges = definition.fetch("transitions").select { |edge| edge.fetch("from") == "review" }
    review_edges.last["conditions"] = [ { "type" => "not-applicable", "artifact_type" => "review" } ]

    expect(errors.map { |error| error.fetch("message") }).to include(
      "Artifact state has no evidence-bearing route: approved"
    )
  end

  it "rejects artifact states outside the source requirement" do
    condition = definition.fetch("transitions").first.fetch("conditions").first
    condition["state"] = "failed"

    expect(errors.map { |error| error.fetch("message") }).to include(
      "Artifact state is not allowed by the source status: document"
    )
  end

  it "enforces repository and worktree policies" do
    forbid_changes_without_worktree

    expect(errors.map { |error| error.fetch("message") }).to include(
      "Repository effects conflict with change policy", "Repository effects require a worktree"
    )
  end

  it "enforces instruction, template, and aggregate UTF-8 byte limits" do
    oversize_first_status
    stub_const("WorkflowCatalog::DefinitionValidator::STATE_CONTENT_LIMIT", 10)

    expect(errors.map { |error| error.fetch("message") }).to include(
      "Content exceeds the UTF-8 byte limit", "Instruction and templates exceed the state byte limit"
    )
  end

  it "rejects schema and workflow identity mismatches structurally" do
    definition["unknown"] = true
    definition["workflow_id"] = "other"

    result = described_class.new(definition, task_type: quick_fix_task_type).structural_errors
    expect(result.map { |error| error.fetch("field") }).to include("/", "/workflow_id")
  end

  it "rejects duplicate template and artifact requirement identities before publication" do
    duplicate_template_and_requirement

    expect(errors.map { |error| error.fetch("message") }).to include(
      "Duplicate artifact template identifier: implementation-plan", "Duplicate artifact requirement: document"
    )
  end

  def add_duplicate_status_and_unknown_endpoint
    definition.fetch("statuses") << deep_copy(definition.fetch("statuses").first)
    definition.fetch("transitions").first["to"] = "missing"
  end

  def add_invalid_transitions
    definition.fetch("transitions") << deep_copy(definition.fetch("transitions").first)
    definition.fetch("transitions") << { "from" => "completed", "to" => "completed",
      "conditions" => [ { "type" => "always" } ] }
    definition.fetch("transitions").delete_if { |edge| edge.fetch("from") == "publication" }
  end

  def add_invalid_edge_conditions
    definition.fetch("transitions").first["conditions"] = [ { "type" => "always" },
      { "type" => "artifact-present", "artifact_type" => "document" },
      { "type" => "artifact-state", "artifact_type" => "document", "state" => "produced" },
      { "type" => "decision", "decision" => "ready", "value" => "yes" },
      { "type" => "decision", "decision" => "ready", "value" => "no" } ]
  end

  def replace_first_edge_with_undeclared_artifact
    definition.fetch("transitions").first["conditions"] =
      [ { "type" => "artifact-present", "artifact_type" => "review" } ]
  end

  def forbid_changes_without_worktree
    definition.fetch("statuses").first.merge!("worktree" => "none", "repository_changes" => "forbidden")
  end

  def oversize_first_status
    status = definition.fetch("statuses").first
    status["instruction"] = "a" * (described_class::INSTRUCTION_LIMIT + 1)
    status.fetch("artifact_templates").first["content"] = "b" * (described_class::TEMPLATE_LIMIT + 1)
  end

  def duplicate_template_and_requirement
    status = definition.fetch("statuses").first
    status.fetch("artifact_templates") << deep_copy(status.fetch("artifact_templates").first)
    status.fetch("required_artifacts") << deep_copy(status.fetch("required_artifacts").first)
  end
end
