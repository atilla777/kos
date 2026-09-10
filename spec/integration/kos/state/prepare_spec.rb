require "rails_helper"
require "open3"
require "timeout"

RSpec.describe Kos::State::Prepare, type: :integration do
  let(:temporary_directory) { Pathname.new(Dir.mktmpdir("kos-production-state")) }
  let(:state_root) { temporary_directory.join("state") }

  after { FileUtils.remove_entry(temporary_directory) }

  it "prepares an absent database idempotently without creating a backup" do
    results = [ run_rails("kos:state:prepare"), run_rails("kos:state:prepare") ]

    expect(
      statuses: results.pluck(:success), database: state_root.join("kos.sqlite3").exist?,
      mode: state_root.join("kos.sqlite3").stat.mode & 0o777, backups: state_root.join("backups").children
    ).to eq(statuses: [ true, true ], database: true, mode: 0o600, backups: [])
  end

  it "refuses server startup before preparation without creating a database" do
    result = run_rails("runner", "Rails.application.load_server")

    expect(result.slice(:success, :database, :error)).to eq(
      success: false, database: false, error: "production database does not exist; run kos:state:prepare"
    )
  end

  it "accepts an exactly compatible schema" do
    run_rails("kos:state:prepare")

    expect(run_rails("runner", "Rails.application.load_server").fetch(:success)).to be(true)
  end

  it "rejects an unknown schema version" do
    run_rails("kos:state:prepare")
    insert_unknown_version

    expect(run_rails("runner", "Rails.application.load_server").fetch(:error))
      .to eq("database contains migration versions unknown to this release: 20260908000000")
  end

  it "cannot prepare state while a server process holds the shared lock" do
    run_rails("kos:state:prepare")

    with_running_server do
      expect(run_rails("kos:state:prepare").fetch(:error))
        .to eq("service is running or state preparation is already active")
    end
  end

  def insert_unknown_version
    database = SQLite3::Database.new(state_root.join("kos.sqlite3").to_s)
    database.execute("INSERT INTO schema_migrations(version) VALUES ('20260908000000')")
    database.close
  end

  def run_rails(*arguments)
    _, stderr, status = Open3.capture3(production_environment, "bin/rails", *arguments, chdir: Rails.root.to_s)
    {
      success: status.success?, database: state_root.join("kos.sqlite3").exist?,
      error: state_error(stderr)
    }
  end

  def state_error(stderr)
    line = stderr.lines.find { |candidate| candidate.include?("Kos::State::Error") }
    return unless line

    line[/:\s(.+) \(Kos::State::Error\)$/, 1] || line[/Kos::State::Error:\s(.+)$/, 1]
  end

  def with_running_server
    input, output, thread = Open3.popen2e(
      production_environment, "bin/rails", "runner",
      "Rails.application.load_server; puts 'state-lock-ready'; STDOUT.flush; sleep 30", chdir: Rails.root.to_s
    )
    Timeout.timeout(10) { output.each_line.find { |line| line.include?("state-lock-ready") } || raise("server failed") }
    yield
  ensure
    input&.close
    Process.kill("TERM", thread.pid) if thread&.alive?
    thread&.join
  end

  def production_environment
    {
      "RAILS_ENV" => "production", "KOS_STATE_ROOT" => state_root.to_s,
      "SECRET_KEY_BASE_DUMMY" => "1", "HOME" => ENV.fetch("HOME")
    }
  end
end
