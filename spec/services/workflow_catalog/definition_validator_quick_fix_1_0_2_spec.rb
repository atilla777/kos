require "rails_helper"

RSpec.describe WorkflowCatalog::DefinitionValidator, :aggregate_failures do
  let(:definition) { JSON.parse(File.read(Rails.root.join("workflows/quick-fix/1.0.2.json"))) }
  let(:task_type) { TaskType.new(id: "quick-fix", name: "quick-fix", workflow_id: "quick-fix") }

  it "pins the schema-valid recovery graph and canonical digest" do
    expect(graph_contract).to eq([ true, [],
      "sha256:3ef55969eb81400d058e152e0d0fb903fe5db00d8ea89caea5118edd2f1016b5",
      %w[base-synchronization development implementation-planning publication review], true ])
  end

  def graph_contract
    schema = Kos::Cli::SchemaRegistry.new
    transitions = definition.fetch("transitions").map { [ _1.fetch("from"), _1.fetch("to") ] }
    [ schema.valid?("workflow_definition.json", "definition", definition),
      described_class.new(definition, task_type:).errors, WorkflowCatalog::CanonicalDefinition.digest(definition),
      definition.fetch("statuses").map { _1.fetch("id") }.sort,
      transitions.include?([ "publication", "base-synchronization" ]) &&
        transitions.include?([ "base-synchronization", "review" ]) ]
  end

  it "authorizes only trusted fetch and rebase in the dedicated synchronization status" do
    expect(synchronization_contract).to eq([ %w[fetch rebase], %w[candidate test], [
      { "type" => "not-applicable", "artifact_type" => "publication" },
      { "type" => "decision", "decision" => "publication-outcome", "value" => "base-moved" }
    ] ])
  end

  def synchronization_contract
    status = definition.fetch("statuses").find { _1.fetch("id") == "base-synchronization" }
    recovery = definition.fetch("transitions").find {
      _1.fetch("from") == "publication" && _1.fetch("to") == "base-synchronization"
    }
    [ status.fetch("allowed_repository_effects"), status.fetch("required_artifacts").map { _1.fetch("type") },
      recovery.fetch("conditions") ]
  end
end
