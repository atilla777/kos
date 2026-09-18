require "test_helper"

class ReadinessTest < ActionDispatch::IntegrationTest
  test "reports that the application is ready" do
    get rails_health_check_path

    assert_response :success
  end
end
