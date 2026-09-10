require "rails_helper"

RSpec.describe Kos::State::ServerStartup do
  let(:temporary_directory) { Pathname.new(Dir.mktmpdir("kos-server-startup")) }
  let(:root) { temporary_directory.join("state") }
  let(:layout) { Kos::State::Layout.new(root_path: root, database_path: root.join("kos.sqlite3")).prepare! }
  let(:migration_context) { instance_double(ActiveRecord::MigrationContext, migrations: [], get_all_versions: []) }
  let(:connection_pool) { instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool, migration_context:) }

  after do
    described_class.instance_variable_get(:@lease)&.close
    described_class.remove_instance_variable(:@lease) if described_class.instance_variable_defined?(:@lease)
    FileUtils.remove_entry(temporary_directory)
  end

  it "retains a shared lock for the serving process lifetime" do
    create_database
    described_class.call(layout:, connection_pool:)

    expect { Kos::State::ServiceLock.new(layout).acquire_exclusive }
      .to raise_error(Kos::State::Error, /service is running/)
  end

  it "releases the shared lock when schema validation fails" do
    create_database
    allow(migration_context).to receive(:migrations).and_return([ Data.define(:version).new(1) ])

    expect(failed_startup_observation)
      .to eq(error: "database has pending migrations: 1", exclusive_lock: false)
  end

  def create_database
    SQLite3::Database.new(layout.database_path.to_s).close
    File.chmod(0o600, layout.database_path)
  end

  def capture_startup_error
    described_class.call(layout:, connection_pool:)
  rescue Kos::State::Error => error
    error
  end

  def failed_startup_observation
    error = capture_startup_error
    lease = Kos::State::ServiceLock.new(layout).acquire_exclusive
    { error: error.message, exclusive_lock: lease.closed? }
  ensure
    lease&.close
  end
end
