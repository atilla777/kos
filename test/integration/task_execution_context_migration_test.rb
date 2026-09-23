require "test_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class TaskExecutionContextMigrationTest < ActiveSupport::TestCase
  test "adds empty artifacts safely and rolls back without changing domain identity or relationships" do
    Dir.mktmpdir("kos-execution-context-migration") do |directory|
      output, error, status = Open3.capture3(RbConfig.ruby,
        Rails.root.join("test/support/task_execution_context_migration_process.rb").to_s,
        File.join(directory, "migration.sqlite3"))
      assert_predicate status, :success?, error
      result = JSON.parse(output.lines.last)

      assert_equal %w[projects task_dependencies task_types tasks workflows], result.fetch("tables")
      assert_equal({}, result.fetch("artifacts"))
      assert_equal [ [ 14, 11, 13, 12, nil ], [ 15, 11, 13, 12, 14 ] ], result.fetch("ids")
      assert_equal result.fetch("ids"), result.fetch("ids_after_down")
      assert_equal [ [ 16, 15, 14 ] ], result.fetch("dependency")
      assert_equal result.fetch("dependency"), result.fetch("dependency_after_down")
      refute_includes result.fetch("columns_after_down"), "accepted_artifacts"
      refute_includes result.fetch("columns_after_down"), "human_answer"
    end
  end
end
