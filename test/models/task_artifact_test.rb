require "test_helper"

class TaskArtifactTest < ActiveSupport::TestCase
  test "artifact keys are unique within a task and versions advance on update" do
    project = Project.create!(name: "KOS", repository: "github.com/atilla777/kos")
    task = project.tasks.create!(kind: "feature", title: "Artifacts", description: "Store results.")
    artifact = task.task_artifacts.create!(key: "specification", content: "# Version 1")

    assert_equal 0, artifact.lock_version
    artifact.update!(content: "# Version 2")
    assert_equal 1, artifact.lock_version
    assert_raises(ActiveRecord::RecordInvalid) do
      task.task_artifacts.create!(key: artifact.key, content: "Duplicate")
    end
  end

  test "destroying a task deletes its artifacts" do
    project = Project.create!(name: "KOS", repository: "github.com/atilla777/kos")
    task = project.tasks.create!(kind: "feature", title: "Artifacts", description: "Store results.")
    artifact = task.task_artifacts.create!(key: "report", content: "# Report")

    task.destroy!

    assert_not TaskArtifact.exists?(artifact.id)
  end
end
