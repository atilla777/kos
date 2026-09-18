require "test_helper"

class AuthenticationProbeController < ApplicationController
  def show
    render json: { authenticated: true }
  end
end

class ApplicationControllerTest < ActionController::TestCase
  tests AuthenticationProbeController

  setup do
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw { get "probe" => "authentication_probe#show" }
  end

  test "rejects a request without authorization" do
    get :show

    assert_response :unauthorized
    assert_equal "application/json", response.media_type
    assert_equal({ "error" => "unauthorized" }, response.parsed_body)
  end

  test "rejects a malformed authorization scheme" do
    request.headers["Authorization"] = "Basic test-api-token"

    get :show

    assert_response :unauthorized
  end

  test "rejects an incorrect bearer token" do
    request.headers["Authorization"] = "Bearer incorrect-token"

    get :show

    assert_response :unauthorized
  end

  test "accepts the configured bearer token" do
    request.headers["Authorization"] = "Bearer test-api-token"

    get :show

    assert_response :success
    assert_equal({ "authenticated" => true }, response.parsed_body)
  end
end
