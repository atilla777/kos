require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe WorkflowCatalog::PublishDraft, :aggregate_failures do
  include WorkflowCatalogHelpers

  before { quick_fix_task_type }

  it "creates and then completely replaces a draft under optimistic locking" do
    draft = import_workflow
    changed = workflow_definition(version: "1.1.0")

    expect { import_workflow(changed, expected_lock_version: draft.lock_version) }
      .to change { draft.reload.lock_version }.from(1).to(2)
    expect(draft.definition).to eq(changed)
  end

  it "stores a graph-invalid but schema-valid draft" do
    definition = workflow_definition
    definition.fetch("transitions").first["to"] = "missing"

    expect(import_workflow(definition)).to be_persisted
  end

  it "does not publish duplicate template or requirement identities" do
    import_duplicate_template

    expect { described_class.call(workflow_id: "quick-fix", expected_lock_version: 1) }
      .to raise_error(WorkflowCatalog::Error) { |error| expect(error.code).to eq("workflow_definition_invalid") }
  end

  it "rejects stale draft writes" do
    import_workflow

    expect { import_workflow(workflow_definition(version: "1.1.0"), expected_lock_version: 0) }
      .to raise_error(WorkflowCatalog::Error, /stale/)
  end

  it "publishes the complete normalized graph atomically" do
    workflow = publish_workflow
    exported = WorkflowCatalog::CanonicalDefinition.from_record(workflow.reload)

    expect(published_attributes(workflow, exported)).to eq(expected_published_attributes(exported))
  end

  it "returns the existing version for the same semantic content" do
    first = publish_workflow

    expect(described_class.call(workflow_id: "quick-fix", expected_lock_version: 1)).to eq(first)
    expect(WorkflowVersion.count).to eq(1)
  end

  it "rejects semantic version reuse with different canonical content" do
    publish_then_change_draft

    expect { described_class.call(workflow_id: "quick-fix", expected_lock_version: 2) }
      .to raise_error(WorkflowCatalog::Error) { |error| expect(error.code).to eq("workflow_version_conflict") }
  end

  it "rolls back every publication row after a child insertion failure" do
    import_workflow
    allow(described_class).to receive(:create_transition).and_raise("injected failure")

    expect { described_class.call(workflow_id: "quick-fix", expected_lock_version: 1) }
      .to raise_error("injected failure")
    expect([ WorkflowVersion.count, WorkflowState.count, ArtifactTemplate.count ]).to eq([ 0, 0, 0 ])
  end

  it "rejects publication of an invalid draft without creating rows" do
    import_invalid_draft

    expect { described_class.call(workflow_id: "quick-fix", expected_lock_version: 1) }
      .to raise_error(WorkflowCatalog::Error) { |error| expect(error.code).to eq("workflow_definition_invalid") }
    expect(WorkflowVersion.count).to be_zero
  end

  it "normalizes semantically unordered arrays before digesting" do
    expect(WorkflowCatalog::CanonicalDefinition.digest(reordered_definition))
      .to eq(WorkflowCatalog::CanonicalDefinition.digest(workflow_definition))
  end

  it "activates a published version under optimistic locking" do
    workflow = publish_workflow

    task_type = WorkflowCatalog::ActivateVersion.call(task_type_id: "quick-fix", workflow_version_id: workflow.id,
      expected_lock_version: 0)
    expect([ task_type.current_workflow_version_id, task_type.lock_version ]).to eq([ workflow.id, 1 ])
  end

  it "rejects activation of an unpublished version" do
    workflow = publish_workflow
    unpublished = create_unpublished_version(workflow.content_digest)

    expect { activate(unpublished.id, 0) }
      .to raise_error(WorkflowCatalog::Error) { |error| expect(error.code).to eq("workflow_version_not_found") }
  end

  it "rejects stale activation" do
    workflow = publish_workflow
    quick_fix_task_type.update!(current_workflow_version: workflow)

    expect { activate(workflow.id, 0) }
      .to raise_error(WorkflowCatalog::Error) { |error| expect(error.code).to eq("stale_lock_version") }
  end

  it "does not change the workflow version pinned by an existing task" do
    ids = activated_versions_for_existing_task

    expect([ ids.all? { |id| id.match?(/\A[0-9a-f-]{36}\z/) }, ids.uniq.length ]).to eq([ true, 2 ])
  end

  def publish_then_change_draft
    publish_workflow
    changed = workflow_definition
    changed.fetch("statuses").first["instruction"] = "# Changed"
    import_workflow(changed, expected_lock_version: 1)
  end

  def import_invalid_draft
    definition = workflow_definition
    definition.fetch("transitions").first["to"] = "missing"
    import_workflow(definition)
  end

  def reordered_definition
    value = workflow_definition
    value.fetch("statuses").reverse_each { |status| reverse_status_arrays(status) }
    value.fetch("statuses").reverse!
    value.fetch("transitions").reverse_each { |transition| transition.fetch("conditions").reverse! }
    value.fetch("transitions").reverse!
    value
  end

  def reverse_status_arrays(status)
    status.fetch("allowed_repository_effects").reverse!
    status.fetch("required_artifacts").reverse_each { |requirement| requirement.fetch("allowed_states").reverse! }
    status.fetch("required_artifacts").reverse!
  end

  def create_unpublished_version(digest)
    WorkflowVersion.create!(task_type: quick_fix_task_type, workflow_id: "quick-fix", version: "2.0.0",
      content_digest: digest)
  end

  def import_duplicate_template
    definition = workflow_definition
    templates = definition.fetch("statuses").first.fetch("artifact_templates")
    templates << deep_copy(templates.first)
    import_workflow(definition)
  end

  def activate(workflow_version_id, expected_lock_version)
    WorkflowCatalog::ActivateVersion.call(task_type_id: "quick-fix", workflow_version_id: workflow_version_id,
      expected_lock_version: expected_lock_version)
  end

  def published_attributes(workflow, exported)
    [ workflow.published_at.present?, workflow.content_digest, workflow.workflow_states.count, exported ]
  end

  def expected_published_attributes(exported)
    [ true, WorkflowCatalog::CanonicalDefinition.digest(exported), workflow_definition.fetch("statuses").length + 1,
      WorkflowCatalog::CanonicalDefinition.normalize(workflow_definition) ]
  end

  def activated_versions_for_existing_task
    first = publish_workflow
    activate(first.id, 0)
    task = create_task_pinned_to(first)
    draft = import_workflow(workflow_definition(version: "2.0.0"), expected_lock_version: 1)
    second = described_class.call(workflow_id: "quick-fix", expected_lock_version: draft.lock_version)
    activate(second.id, 1)
    [ task.reload.workflow_version_id, quick_fix_task_type.reload.current_workflow_version_id ]
  end

  def create_task_pinned_to(workflow)
    repository = Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
    Task.create!(repository: repository, sequence: 1, title: "Pinned task", task_type: quick_fix_task_type,
      workflow_version: workflow, workflow_state: workflow.workflow_states.find_by!(initial: true))
  end
end
