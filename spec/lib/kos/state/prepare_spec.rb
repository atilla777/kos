require "rails_helper"

RSpec.describe Kos::State::Prepare do
  let(:temporary_directory) { Pathname.new(Dir.mktmpdir("kos-prepare")) }
  let(:layout) do
    root = temporary_directory.join("state")
    Kos::State::Layout.new(root_path: root, database_path: root.join("kos.sqlite3")).prepare!
  end
  let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::SQLite3Adapter, raw_connection: nil) }
  let(:migration_context) { instance_double(ActiveRecord::MigrationContext, migrations:) }
  let(:connection_pool) do
    instance_double(
      ActiveRecord::ConnectionAdapters::ConnectionPool,
      lease_connection: connection, migration_context:, release_connection: true
    )
  end

  after { FileUtils.remove_entry(temporary_directory) }

  it "creates a backup before migrating an existing database" do
    events = prepare_pending_operation

    described_class.new(layout:, connection_pool:).call

    expect(events).to eq(%i[backup migrate])
  end

  it "does not migrate when backup verification fails" do
    events = prepare_pending_operation(backup_failure: Kos::State::Error.new("backup invalid"))

    error = run_prepare

    expect(error: error.message, events:).to eq(error: "backup invalid", events: [ :backup ])
  end

  it "reports the applied version after migration failure" do
    events = prepare_pending_operation(migration_failure: StandardError.new("migration failed"))

    error = run_prepare

    expect(error: error.message, events:)
      .to eq(error: "state preparation failed at schema version 1: migration failed", events: %i[backup migrate])
  end

  def prepare_pending_operation(backup_failure: nil, migration_failure: nil)
    create_database
    events = []
    final_versions = migration_failure ? [ 1 ] : [ 1, 2 ]
    allow(migration_context).to receive(:get_all_versions).and_return([ 1 ], final_versions)
    stub_backup(events, backup_failure)
    allow(migration_context).to receive(:migrate) { events << :migrate; raise migration_failure if migration_failure }
    events
  end

  def stub_backup(events, failure)
    backup = instance_double(Kos::State::Backup)
    allow(backup).to receive(:create!) { events << :backup; raise failure if failure }
    allow(Kos::State::Backup).to receive(:new).with(layout, source_connection: connection).and_return(backup)
  end

  def run_prepare
    described_class.new(layout:, connection_pool:).call
  rescue Kos::State::Error => error
    error
  end

  def migrations
    migration_class = Data.define(:version)
    [ migration_class.new(1), migration_class.new(2) ]
  end

  def create_database
    SQLite3::Database.new(layout.database_path.to_s).close
    File.chmod(0o600, layout.database_path)
  end
end
