require "test_helper"

class ProjectsApiTest < ActionDispatch::IntegrationTest
  setup do
    Project.delete_all
  end

  test "creates, reads, updates, lists, and deletes a project" do
    post "/api/v1/projects", params: {
      project: { name: "KOS", repository: "github.com/atilla777/kos" }
    }, as: :json

    assert_response :created
    project = response.parsed_body.dig("data", "project")

    get "/api/v1/projects/#{project.fetch("id")}", as: :json
    assert_response :ok
    assert_equal "KOS", response.parsed_body.dig("data", "project", "name")

    patch "/api/v1/projects/#{project.fetch("id")}", params: {
      project: { name: "KOS Tracker" }
    }, as: :json
    assert_response :ok
    assert_equal "KOS Tracker", response.parsed_body.dig("data", "project", "name")

    get "/api/v1/projects", params: { repository: "github.com/atilla777/kos" }
    assert_response :ok
    assert_equal [ project.fetch("id") ], response.parsed_body.dig("data", "projects").pluck("id")

    delete "/api/v1/projects/#{project.fetch("id")}", as: :json
    assert_response :ok
    assert_not Project.exists?(project.fetch("id"))
  end

  test "returns machine-readable validation and not-found errors" do
    post "/api/v1/projects", params: {
      project: { name: "KOS", repository: "not a repository" }
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body.dig("error", "code")

    get "/api/v1/projects/999999", as: :json
    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")

    get "/api/v1/unknown", as: :json
    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")
  end

  test "returns a machine-readable error for malformed JSON" do
    post "/api/v1/projects",
      params: "{",
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request
    assert_equal "invalid_request", response.parsed_body.dig("error", "code")
  end

  test "enforces repository uniqueness in the database and API" do
    Project.create!(name: "KOS", repository: "github.com/atilla777/kos")

    post "/api/v1/projects", params: {
      project: { name: "Duplicate", repository: "github.com/atilla777/kos" }
    }, as: :json

    assert_response :conflict
    assert_equal "repository_taken", response.parsed_body.dig("error", "code")
    assert_equal 1, Project.count
  end

  test "paginates by id up to the maximum limit" do
    3.times do |index|
      Project.create!(name: "Project #{index}", repository: "example.com/team/project-#{index}")
    end

    get "/api/v1/projects", params: { limit: 2 }
    first_page = response.parsed_body.fetch("data")

    assert_response :ok
    assert_equal 2, first_page.fetch("projects").length
    assert first_page.dig("pagination", "next_after_id")

    get "/api/v1/projects", params: {
      limit: 100,
      after_id: first_page.dig("pagination", "next_after_id")
    }

    assert_response :ok
    assert_equal 100, response.parsed_body.dig("data", "pagination", "limit")
    assert_equal 1, response.parsed_body.dig("data", "projects").length
  end

  test "rejects invalid pagination" do
    get "/api/v1/projects", params: { limit: 101 }

    assert_response :bad_request
    assert_equal "invalid_request", response.parsed_body.dig("error", "code")

    get "/api/v1/projects", params: { after_id: "invalid" }

    assert_response :bad_request
    assert_equal "invalid_request", response.parsed_body.dig("error", "code")
  end
end
