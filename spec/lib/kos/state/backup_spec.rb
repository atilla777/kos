require "rails_helper"

RSpec.describe Kos::State::Backup do
  let(:temporary_directory) { Pathname.new(Dir.mktmpdir("kos-backup")) }
  let(:layout) do
    root = temporary_directory.join("state")
    Kos::State::Layout.new(root_path: root, database_path: root.join("kos.sqlite3")).prepare!
  end
  let(:source) { SQLite3::Database.new(layout.database_path.to_s) }
  let(:source_connection) { Data.define(:raw_connection).new(source) }
  let(:clock) { Data.define(:now).new(Time.utc(2026, 9, 10, 12, 30, 0, 123_456)) }

  after do
    source.close unless source.closed?
    FileUtils.remove_entry(temporary_directory)
  end

  it "captures committed WAL content and publishes a verified manifest" do
    prepare_source

    backup_path = described_class.new(layout, source_connection:, clock:).create!(schema_version: schema_version)

    expect(backup_observation(backup_path)).to eq(expected_observation(backup_path))
  end

  def prepare_source
    source.execute("PRAGMA journal_mode = WAL")
    source.execute("CREATE TABLE records (value TEXT NOT NULL)")
    source.execute("INSERT INTO records VALUES ('durable')")
    File.chmod(0o600, layout.database_path)
  end

  def backup_observation(backup_path)
    backup = SQLite3::Database.new(backup_path.to_s, readonly: true)
    manifest = JSON.parse(File.read("#{backup_path}.json"))
    {
      rows: backup.execute("SELECT value FROM records"), manifest:, backup_mode: backup_path.stat.mode & 0o777,
      manifest_mode: Pathname.new("#{backup_path}.json").stat.mode & 0o777
    }
  ensure
    backup&.close
  end

  def expected_observation(backup_path)
    {
      rows: [ [ "durable" ] ],
      manifest: {
        "backup" => backup_path.basename.to_s, "source_schema_version" => schema_version,
        "created_at" => "2026-09-10T12:30:00.123456Z", "byte_size" => File.size(backup_path),
        "sha256" => Digest::SHA256.file(backup_path).hexdigest
      },
      backup_mode: 0o600,
      manifest_mode: 0o600
    }
  end

  def schema_version
    20_260_909_000_000
  end
end
