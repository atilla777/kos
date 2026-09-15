require "json"
require "open3"
require "rails_helper"
require "tmpdir"
require Rails.root.join("db/migrate/20260915010000_create_publication_preflights")

RSpec.describe CreatePublicationPreflights, :aggregate_failures do
  def root = File.expand_path("../../..", __dir__)

  def environment(directory)
    { "RAILS_ENV" => "development", "KOS_DATABASE_PATH" => File.join(directory, "state.sqlite3") }
  end

  def command!(environment, script)
    output, status = Open3.capture2e(environment, File.join(root, "bin/rails"), "runner", script)
    expect(status).to be_success, output
    output
  end

  def migrate!(environment, target = nil)
    invocation = target ? "context.migrate(#{target})" : "context.migrate"
    command!(environment, "context = ActiveRecord::Base.connection_pool.migration_context; #{invocation}")
  end

  def runner!(environment, script)
    JSON.parse(command!(environment, script).lines.last)
  end

  def migration_summary
    Dir.mktmpdir("kos-preflight-migration") do |directory|
      env = environment(directory)
      migrate!(env, 20_260_915_000_000)
      seed_repository(env)
      migrate!(env)
      upgraded = inspect_schema(env)
      migrate!(env, 20_260_915_000_000)
      rolled_back = inspect_rollback(env)
      migrate!(env)
      [ upgraded, rolled_back, inspect_schema(env) ]
    end
  end

  def seed_repository(environment)
    runner!(environment, <<~'RUBY')
      Repository.create!(git_common_dir: "/tmp/preflight-migration.git", task_prefix: "KOS",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      puts JSON.generate(Repository.count)
    RUBY
  end

  def inspect_schema(environment)
    runner!(environment, <<~'RUBY')
      connection = ActiveRecord::Base.connection
      triggers = connection.select_values(<<~SQL).sort
        SELECT name FROM sqlite_master
        WHERE type = 'trigger' AND tbl_name IN ('publication_preflights', 'workflow_attempts')
          AND name LIKE '%publication_preflight%'
      SQL
      indexes = connection.indexes(:publication_preflights).map(&:name).sort
      sql = connection.select_value(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'publication_preflights'"
      )
      puts JSON.generate([connection.table_exists?(:publication_preflights), Repository.count,
        sql.include?("publication_preflights_lifecycle_shape"), triggers, indexes])
    RUBY
  end

  def inspect_rollback(environment)
    runner!(environment, <<~'RUBY')
      connection = ActiveRecord::Base.connection
      guard = connection.select_value(<<~SQL)
        SELECT 1 FROM sqlite_master
        WHERE type = 'trigger' AND name = 'workflow_attempts_active_publication_preflight_guard'
      SQL
      puts JSON.generate([connection.table_exists?(:publication_preflights), guard.present?, Repository.count])
    RUBY
  end

  def expect_valid_migration(summary)
    upgraded, rolled_back, reapplied = summary
    expect(upgraded.first(3)).to eq([ true, 1, true ])
    expect(upgraded.fetch(3)).to include("publication_preflights_immutable_intent",
      "publication_preflights_consumed_binding", "workflow_attempts_active_publication_preflight_guard")
    expect(upgraded.fetch(4)).to include("index_publication_preflights_one_active_per_task")
    expect(rolled_back).to eq([ false, false, 1 ])
    expect(reapplied).to eq(upgraded)
  end

  it "upgrades, rolls back, and reapplies without changing existing central state" do
    expect_valid_migration(migration_summary)
  end
end
