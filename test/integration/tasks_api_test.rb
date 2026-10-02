require "test_helper"

class TasksApiTest < ActionDispatch::IntegrationTest
  REPOSITORY = "github.com/atilla777/kos"

  test "state view gives availability and paginated own versions without loading dependency context" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    workflow = workflow_for(project)
    task = project.tasks.create!(workflow: workflow, kind: "task", title: "Target", description: "Private text")
    12.times do |index|
      blocker = project.tasks.create!(workflow: workflow, kind: "task", title: "Blocker #{index}", description: "Dependency")
      blocker.task_artifacts.create!(key: "report", content: "Blocker secret #{index}")
      task.task_dependencies.create!(project: project, blocking_task: blocker)
    end
    first, second = %w[first second].map { |key| task.task_artifacts.create!(key: key, content: "Own secret") }

    get "/api/v1/tasks/#{task.id}", params: { project: REPOSITORY, view: "state", context_limit: 1 }
    assert_response :ok
    state = response.parsed_body.dig("data", "task")
    assert_equal %w[artifacts availability current_step id pagination status title], state.keys.sort
    assert_equal [ task.id, "Target", "planned", 0 ], state.values_at("id", "title", "status", "current_step")
    assert_equal false, state.dig("availability", "available")
    assert_equal [ { "key" => "first", "lock_version" => first.lock_version } ], state.fetch("artifacts")
    assert_equal({ "limit" => 1, "complete" => false, "after_parameter" => "artifact_after_id",
      "next_after_id" => first.id }, state.fetch("pagination"))
    assert_operator response.body.bytesize, :<, begin
      get "/api/v1/tasks/#{task.id}", params: { project: REPOSITORY, view: "brief", context_limit: 1 }
      response.body.bytesize
    end
    get "/api/v1/tasks/#{task.id}", params: { project: REPOSITORY, view: "state", context_limit: 1,
      artifact_after_id: first.id }
    assert_equal [ { "key" => "second", "lock_version" => second.lock_version } ],
      response.parsed_body.dig("data", "task", "artifacts")
    assert_equal true, response.parsed_body.dig("data", "task", "pagination", "complete")
    assert_not_includes response.body, "secret"
  end

  test "brief task context retains paginated sources and versions without long texts" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    workflow = workflow_for(project)
    blocker = project.tasks.create!(workflow: workflow, kind: "task", title: "Blocker", description: "Blocker secret")
    blocker.task_artifacts.create!(key: "source", content: "Blocker document")
    task = project.tasks.create!(workflow: workflow, kind: "task", title: "Target", description: "Task secret")
    task.task_dependencies.create!(project: project, blocking_task: blocker)
    first, second = %w[first second].map { |key| task.task_artifacts.create!(key: key, content: "Secret #{key}") }

    get "/api/v1/tasks/#{task.id}", params: { project: REPOSITORY, view: "brief", context_limit: 1 }
    assert_response :ok
    short = response.parsed_body.dig("data", "task")
    assert_equal "planned", short.fetch("status")
    assert_equal 0, short.fetch("current_step")
    assert_equal blocker.id, short.dig("blocked_by", 0, "id")
    assert_equal first.id, short.dig("artifacts", 0, "id")
    assert_equal "first", short.dig("artifacts", 0, "key")
    assert_equal 0, short.dig("artifacts", 0, "lock_version")
    assert_equal blocker.id, short.dig("dependency_artifacts", 0, "source", "task_id")
    assert_equal "source", short.dig("dependency_artifacts", 0, "source", "key")
    assert_equal first.id, short.dig("pagination", "artifacts", "next_after_id")
    assert_not short.key?("description")
    assert_not short.key?("work_summary")
    assert_not_includes response.body, "Secret"
    assert_not_includes response.body, "Blocker document"

    get "/api/v1/tasks/#{task.id}", params: { project: REPOSITORY, view: "brief", context_limit: 1,
      artifact_after_id: first.id }
    assert_equal second.id, response.parsed_body.dig("data", "task", "artifacts", 0, "id")
    get "/api/v1/tasks/#{task.id}", params: { project: REPOSITORY }
    assert_equal "Task secret", response.parsed_body.dig("data", "task", "description")
    assert_equal "Blocker document", response.parsed_body.dig("data", "task", "dependency_artifacts", 0, "content")
  end

  test "creates, lists, shows, updates, and deletes a task in its project" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    post "/api/v1/tasks", params: {
      project: REPOSITORY,
      workflow_id: workflow_for(project).id,
      kind: "feature",
      title: "Task CRUD",
      description: "Implement task CRUD."
    }, as: :json

    assert_response :created
    task = response.parsed_body.dig("data", "task")
    assert_equal "planned", task.fetch("status")
    assert_nil task.fetch("session_id")
    assert_nil task.fetch("claimed_at")
    assert Project.exists?(repository: REPOSITORY)

    get "/api/v1/tasks", params: { project: REPOSITORY }
    assert_response :ok
    brief = response.parsed_body.dig("data", "tasks").sole
    assert_equal task.fetch("id"), brief.fetch("id")
    assert_not brief.key?("description")
    assert_not brief.key?("work_summary")

    get "/api/v1/tasks/#{task.fetch('id')}", params: { project: REPOSITORY }
    assert_response :ok
    assert_equal "Implement task CRUD.", response.parsed_body.dig("data", "task", "description")

    patch "/api/v1/tasks/#{task.fetch('id')}", params: {
      project: REPOSITORY,
      title: "Complete task CRUD",
      work_summary: "CRUD is implemented."
    }, as: :json
    assert_response :ok
    assert_equal "Complete task CRUD", response.parsed_body.dig("data", "task", "title")
    assert_equal "CRUD is implemented.", response.parsed_body.dig("data", "task", "work_summary")

    delete "/api/v1/tasks/#{task.fetch('id')}", params: { project: REPOSITORY }, as: :json
    assert_response :ok
    assert_not Task.exists?(task.fetch("id"))
  end

  test "requires task fields and rolls back an automatically created project" do
    post "/api/v1/tasks", params: {
      project: "github.com/atilla777/new-project",
      kind: "feature",
      title: "Missing description"
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body.dig("error", "code")
    assert_not Project.exists?(repository: "github.com/atilla777/new-project")
    assert_equal 0, Task.count
  end

  test "reuses an existing project when creating tasks" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)

    2.times do |index|
      post "/api/v1/tasks", params: {
        project: "GitHub.com/Atilla777/KOS.git",
        workflow_id: workflow_for(project).id,
        kind: "feature",
        title: "Task #{index}",
        description: "Implement it."
      }, as: :json
      assert_response :created
    end

    assert_equal 1, Project.count
    assert_equal [ project.id ], Task.distinct.pluck(:project_id)
    assert_equal 2, Task.count
  end

  test "assigns, changes, and removes a group within the task project" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    group = project.task_groups.create!(kind: "epic", title: "Groups", description: "Implement groups.")
    replacement = project.task_groups.create!(kind: "epic", title: "Replacement", description: "Replacement group.")

    post "/api/v1/tasks", params: {
      project: REPOSITORY,
      workflow_id: workflow_for(project).id,
      task_group_id: group.id,
      kind: "feature",
      title: "Grouped task",
      description: "Implement it."
    }, as: :json
    assert_response :created
    task_id = response.parsed_body.dig("data", "task", "id")
    assert_equal group.id, response.parsed_body.dig("data", "task", "task_group_id")

    patch "/api/v1/tasks/#{task_id}", params: { project: REPOSITORY, task_group_id: replacement.id }, as: :json
    assert_response :ok
    assert_equal replacement.id, Task.find(task_id).task_group_id

    patch "/api/v1/tasks/#{task_id}", params: { project: REPOSITORY, task_group_id: nil }, as: :json
    assert_response :ok
    assert_nil Task.find(task_id).task_group_id
  end

  test "rejects a group from another project" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    other = Project.create!(name: "Other", repository: "github.com/atilla777/other")
    group = other.task_groups.create!(kind: "epic", title: "Other", description: "Other group.")

    post "/api/v1/tasks", params: {
      project: REPOSITORY,
      workflow_id: workflow_for(project).id,
      task_group_id: group.id,
      kind: "feature",
      title: "Wrong group",
      description: "Must fail."
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body.dig("error", "code")
  end

  test "read operations do not create projects" do
    get "/api/v1/tasks", params: { project: "github.com/atilla777/missing" }

    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")
    assert_equal 0, Project.count
  end

  test "all id operations reject a different project scope" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    other = Project.create!(name: "Other", repository: "github.com/atilla777/other")
    task = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Task CRUD", description: "Implement it.")

    get "/api/v1/tasks/#{task.id}", params: { project: other.repository }
    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")

    patch "/api/v1/tasks/#{task.id}", params: { project: other.repository, title: "Wrong" }, as: :json
    assert_response :not_found

    delete "/api/v1/tasks/#{task.id}", params: { project: other.repository }, as: :json
    assert_response :not_found
    assert Task.exists?(task.id)
  end

  test "create and update ignore protected fields" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    post "/api/v1/tasks", params: {
      project: REPOSITORY,
      workflow_id: workflow_for(project).id,
      kind: "feature",
      title: "Task CRUD",
      description: "Implement it.",
      status: "done",
      session_id: "session",
      claim_id: "claim",
      claimed_at: Time.current,
      lease_expires_at: 1.hour.from_now,
      current_step: 77,
      project_id: 999_999
    }, as: :json
    task_id = response.parsed_body.dig("data", "task", "id")

    assert_response :created
    task = Task.find(task_id)
    assert_equal "planned", task.status
    assert_nil task.session_id
    assert_nil task.claim_id
    assert_equal 0, task.current_step
    assert_equal Project.find_by!(repository: REPOSITORY).id, task.project_id

    patch "/api/v1/tasks/#{task.id}", params: {
      project: REPOSITORY,
      status: "done",
      session_id: "session",
      claim_id: "claim",
      claimed_at: Time.current,
      lease_expires_at: 1.hour.from_now,
      current_step: 99,
      project_id: 999_999
    }, as: :json

    assert_response :ok
    task.reload
    assert_equal "planned", task.status
    assert_equal 0, task.current_step
    assert_nil task.session_id
    assert_nil task.claim_id
    assert_equal Project.find_by!(repository: REPOSITORY).id, task.project_id
  end

  test "paginates task lists within the project" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    other = Project.create!(name: "Other", repository: "github.com/atilla777/other")
    3.times do |index|
      project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Task #{index}", description: "Implement it.")
    end
    other.tasks.create!(workflow: workflow_for(other), kind: "feature", title: "Other", description: "Implement it.")

    get "/api/v1/tasks", params: { project: REPOSITORY, limit: 2 }
    first_page = response.parsed_body.fetch("data")

    assert_response :ok
    assert_equal 2, first_page.fetch("tasks").length
    assert first_page.dig("pagination", "next_after_id")

    get "/api/v1/tasks", params: {
      project: REPOSITORY,
      limit: 100,
      after_id: first_page.dig("pagination", "next_after_id")
    }

    assert_response :ok
    assert_equal 1, response.parsed_body.dig("data", "tasks").length
    assert_nil response.parsed_body.dig("data", "pagination", "next_after_id")
  end

  test "rejects missing project and invalid pagination" do
    get "/api/v1/tasks"
    assert_response :bad_request
    assert_equal "invalid_request", response.parsed_body.dig("error", "code")

    Project.create!(name: "KOS", repository: REPOSITORY)
    get "/api/v1/tasks", params: { project: REPOSITORY, limit: 101 }
    assert_response :bad_request

    get "/api/v1/tasks", params: { project: REPOSITORY, after_id: "invalid" }
    assert_response :bad_request

    get "/api/v1/tasks", params: { project: "https://github.com/atilla777/kos" }
    assert_response :bad_request
    assert_equal "invalid_request", response.parsed_body.dig("error", "code")
  end

  test "project deletion returns a safe conflict while tasks exist" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Task CRUD", description: "Implement it.")

    delete "/api/v1/projects/#{project.id}", as: :json

    assert_response :conflict
    assert_equal "project_not_empty", response.parsed_body.dig("error", "code")
    assert Project.exists?(project.id)
  end

  test "creates a grouped task with blockers atomically" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    group = project.task_groups.create!(kind: "epic", title: "Graph", description: "Build the graph.")
    blocker = project.tasks.create!(workflow: workflow_for(project), kind: "decomposition", title: "Plan", description: "Plan the work.")

    post "/api/v1/tasks", params: {
      project: REPOSITORY,
      task_group_id: group.id,
      workflow_id: workflow_for(project).id,
      kind: "feature",
      title: "Implement",
      description: "Implement the plan.",
      blocked_by_ids: [ blocker.id ]
    }, as: :json

    assert_response :created
    task = response.parsed_body.dig("data", "task")
    assert_equal group.id, task.fetch("task_group_id")
    assert_equal [ blocker.id ], task.fetch("blocked_by_ids")
    assert_equal [ blocker.id ], Task.find(task.fetch("id")).blocking_task_ids
  end

  test "rolls back task creation when any blocker is invalid" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    blocker = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Blocker", description: "Block work.")

    post "/api/v1/tasks", params: {
      project: REPOSITORY,
      workflow_id: workflow_for(project).id,
      kind: "feature",
      title: "Invalid graph",
      description: "Must roll back.",
      blocked_by_ids: [ blocker.id, 999_999 ]
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body.dig("error", "code")
    assert_equal [ blocker.id ], project.tasks.pluck(:id)
    assert_equal 0, TaskDependency.count
  end

  test "replaces the complete blocker set and rejects invalid graph changes atomically" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    other_project = Project.create!(name: "Other", repository: "github.com/atilla777/other")
    first = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "First", description: "First.")
    second = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Second", description: "Second.")
    target = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Target", description: "Target.")
    foreign = other_project.tasks.create!(workflow: workflow_for(other_project), kind: "feature", title: "Foreign", description: "Foreign.")
    target.replace_blockers!([ first.id ])

    patch "/api/v1/tasks/#{target.id}", params: {
      project: REPOSITORY,
      blocked_by_ids: [ second.id ]
    }, as: :json
    assert_response :ok
    assert_equal [ second.id ], response.parsed_body.dig("data", "task", "blocked_by_ids")

    [ [ target.id ], [ second.id, second.id ], [ foreign.id ] ].each do |invalid_ids|
      patch "/api/v1/tasks/#{target.id}", params: {
        project: REPOSITORY,
        blocked_by_ids: invalid_ids
      }, as: :json
      assert_response :unprocessable_entity
      assert_equal [ second.id ], target.reload.blocking_task_ids
    end

    patch "/api/v1/tasks/#{target.id}", params: { project: REPOSITORY, blocked_by_ids: [] }, as: :json
    assert_response :ok
    assert_empty target.reload.blocking_task_ids

    target.update_columns(
      status: "in_progress", session_id: "session", claim_id: "claim",
      claimed_at: Time.current, lease_expires_at: 1.hour.from_now
    )
    patch "/api/v1/tasks/#{target.id}", params: {
      project: REPOSITORY,
      blocked_by_ids: [ first.id ]
    }, as: :json
    assert_response :unprocessable_entity
    assert_empty target.reload.blocking_task_ids
  end

  test "rejects cycles without changing the existing graph" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    first = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "First", description: "First.")
    second = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Second", description: "Second.")
    second.replace_blockers!([ first.id ])

    patch "/api/v1/tasks/#{first.id}", params: {
      project: REPOSITORY,
      blocked_by_ids: [ second.id ]
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "dependency_cycle", response.parsed_body.dig("error", "code")
    assert_empty first.reload.blocking_task_ids
    assert_equal [ first.id ], second.reload.blocking_task_ids
  end

  test "rolls back task fields when blocker replacement fails" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    blocker = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Blocker", description: "Blocker.")
    target = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Original", description: "Original.")
    target.replace_blockers!([ blocker.id ])

    patch "/api/v1/tasks/#{target.id}", params: {
      project: REPOSITORY,
      title: "Must roll back",
      blocked_by_ids: [ target.id ]
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "Original", target.reload.title
    assert_equal [ blocker.id ], target.blocking_task_ids
  end

  test "ready is computed by the server with filters ordering and pagination" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    group = project.task_groups.create!(kind: "epic", title: "Ready", description: "Ready work.")
    blocker = project.tasks.create!(workflow: workflow_for(project), kind: "decomposition", title: "Plan", description: "Plan.")
    blocked = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Blocked", description: "Blocked.", task_group: group)
    blocked.replace_blockers!([ blocker.id ])
    first = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "First ready", description: "Ready.", task_group: group)
    second = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Second ready", description: "Ready.", task_group: group)
    project.tasks.create!(workflow: workflow_for(project), kind: "bug", title: "Different kind", description: "Ready.", task_group: group)
    active = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Active", description: "Claimed.", task_group: group)
    expired = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Expired", description: "Claim expired.", task_group: group)
    active.update_columns(
      status: "in_progress", session_id: "active-session", claim_id: "active-claim",
      claimed_at: Time.current, lease_expires_at: 1.hour.from_now
    )
    expired.update_columns(
      status: "in_progress", session_id: "expired-session", claim_id: "expired-claim",
      claimed_at: 2.hours.ago, lease_expires_at: 1.hour.ago
    )

    get "/api/v1/tasks/ready", params: {
      project: REPOSITORY,
      kind: "feature",
      task_group_id: group.id,
      limit: 1
    }

    assert_response :ok
    page = response.parsed_body.fetch("data")
    assert_equal [ first.id ], page.fetch("tasks").map { |task| task.fetch("id") }
    assert_equal first.id, page.dig("pagination", "next_after_id")

    get "/api/v1/tasks/ready", params: {
      project: REPOSITORY,
      kind: "feature",
      task_group_id: group.id,
      limit: 1,
      after_id: page.dig("pagination", "next_after_id")
    }

    assert_response :ok
    assert_equal [ second.id ], response.parsed_body.dig("data", "tasks").map { |task| task.fetch("id") }

    blocker.update_columns(status: "done")
    get "/api/v1/tasks/ready", params: { project: REPOSITORY, kind: "feature", task_group_id: group.id }
    assert_response :ok
    ready_ids = response.parsed_body.dig("data", "tasks").map { |task| task.fetch("id") }
    assert_includes ready_ids, blocked.id
    assert_includes ready_ids, expired.id
    assert_not_includes ready_ids, active.id
    expired_result = response.parsed_body.dig("data", "tasks").find { |task| task.fetch("id") == expired.id }
    assert_equal "in_progress", expired_result.fetch("status")
    assert_equal true, expired_result.fetch("lease_expired")
    assert TaskDependency.exists?(task_id: blocked.id, blocking_task_id: blocker.id)
  end

  test "a blocker cannot be deleted while a dependent task exists" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    blocker = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Blocker", description: "Blocker.")
    dependent = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Dependent", description: "Dependent.")
    dependent.replace_blockers!([ blocker.id ])

    delete "/api/v1/tasks/#{blocker.id}", params: { project: REPOSITORY }, as: :json

    assert_response :conflict
    assert_equal "task_has_dependents", response.parsed_body.dig("error", "code")
    assert Task.exists?(blocker.id)
    assert TaskDependency.exists?(task_id: dependent.id, blocking_task_id: blocker.id)
  end

  test "claims a task with a server-issued lease and does not expose the claim in ordinary show" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    task = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Claim", description: "Claim it.")
    before_claim = Time.current

    post "/api/v1/tasks/#{task.id}/claim", params: {
      project: REPOSITORY,
      session_id: "agent-1"
    }, as: :json

    assert_response :ok
    data = response.parsed_body.fetch("data")
    claimed = data.fetch("task")
    assert_equal "created", data.fetch("claim_status")
    assert_equal "in_progress", claimed.fetch("status")
    assert_equal "agent-1", claimed.fetch("session_id")
    assert_match(/\A[0-9a-f]{64}\z/, claimed.fetch("claim_id"))
    assert_in_delta 1.hour, Time.iso8601(claimed.fetch("lease_expires_at")) - Time.iso8601(claimed.fetch("claimed_at")), 0.001
    assert_operator Time.iso8601(claimed.fetch("claimed_at")), :>=, before_claim - 1.second

    get "/api/v1/tasks/#{task.id}", params: { project: REPOSITORY }
    assert_response :ok
    assert_not response.parsed_body.dig("data", "task").key?("claim_id")
  end

  test "show current and claim return the same complete task context" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    group = project.task_groups.create!(kind: "epic", title: "Context", description: "Provide context.")
    blocker = project.tasks.create!(
      workflow: workflow_for(project),
      kind: "decomposition", title: "Plan", description: "Plan it.", work_summary: "Plan complete."
    )
    blocker.update_columns(status: "done")
    blocker_artifact = blocker.task_artifacts.create!(key: "plan", content: "# Plan")
    task = project.tasks.create!(
      workflow: workflow_for(project),
      kind: "feature", title: "Implement", description: "Use the plan.",
      work_summary: "Not started.", task_group: group
    )
    task.replace_blockers!([ blocker.id ])
    own_artifact = task.task_artifacts.create!(key: "notes", content: "# Notes")
    dependent = project.tasks.create!(workflow: workflow_for(project), kind: "test", title: "Verify", description: "Verify it.")
    dependent.replace_blockers!([ task.id ])

    get "/api/v1/tasks/#{task.id}", params: { project: REPOSITORY }
    assert_response :ok
    shown = response.parsed_body.dig("data", "task")
    assert_equal "Use the plan.", shown.fetch("description")
    assert_equal "Not started.", shown.fetch("work_summary")
    assert_equal group.id, shown.dig("task_group", "id")
    assert_equal [ own_artifact.id ], shown.fetch("artifacts").map { |artifact| artifact.fetch("id") }
    assert_equal [ blocker.id ], shown.fetch("blocked_by").map { |item| item.fetch("id") }
    assert_equal [ dependent.id ], shown.fetch("blocks").map { |item| item.fetch("id") }
    dependency_result = shown.fetch("dependency_artifacts").sole
    assert_equal "# Plan", dependency_result.fetch("content")
    assert_equal blocker.id, dependency_result.dig("source", "task_id")
    assert_equal blocker_artifact.key, dependency_result.dig("source", "key")
    assert_equal blocker_artifact.lock_version, dependency_result.dig("source", "lock_version")
    assert_equal({ "available" => true, "reasons" => [] }, shown.fetch("availability"))
    assert_not shown.key?("claim_id")

    post "/api/v1/tasks/#{task.id}/claim", params: {
      project: REPOSITORY, session_id: "agent-1"
    }, as: :json
    assert_response :ok
    claimed = response.parsed_body.dig("data", "task")
    assert_equal shown.keys.sort, claimed.keys.reject { |key| key == "claim_id" }.sort
    assert claimed.fetch("claim_id")

    lease_expires_at = task.reload.lease_expires_at
    updated_at = task.updated_at
    get "/api/v1/tasks/current", params: { project: REPOSITORY, session_id: "agent-1" }
    assert_response :ok
    current = response.parsed_body.dig("data", "task")
    assert_equal claimed.keys.sort, current.keys.sort
    assert_equal claimed.fetch("claim_id"), current.fetch("claim_id")
    assert_equal lease_expires_at, task.reload.lease_expires_at
    assert_equal updated_at, task.updated_at
  end

  test "task context marks incomplete collections and continues each with its cursor" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    blockers = 2.times.map do |index|
      blocker = project.tasks.create!(workflow: workflow_for(project), kind: "task", title: "Blocker #{index}", description: "Block.")
      blocker.update_columns(status: "done")
      blocker.task_artifacts.create!(key: "result-#{index}", content: "Result #{index}")
      blocker
    end
    task = project.tasks.create!(workflow: workflow_for(project), kind: "task", title: "Context", description: "Read context.")
    task.replace_blockers!(blockers.map(&:id))
    2.times { |index| task.task_artifacts.create!(key: "own-#{index}", content: "Own #{index}") }
    dependents = 2.times.map do |index|
      dependent = project.tasks.create!(workflow: workflow_for(project), kind: "task", title: "Dependent #{index}", description: "Wait.")
      dependent.replace_blockers!([ task.id ])
      dependent
    end

    get "/api/v1/tasks/#{task.id}", params: { project: REPOSITORY, context_limit: 1 }
    assert_response :ok
    first = response.parsed_body.dig("data", "task")
    %w[artifacts blocked_by dependency_artifacts blocks].each do |collection|
      page = first.dig("pagination", collection)
      assert_equal false, page.fetch("complete")
      assert page.fetch("next_after_id")
      assert page.fetch("after_parameter")
      assert_equal 1, first.fetch(collection).length
    end

    get "/api/v1/tasks/#{task.id}", params: {
      project: REPOSITORY,
      context_limit: 1,
      artifact_after_id: first.dig("pagination", "artifacts", "next_after_id"),
      blocked_by_after_id: first.dig("pagination", "blocked_by", "next_after_id"),
      dependency_artifact_after_id: first.dig("pagination", "dependency_artifacts", "next_after_id"),
      blocks_after_id: first.dig("pagination", "blocks", "next_after_id")
    }
    assert_response :ok
    second = response.parsed_body.dig("data", "task")
    %w[artifacts blocked_by dependency_artifacts blocks].each do |collection|
      assert_equal true, second.dig("pagination", collection, "complete")
      assert_nil second.dig("pagination", collection, "next_after_id")
      assert_equal 1, second.fetch(collection).length
    end
    assert_equal blockers.last.id, second.fetch("blocked_by").sole.fetch("id")
    assert_equal dependents.last.id, second.fetch("blocks").sole.fetch("id")
  end

  test "task context explains why work is unavailable" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    blocker = project.tasks.create!(workflow: workflow_for(project), kind: "task", title: "Blocker", description: "Block.")
    task = project.tasks.create!(workflow: workflow_for(project), kind: "task", title: "Waiting", description: "Wait.")
    task.replace_blockers!([ blocker.id ])

    get "/api/v1/tasks/#{task.id}", params: { project: REPOSITORY }
    reasons = response.parsed_body.dig("data", "task", "availability", "reasons")
    assert_equal false, response.parsed_body.dig("data", "task", "availability", "available")
    assert_equal "unfinished_blockers", reasons.sole.fetch("code")
    assert_equal 1, reasons.sole.fetch("count")
  end

  test "repeated claim and current return the existing claim without extending it" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    task = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Claim", description: "Claim it.")

    post "/api/v1/tasks/#{task.id}/claim", params: { project: REPOSITORY, session_id: "agent-1" }, as: :json
    original = response.parsed_body.dig("data", "task")

    post "/api/v1/tasks/#{task.id}/claim", params: { project: REPOSITORY, session_id: "agent-1" }, as: :json
    assert_response :ok
    assert_equal "existing", response.parsed_body.dig("data", "claim_status")
    assert_equal original.fetch("claim_id"), response.parsed_body.dig("data", "task", "claim_id")
    assert_equal original.fetch("lease_expires_at"), response.parsed_body.dig("data", "task", "lease_expires_at")

    get "/api/v1/tasks/current", params: { project: REPOSITORY, session_id: "agent-1" }
    assert_response :ok
    assert_equal original.fetch("claim_id"), response.parsed_body.dig("data", "task", "claim_id")
    assert_equal original.fetch("lease_expires_at"), response.parsed_body.dig("data", "task", "lease_expires_at")

    get "/api/v1/tasks/current", params: { project: REPOSITORY, session_id: "agent-2" }
    assert_response :ok
    assert_nil response.parsed_body.dig("data", "task")
    assert_equal "no_current_task", response.parsed_body.dig("data", "reason")
  end

  test "claim enforces blockers ownership and terminal state" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    blocker = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Blocker", description: "Block.")
    blocked = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Blocked", description: "Wait.")
    blocked.replace_blockers!([ blocker.id ])
    other = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Other", description: "Other.")
    done = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Done", description: "Done.")
    done.update_columns(status: "done")

    post "/api/v1/tasks/#{blocked.id}/claim", params: { project: REPOSITORY, session_id: "agent-1" }, as: :json
    assert_response :conflict
    assert_equal "task_blocked", response.parsed_body.dig("error", "code")

    post "/api/v1/tasks/#{blocker.id}/claim", params: { project: REPOSITORY, session_id: "agent-1" }, as: :json
    assert_response :ok

    post "/api/v1/tasks/#{other.id}/claim", params: { project: REPOSITORY, session_id: "agent-1" }, as: :json
    assert_response :conflict
    assert_equal "session_has_active_task", response.parsed_body.dig("error", "code")

    post "/api/v1/tasks/#{blocker.id}/claim", params: { project: REPOSITORY, session_id: "agent-2" }, as: :json
    assert_response :conflict
    assert_equal "task_already_claimed", response.parsed_body.dig("error", "code")

    post "/api/v1/tasks/#{done.id}/claim", params: { project: REPOSITORY, session_id: "agent-2" }, as: :json
    assert_response :conflict
    assert_equal "invalid_transition", response.parsed_body.dig("error", "code")
  end

  test "claim-next atomically selects filtered work or returns a normal empty result" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    project.tasks.create!(workflow: workflow_for(project), kind: "bug", title: "Bug", description: "Bug.")
    first = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "First", description: "First.")
    project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Second", description: "Second.")

    post "/api/v1/tasks/claim-next", params: {
      project: REPOSITORY,
      session_id: "agent-1",
      kind: "feature"
    }, as: :json
    assert_response :ok
    assert_equal first.id, response.parsed_body.dig("data", "task", "id")
    assert_equal "created", response.parsed_body.dig("data", "claim_status")

    post "/api/v1/tasks/claim-next", params: {
      project: REPOSITORY,
      session_id: "agent-1",
      kind: "missing"
    }, as: :json
    assert_response :ok
    assert_equal first.id, response.parsed_body.dig("data", "task", "id")
    assert_equal "existing", response.parsed_body.dig("data", "claim_status")

    project.tasks.where.not(id: first.id).update_all(
      status: "done", session_id: nil, claim_id: nil, claimed_at: nil, lease_expires_at: nil
    )
    post "/api/v1/tasks/claim-next", params: { project: REPOSITORY, session_id: "agent-2" }, as: :json
    assert_response :ok
    assert_nil response.parsed_body.dig("data", "task")
    assert_equal "no_ready_tasks", response.parsed_body.dig("data", "reason")
  end

  test "expired task receives a fresh claim id" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    task = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Expired", description: "Expired.")
    task.update_columns(
      status: "in_progress",
      session_id: "old-agent",
      claim_id: "old-claim",
      claimed_at: 2.hours.ago,
      lease_expires_at: 1.hour.ago
    )

    post "/api/v1/tasks/#{task.id}/claim", params: { project: REPOSITORY, session_id: "new-agent" }, as: :json

    assert_response :ok
    assert_equal "created", response.parsed_body.dig("data", "claim_status")
    assert_not_equal "old-claim", response.parsed_body.dig("data", "task", "claim_id")
    assert_equal "new-agent", task.reload.session_id
  end

  test "claim operations require a nonblank string session" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    task = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Claim", description: "Claim.")

    [ nil, "", "   ", 123 ].each do |session|
      post "/api/v1/tasks/#{task.id}/claim", params: { project: REPOSITORY, session_id: session }, as: :json
      assert_response :bad_request
      assert_equal "invalid_request", response.parsed_body.dig("error", "code")
    end
  end

  test "renews an active claim without changing its identity or start time" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    task = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Renew", description: "Renew it.")
    task.update_columns(
      status: "in_progress", session_id: "agent-1", claim_id: "current-claim",
      claimed_at: 10.minutes.ago, lease_expires_at: 1.minute.from_now
    )
    original_claimed_at = task.claimed_at
    before_renew = Time.current

    post "/api/v1/tasks/#{task.id}/renew", params: {
      project: REPOSITORY, claim_id: "current-claim"
    }, as: :json

    assert_response :ok
    task.reload
    assert_equal "current-claim", task.claim_id
    assert_equal original_claimed_at, task.claimed_at
    assert_in_delta 1.hour, task.lease_expires_at - before_renew, 2.seconds
    assert_equal task.lease_expires_at.iso8601(3), response.parsed_body.dig("data", "task", "lease_expires_at")
  end

  test "only the active claim can update in-progress task text" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    task = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Progress", description: "Track it.", work_summary: "Original")
    task.update_columns(
      status: "in_progress", session_id: "agent-1", claim_id: "current-claim",
      claimed_at: Time.current, lease_expires_at: 1.hour.from_now
    )

    patch "/api/v1/tasks/#{task.id}", params: {
      project: REPOSITORY, claim_id: "stale-claim", work_summary: "Stale"
    }, as: :json
    assert_response :conflict
    assert_equal "claim_mismatch", response.parsed_body.dig("error", "code")
    assert_equal "Original", task.reload.work_summary

    patch "/api/v1/tasks/#{task.id}", params: {
      project: REPOSITORY, claim_id: "current-claim", title: "Updated", work_summary: "Current"
    }, as: :json
    assert_response :ok
    assert_equal "Updated", task.reload.title
    assert_equal "Current", task.work_summary

    patch "/api/v1/tasks/#{task.id}", params: {
      project: REPOSITORY, claim_id: "current-claim", kind: "bug"
    }, as: :json
    assert_response :unprocessable_entity
    assert_equal "feature", task.reload.kind

    task.update_columns(lease_expires_at: Time.current)
    patch "/api/v1/tasks/#{task.id}", params: {
      project: REPOSITORY, claim_id: "current-claim", work_summary: "Too late"
    }, as: :json
    assert_response :conflict
    assert_equal "lease_expired", response.parsed_body.dig("error", "code")
    assert_equal "Current", task.reload.work_summary
  end

  test "blockers cannot be removed after dependent work starts" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    blocker = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Blocker", description: "Produce a result.")
    dependent = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Dependent", description: "Use the result.")
    dependent.replace_blockers!([ blocker.id ])
    blocker.update_columns(status: "done")

    post "/api/v1/tasks/#{dependent.id}/claim", params: {
      project: REPOSITORY, session_id: "agent-1"
    }, as: :json
    claim_id = response.parsed_body.dig("data", "task", "claim_id")

    patch "/api/v1/tasks/#{dependent.id}", params: {
      project: REPOSITORY, claim_id: claim_id, blocked_by_ids: []
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body.dig("error", "code")
    assert_equal [ blocker.id ], dependent.reload.blocking_task_ids
  end

  test "release and complete atomically save summaries and clear ownership" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    task = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Finish", description: "Finish it.")

    post "/api/v1/tasks/#{task.id}/claim", params: { project: REPOSITORY, session_id: "agent-1" }, as: :json
    first_claim = response.parsed_body.dig("data", "task", "claim_id")
    post "/api/v1/tasks/#{task.id}/release", params: {
      project: REPOSITORY, claim_id: first_claim, work_summary: "Paused safely"
    }, as: :json

    assert_response :ok
    task.reload
    assert_equal "planned", task.status
    assert_equal "Paused safely", task.work_summary
    assert_nil task.claim_id
    assert_nil task.lease_expires_at

    post "/api/v1/tasks/#{task.id}/claim", params: { project: REPOSITORY, session_id: "agent-2" }, as: :json
    second_claim = response.parsed_body.dig("data", "task", "claim_id")
    post "/api/v1/tasks/#{task.id}/complete", params: {
      project: REPOSITORY, claim_id: second_claim, work_summary: "Finished"
    }, as: :json

    assert_response :ok
    task.reload
    assert_equal "done", task.status
    assert_equal "Finished", task.work_summary
    assert_nil task.session_id
    assert_nil task.claimed_at
  end

  test "an expired owner cannot mutate a task after a fresh claim" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    task = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Takeover", description: "Take it.", work_summary: "Saved")
    task.update_columns(
      status: "in_progress", session_id: "old-agent", claim_id: "old-claim",
      claimed_at: 2.hours.ago, lease_expires_at: 1.hour.ago
    )

    post "/api/v1/tasks/#{task.id}/claim", params: { project: REPOSITORY, session_id: "new-agent" }, as: :json
    new_claim = response.parsed_body.dig("data", "task", "claim_id")

    %w[renew release complete].each do |operation|
      post "/api/v1/tasks/#{task.id}/#{operation}", params: {
        project: REPOSITORY, claim_id: "old-claim", work_summary: "Corrupted"
      }, as: :json
      assert_response :conflict
      assert_equal "claim_mismatch", response.parsed_body.dig("error", "code")
    end
    patch "/api/v1/tasks/#{task.id}", params: {
      project: REPOSITORY, claim_id: "old-claim", work_summary: "Corrupted"
    }, as: :json
    assert_response :conflict

    task.reload
    assert_equal new_claim, task.claim_id
    assert_equal "Saved", task.work_summary
  end

  test "an expired claim cannot renew release or complete at the lease boundary" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    task = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Expired", description: "Expire it.", work_summary: "Safe")
    task.update_columns(
      status: "in_progress", session_id: "agent-1", claim_id: "expired-claim",
      claimed_at: 30.minutes.ago, lease_expires_at: Time.current
    )

    %w[renew release complete].each do |operation|
      post "/api/v1/tasks/#{task.id}/#{operation}", params: {
        project: REPOSITORY, claim_id: "expired-claim", work_summary: "Too late"
      }, as: :json
      assert_response :conflict
      assert_equal "lease_expired", response.parsed_body.dig("error", "code")
    end

    task.reload
    assert_equal "in_progress", task.status
    assert_equal "expired-claim", task.claim_id
    assert_equal "Safe", task.work_summary
  end

  test "reopen is explicit and rejects started dependent work" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    completed = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Result", description: "Produce it.")
    dependent = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Consumer", description: "Use it.")
    dependent.replace_blockers!([ completed.id ])
    completed.update_columns(status: "done")

    post "/api/v1/tasks/#{completed.id}/reopen", params: { project: REPOSITORY }, as: :json
    assert_response :ok
    assert_equal "planned", completed.reload.status

    completed.update_columns(status: "done")
    dependent.update_columns(
      status: "in_progress", session_id: "agent-1", claim_id: "dependent-claim",
      claimed_at: Time.current, lease_expires_at: 1.hour.from_now
    )
    post "/api/v1/tasks/#{completed.id}/reopen", params: { project: REPOSITORY }, as: :json
    assert_response :conflict
    assert_equal "task_has_started_dependents", response.parsed_body.dig("error", "code")
    assert_equal "done", completed.reload.status

    patch "/api/v1/tasks/#{completed.id}", params: { project: REPOSITORY, title: "Silent edit" }, as: :json
    assert_response :conflict
    assert_equal "invalid_transition", response.parsed_body.dig("error", "code")
  end

  test "active claims prevent deletion but expired claims do not" do
    project = Project.create!(name: "KOS", repository: REPOSITORY)
    task = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Delete", description: "Delete it.")
    task.update_columns(
      status: "in_progress", session_id: "agent-1", claim_id: "claim",
      claimed_at: Time.current, lease_expires_at: 1.hour.from_now
    )

    delete "/api/v1/tasks/#{task.id}", params: { project: REPOSITORY }, as: :json
    assert_response :conflict
    assert_equal "task_already_claimed", response.parsed_body.dig("error", "code")
    assert Task.exists?(task.id)

    task.update_columns(lease_expires_at: Time.current)
    delete "/api/v1/tasks/#{task.id}", params: { project: REPOSITORY }, as: :json
    assert_response :ok
    assert_not Task.exists?(task.id)
  end
end
