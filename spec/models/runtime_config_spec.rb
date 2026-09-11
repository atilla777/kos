require "rails_helper"

RSpec.describe RuntimeConfig do
  def singleton_summary
    attributes = described_class.current.attributes.values_at("id", "retrospective_enabled", "lock_version")
    error = begin
      described_class.create!(retrospective_enabled: true)
    rescue ActiveRecord::StatementInvalid => exception
      exception.is_a?(ActiveRecord::StatementInvalid)
    end
    [ attributes, error ]
  end

  it "provides one durable installation-wide default" do
    expect(singleton_summary).to eq([ [ 1, false, 0 ], true ])
  end
end
