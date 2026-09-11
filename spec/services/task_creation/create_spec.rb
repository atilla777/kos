require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe TaskCreation::Create, :aggregate_failures do
  include WorkflowCatalogHelpers

  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end

  def activate(version)
    quick_fix_task_type.update!(current_workflow_version: version)
  end

  def create_task(title: "Repair timeout")
    described_class.call(repository: repository, title: title, task_type_name: "quick-fix")
  end

  def publish_second_version
    draft = import_workflow(workflow_definition(version: "2.0.0"), expected_lock_version: 1)
    WorkflowCatalog::PublishDraft.call(workflow_id: "quick-fix", expected_lock_version: draft.lock_version)
  end

  def pinning_summary(task)
    [ task.reload.workflow_version, task.workflow_state.workflow_version,
      quick_fix_task_type.reload.current_workflow_version ]
  end

  def task_and_versions
    first = publish_workflow
    activate(first)
    task = create_task
    second = publish_second_version
    activate(second)
    [ task, first, second ]
  end

  it "allocates a public number and pins the active version and initial state" do
    version = publish_workflow
    activate(version)

    task = create_task

    expect([ task.number, task.workflow_version, task.workflow_state.identifier, task.lock_version,
      repository.reload.next_task_sequence ]).to eq([ "KOS-000001", version, "implementation-planning", 0, 2 ])
  end

  it "keeps an existing task pinned after another version is activated" do
    task, first, second = task_and_versions

    expect(pinning_summary(task)).to eq([ first, first, second ])
  end

  it "allocates sequence one independently in separate repositories" do
    activate(publish_workflow)
    other = Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "APP",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/other.git", base_ref: "refs/heads/main")

    expect([ create_task.number, described_class.call(repository: other, title: "Other", task_type_name: "quick-fix").number ])
      .to eq(%w[KOS-000001 APP-000001])
  end

  it "does not allocate when the task type has no active workflow" do
    quick_fix_task_type

    expect { create_task }.to raise_error(OperationError) { |error| expect(error.code).to eq("task_type_unavailable") }
    expect([ Task.count, repository.reload.next_task_sequence ]).to eq([ 0, 1 ])
  end

  it "uses the final sequence and then reports explicit exhaustion" do
    activate(publish_workflow)
    repository.update!(next_task_sequence: 999_999)

    expect(create_task.number).to eq("KOS-999999")
    expect { create_task }.to raise_error(OperationError) { |error| expect(error.code).to eq("task_number_exhausted") }
    expect([ Task.count, repository.reload.next_task_sequence ]).to eq([ 1, 1_000_000 ])
  end

  it "rolls back allocation when task persistence fails" do
    activate(publish_workflow)

    expect { create_task(title: " ") }.to raise_error(ActiveRecord::RecordInvalid)
    expect([ Task.count, repository.reload.next_task_sequence ]).to eq([ 0, 1 ])
  end
end
