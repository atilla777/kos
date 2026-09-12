require "json"
require "open3"
require "rails_helper"
require "tmpdir"
require Rails.root.join("db/migrate/20260912010000_create_publications")

RSpec.describe CreatePublications, :aggregate_failures do
  def root
    File.expand_path("../../..", __dir__)
  end

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

  def migration_result
    Dir.mktmpdir("kos-publication-migration") do |directory|
      env = environment(directory)
      migrate!(env, 20_260_912_000_000)
      seed_repository(env)
      migrate!(env)
      upgraded = runner!(env, <<~'RUBY')
        puts JSON.generate([ActiveRecord::Base.connection.table_exists?(:publications),
          Task.column_names.include?("active_publication_id"), Repository.count,
          ActiveRecord::Base.connection.select_value(<<~SQL).present?])
            SELECT 1 FROM sqlite_master
            WHERE type = 'trigger' AND name = 'publications_observation_update'
          SQL
      RUBY
      command!(env, "ActiveRecord::Base.connection_pool.migration_context.rollback(1)")
      rolled_back = runner!(env, <<~'RUBY')
        puts JSON.generate([ActiveRecord::Base.connection.table_exists?(:publications),
          Task.column_names.include?("active_publication_id"), Repository.count])
      RUBY
      migrate!(env)
      upgraded_again = runner!(env, <<~'RUBY')
        sql = ActiveRecord::Base.connection.select_value(<<~SQL)
          SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'publications'
        SQL
        puts JSON.generate([ActiveRecord::Base.connection.table_exists?(:publications),
          Task.column_names.include?("active_publication_id"), Repository.count,
          sql.include?("publications_candidate_reachable_boolean"),
          Publication.column_names.include?("observation_owner_attempt_id"),
          ActiveRecord::Base.connection.select_value(<<~SQL).present?])
            SELECT 1 FROM sqlite_master
            WHERE type = 'trigger' AND name = 'publications_observation_update'
          SQL
      RUBY
      [ upgraded, rolled_back, upgraded_again ]
    end
  end

  def seed_repository(environment)
    runner!(environment, <<~'RUBY')
      Repository.create!(git_common_dir: "/tmp/publication-migration.git", task_prefix: "KOS",
        trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
      puts JSON.generate(Repository.count)
    RUBY
  end

  it "upgrades and rolls back populated central state without changing existing rows" do
    expect(migration_result)
      .to eq([ [ true, true, 1, true ], [ false, false, 1 ], [ true, true, 1, true, true, true ] ])
  end
end
