require "test_helper"

class TaskGroupsApiTest < ActionDispatch::IntegrationTest
  REPOSITORY = "github.com/atilla777/kos"

  test "creates, lists, shows, updates, and deletes an empty group" do
    post "/api/v1/task-groups", params: {
      project: REPOSITORY,
      kind: "epic",
      title: "Task groups",
      description: "Implement task groups."
    }, as: :json

    assert_response :created
    group = response.parsed_body.dig("data", "task_group")
    assert_equal false, group.fetch("completed")
    assert_equal 0, group.fetch("tasks_total")
    assert Project.exists?(repository: REPOSITORY)

    get "/api/v1/task-groups", params: { project: REPOSITORY }
    assert_response :ok
    brief = response.parsed_body.dig("data", "task_groups").sole
    assert_equal group.fetch("id"), brief.fetch("id")
    assert_not brief.key?("description")

    get "/api/v1/task-groups/#{group.fetch('id')}", params: { project: REPOSITORY }
    assert_response :ok
    assert_equal "Implement task groups.", response.parsed_body.dig("data", "task_group", "description")

    patch "/api/v1/task-groups/#{group.fetch('id')}", params: {
      project: REPOSITORY,
      title: "Updated groups"
    }, as: :json
    assert_response :ok
    assert_equal "Updated groups", response.parsed_body.dig("data", "task_group", "title")

    delete "/api/v1/task-groups/#{group.fetch('id')}", params: { project: REPOSITORY }, as: :json
    assert_response :ok
    assert_not TaskGroup.exists?(group.fetch("id"))
  end

  test "reports current progress and rejects deletion of a nonempty group" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    group = project.task_groups.create!(kind: "epic", title: "Task groups", description: "Implement groups.")
    done = project.tasks.create!(workflow: workflow_for(project), task_group: group, kind: "feature", title: "Done", description: "Done task.")
    project.tasks.create!(workflow: workflow_for(project), task_group: group, kind: "feature", title: "Planned", description: "Planned task.")
    done.update!(status: "done")

    get "/api/v1/task-groups/#{group.id}", params: { project: REPOSITORY }
    progress = response.parsed_body.dig("data", "task_group")
    assert_equal false, progress.fetch("completed")
    assert_equal 2, progress.fetch("tasks_total")
    assert_equal 1, progress.fetch("tasks_done")
    assert_equal 0, progress.fetch("tasks_in_progress")

    delete "/api/v1/task-groups/#{group.id}", params: { project: REPOSITORY }, as: :json
    assert_response :conflict
    assert_equal "group_not_empty", response.parsed_body.dig("error", "code")
  end

  test "rejects invalid kinds and rolls back an automatically created project" do
    post "/api/v1/task-groups", params: {
      project: REPOSITORY,
      kind: "initiative",
      title: "Invalid",
      description: "Invalid kind."
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body.dig("error", "code")
    assert_not Project.exists?(repository: REPOSITORY)
  end

  test "all id operations reject a different project scope" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    other = Project.create!(name: "Other", repository: "github.com/atilla777/other")
    group = project.task_groups.create!(kind: "epic", title: "Task groups", description: "Implement groups.")

    get "/api/v1/task-groups/#{group.id}", params: { project: other.repository }
    assert_response :not_found

    patch "/api/v1/task-groups/#{group.id}", params: { project: other.repository, title: "Wrong" }, as: :json
    assert_response :not_found

    delete "/api/v1/task-groups/#{group.id}", params: { project: other.repository }, as: :json
    assert_response :not_found
    assert TaskGroup.exists?(group.id)
  end

  test "paginates groups within the project" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    other = Project.create!(name: "Other", repository: "github.com/atilla777/other")
    3.times { |index| project.task_groups.create!(kind: "epic", title: "Group #{index}", description: "Group.") }
    other.task_groups.create!(kind: "epic", title: "Other", description: "Other group.")

    get "/api/v1/task-groups", params: { project: REPOSITORY, limit: 2 }
    first_page = response.parsed_body.fetch("data")
    assert_equal 2, first_page.fetch("task_groups").length

    get "/api/v1/task-groups", params: {
      project: REPOSITORY,
      limit: 100,
      after_id: first_page.dig("pagination", "next_after_id")
    }
    assert_equal 1, response.parsed_body.dig("data", "task_groups").length
    assert_nil response.parsed_body.dig("data", "pagination", "next_after_id")
  end
end
