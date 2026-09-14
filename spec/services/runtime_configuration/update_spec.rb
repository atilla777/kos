require "rails_helper"

RSpec.describe RuntimeConfiguration::Update do
  it "updates the singleton and advances its lock version" do
    config = described_class.call(retrospective_enabled: true, expected_lock_version: 0)

    expect(config.attributes.values_at("id", "retrospective_enabled", "lock_version")).to eq([ 1, true, 1 ])
  end

  it "rejects a stale lock without changing the setting" do
    described_class.call(retrospective_enabled: true, expected_lock_version: 0)

    expect(stale_update_summary).to eq([ "stale_lock_version", true, 1 ])
  end

  def stale_update_summary
    error = begin
      described_class.call(retrospective_enabled: false, expected_lock_version: 0)
    rescue OperationError => exception
      exception.code
    end
    [ error, *RuntimeConfig.current.attributes.values_at("retrospective_enabled", "lock_version") ]
  end
end
