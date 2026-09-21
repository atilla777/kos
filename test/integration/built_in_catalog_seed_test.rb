require "test_helper"
require "json"
require "open3"
require "tmpdir"

class BuiltInCatalogSeedTest < ActiveSupport::TestCase
  test "a fresh prepared database receives the idempotent built-in catalog" do
    Dir.mktmpdir("kos-seed") do |data_home|
      environment = {
        "RAILS_ENV" => "development",
        "KOS_API_TOKEN" => "seed-test-token",
        "KOS_DATA_HOME" => data_home,
        "DATABASE_URL" => nil
      }

      run_rails(environment, "db:prepare")
      first = catalog_counts(environment)
      run_rails(environment, "db:seed")
      second = catalog_counts(environment)

      assert_equal({ "keys" => %w[brief development fix], "task_types" => 3, "workflows" => 3 }, first)
      assert_equal first, second
    end
  end

  private

  def catalog_counts(environment)
    script = <<~RUBY
      puts({
        keys: TaskType.order(:key).pluck(:key),
        task_types: TaskType.count,
        workflows: Workflow.count
      }.to_json)
    RUBY
    JSON.parse(run_rails(environment, "runner", script).lines.last)
  end

  def run_rails(environment, *arguments)
    output, error, status = Open3.capture3(environment, Rails.root.join("bin/rails").to_s, *arguments)
    assert_predicate status, :success?, error
    output
  end
end
