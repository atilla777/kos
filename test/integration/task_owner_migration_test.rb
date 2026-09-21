require "test_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class TaskOwnerMigrationTest < ActiveSupport::TestCase
  test "adds a partial unique owner index to valid legacy data" do
    result = run_migration("valid")

    assert_nil result.fetch("error")
    assert_equal 1, result.fetch("owner_indexes")
  end

  test "rejects duplicate and blank legacy owners with an actionable error" do
    %w[duplicate blank].each do |scenario|
      result = run_migration(scenario)

      assert_includes result.fetch("error"), "blank or duplicate values"
      assert_equal 0, result.fetch("owner_indexes")
    end
  end

  private

  def run_migration(scenario)
    Dir.mktmpdir("kos-owner-migration") do |directory|
      output, error, status = Open3.capture3(RbConfig.ruby,
        Rails.root.join("test/support/task_owner_migration_process.rb").to_s,
        File.join(directory, "migration.sqlite3"), scenario)
      assert_predicate status, :success?, error
      return JSON.parse(output.lines.last)
    end
  end
end
