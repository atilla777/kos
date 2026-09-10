require "rails_helper"

RSpec.describe Kos::State::SchemaStatus do
  let(:migration_class) { Data.define(:version) }

  it "reports pending and unknown versions independently" do
    status = build_status(known: [ 1, 3 ], applied: [ 1, 2 ])

    expect(status_observation(status))
      .to eq(current: 2, pending: [ 3 ], unknown: [ 2 ], compatible: false)
  end

  it "rejects pending schema versions" do
    status = build_status(known: [ 1, 2 ], applied: [ 1 ])

    expect { status.validate_compatible! }.to raise_error(Kos::State::Error, /pending migrations: 2/)
  end

  it "rejects unknown schema versions" do
    status = build_status(known: [ 1 ], applied: [ 1, 2 ])

    expect { status.validate_no_unknown! }.to raise_error(Kos::State::Error, /unknown.*: 2/)
  end

  def build_status(known:, applied:)
    migrations = known.map { |version| migration_class.new(version) }
    context = instance_double(ActiveRecord::MigrationContext, migrations:, get_all_versions: applied)
    described_class.new(context)
  end

  def status_observation(status)
    {
      current: status.current_version, pending: status.pending_versions,
      unknown: status.unknown_versions, compatible: status.compatible?
    }
  end
end
