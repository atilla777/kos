require "test_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class RepositoryIdentityMigrationTest < ActiveSupport::TestCase
  test "backfill and reversal preserve IDs relationships workflow snapshots and execution state" do
    result = run_migration("valid")

    assert_nil result.fetch("error")
    assert_equal [ [ 11, "https://github.com/acme/kos.git" ], [ 12, "git@github.com:acme/other.git" ] ],
      result.fetch("projects")
    assert_equal %w[github.com/acme/kos github.com/acme/other], result.fetch("identities")
    assert_equal expected_task, result.fetch("task")
    assert_equal [ [ 21, 22 ] ], result.fetch("dependencies")
    definition = "{\"steps\":[{\"id\":\"plan\"},{\"id\":\"review\"},{\"id\":\"publish\"}]}"
    assert_equal [ 7, "Snapshot", definition, "2026-09-01 00:00:00" ],
      result.fetch("workflow")
    assert_not_includes result.fetch("down_columns"), "repository_identity"
    assert_equal expected_task, result.fetch("task_after_down")
    assert_equal [ [ 21, 22 ] ], result.fetch("dependencies_after_down")
  end

  test "malformed and colliding legacy remotes atomically roll back schema and data" do
    %w[malformed colliding].each do |scenario|
      result = run_migration(scenario)

      assert result.fetch("error").present?
      assert_not_includes result.fetch("columns"), "repository_identity"
      assert_empty result.fetch("identities")
      assert_equal expected_task, result.fetch("task")
      assert_equal [ [ 21, 22 ] ], result.fetch("dependencies")
    end
  end

  private

  def expected_task
    [ 21, 11, 5, 7, 22, "Active task", "Description", "blocked", "review", "owner-21", 9,
      "2026-10-01 00:00:00", "{\"plan\":{\"outcome\":\"planned\"}}", "Network unavailable", "review", 8,
      "Use retry", "review", 7, "2026-09-02 00:00:00", "2026-09-03 00:00:00" ]
  end

  def run_migration(scenario)
    Dir.mktmpdir("kos-repository-identity-migration") do |directory|
      output, error, status = Open3.capture3(RbConfig.ruby,
        Rails.root.join("test/support/repository_identity_migration_process.rb").to_s,
        File.join(directory, "migration.sqlite3"), scenario)
      assert_predicate status, :success?, error
      JSON.parse(output.lines.last)
    end
  end
end
