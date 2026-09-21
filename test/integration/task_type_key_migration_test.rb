require "test_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class TaskTypeKeyMigrationTest < ActiveSupport::TestCase
  test "assigns deterministic custom keys without inferring built-ins from names" do
    result = run_migration("legacy")

    assert_nil result.fetch("error")
    assert_equal [ [ 11, "Brief", 7, "custom-11" ], [ 12, "Development", 7, "custom-12" ] ], result.fetch("rows")
    assert_equal [ 11, 7 ], result.fetch("task")
    assert_equal false, result.fetch("key_null")
    assert_equal 1, result.fetch("key_indexes")
  end

  test "finishes an already complete deterministic backfill" do
    result = run_migration("complete")

    assert_nil result.fetch("error")
    assert_equal %w[custom-11 custom-12], result.fetch("rows").map(&:last)
    assert_equal false, result.fetch("key_null")
  end

  test "rejects reserved and partially migrated keys without rewriting rows" do
    {
      "reserved" => [ "brief", "custom-12" ],
      "partial" => [ "custom-11", nil ]
    }.each do |scenario, expected_keys|
      result = run_migration(scenario)

      assert_includes result.fetch("error"), "partially migrated or collide"
      assert_equal expected_keys, result.fetch("rows").map(&:last)
      assert_equal [ 11, 7 ], result.fetch("task")
    end
  end

  private

  def run_migration(scenario)
    Dir.mktmpdir("kos-migration") do |directory|
      output, error, status = Open3.capture3(RbConfig.ruby,
        Rails.root.join("test/support/task_type_key_migration_process.rb").to_s,
        File.join(directory, "migration.sqlite3"), scenario)
      assert_predicate status, :success?, error
      return JSON.parse(output.lines.last)
    end
  end
end
