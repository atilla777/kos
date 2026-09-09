require "spec_helper"

module TaskModelContract
  SPECIFICATION = File.read(File.expand_path("../../docs/specs/task-model.md", __dir__))
  TRACEABILITY_BLOCK = SPECIFICATION.match(/Task-local Markdown artifacts.*?```text\n(?<ids>.*?)```/m)
  TRACEABILITY_IDS = TRACEABILITY_BLOCK[:ids].lines(chomp: true)
  EXPECTED_IDS = %w[
    KOS-000123-REQ-001 KOS-000123-DEC-001 KOS-000123-Q-001 KOS-000123-RISK-001 KOS-000123-AC-001
  ]
end

RSpec.describe TaskModelContract do
  it "uses unique repository-specific traceability examples" do
    expect(described_class::TRACEABILITY_IDS).to eq(described_class::EXPECTED_IDS)
  end
end
