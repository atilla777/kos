require "spec_helper"
require_relative "../../lib/kos/runtime/open_code/capability_verifier"

module OpenCodeRetrospectiveExecutableContract
  module_function

  def observations
    Kos::Runtime::OpenCode::CapabilityVerifier.expected_report.fetch("observations")
  end
end

RSpec.describe OpenCodeRetrospectiveExecutableContract do
  let(:observations) { described_class.observations }

  it "records the real child retrospective path in the pinned capability report" do
    expect(observations.values_at("retrospective_child_delivery", "retrospective_child_timeout_independence")
      .map { |observation| observation.fetch("outcome") }).to eq(%w[passed passed])
  end

  it "records the real root retrospective path in the pinned capability report" do
    expect(observations.values_at("retrospective_root_post_primary", "retrospective_timeout_failure_independence")
      .map { |observation| observation.fetch("outcome") }).to eq(%w[passed passed])
  end
end
