require "test_helper"
require "open3"

class CliTest < ActiveSupport::TestCase
  test "prints help" do
    output, _error, status = Open3.capture3(Rails.root.join("bin/kos").to_s, "--help")

    assert_predicate status, :success?
    assert_includes output, "Usage: kos [options]"
  end
end
