require "rails_helper"

RSpec.describe Kos::State::ServiceLock do
  let(:temporary_directory) { Pathname.new(Dir.mktmpdir("kos-service-lock")) }
  let(:root) { temporary_directory.join("state") }
  let(:layout) { Kos::State::Layout.new(root_path: root, database_path: root.join("kos.sqlite3")).prepare! }

  after { FileUtils.remove_entry(temporary_directory) }

  it "allows concurrent shared service locks" do
    leases = [ described_class.new(layout).acquire_shared, described_class.new(layout).acquire_shared ]

    expect(leases).to all(satisfy { |lease| !lease.closed? })
  ensure
    leases&.each(&:close)
  end

  it "rejects an exclusive prepare lock while a service lock is held" do
    service = described_class.new(layout).acquire_shared

    expect { described_class.new(layout).acquire_exclusive }.to raise_error(Kos::State::Error, /service is running/)
  ensure
    service&.close
  end

  it "rejects a service lock while preparation is active" do
    prepare = described_class.new(layout).acquire_exclusive

    expect { described_class.new(layout).acquire_shared }.to raise_error(Kos::State::Error, /being prepared/)
  ensure
    prepare&.close
  end

  it "rejects another exclusive lock while preparation is active" do
    prepare = described_class.new(layout).acquire_exclusive

    expect { described_class.new(layout).acquire_exclusive }.to raise_error(Kos::State::Error, /already active/)
  ensure
    prepare&.close
  end
end
