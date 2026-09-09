require "rails_helper"

RSpec.describe Repository, type: :model do
  def create_task_type(suffix = SecureRandom.hex(4))
    TaskType.create!(id: "type-#{suffix}", name: "type-#{suffix}", workflow_id: "workflow-#{suffix}")
  end

  def create_repository(prefix: "KOS")
    Repository.create!(
      git_common_dir: "/tmp/#{SecureRandom.uuid}.git",
      task_prefix: prefix,
      trusted_remote: "origin",
      trusted_remote_url: "file:///tmp/remote.git",
      base_ref: "refs/heads/main"
    )
  end

  def create_workflow(task_type: create_task_type, version: "1.0.0")
    workflow_version = create_workflow_version(task_type, version)
    source = create_source_state(workflow_version)
    terminal = WorkflowState.create!(workflow_version:, identifier: "completed", terminal: true)
    children = create_workflow_children(workflow_version, source, terminal)
    workflow_version.update!(published_at: Time.current)

    { task_type:, version: workflow_version, source:, terminal:, **children }
  end

  def create_workflow_version(task_type, version)
    WorkflowVersion.create!(
      task_type:,
      workflow_id: task_type.workflow_id,
      version:,
      content_digest: "sha256:#{"a" * 64}"
    )
  end

  def create_source_state(workflow_version)
    WorkflowState.create!(
      workflow_version:,
      identifier: "planning",
      initial: true,
      execution_mode: "subagent",
      instruction: "Plan the change.",
      worktree_policy: "required",
      repository_changes_policy: "allowed"
    )
  end

  def create_workflow_children(workflow_version, source, terminal)
    template = ArtifactTemplate.create!(
      workflow_state: source,
      identifier: "plan",
      media_type: "text/markdown; charset=utf-8",
      content: "# Plan"
    )
    effect = WorkflowStateEffect.create!(workflow_state: source, effect: "commit")
    requirement = ArtifactRequirement.create!(
      workflow_state: source,
      artifact_type: "document",
      cardinality: "one",
      subject: "task"
    )
    requirement_state = ArtifactRequirementState.create!(artifact_requirement: requirement, state: "produced")
    transition = WorkflowTransition.create!(workflow_version:, from_state: source, to_state: terminal)
    condition = WorkflowTransitionCondition.create!(
      workflow_transition: transition,
      position: 0,
      condition_type: "artifact-present",
      artifact_type: "document"
    )

    { template:, effect:, requirement:, requirement_state:, transition:, condition: }
  end

  def create_task(workflow = create_workflow, sequence: 12)
    Task.create!(
      repository: create_repository,
      sequence:,
      title: "Persist task state",
      task_type: workflow.fetch(:task_type),
      workflow_version: workflow.fetch(:version),
      workflow_state: workflow.fetch(:source)
    )
  end

  def stale_draft_pair
    task_type = create_task_type
    draft = WorkflowDraft.create!(
      task_type:,
      workflow_id: task_type.workflow_id,
      definition: { "workflow_id" => task_type.workflow_id }
    )
    [ draft, WorkflowDraft.find(draft.id) ]
  end

  def mismatched_task
    task_type = create_task_type
    first = create_workflow(task_type:)
    second = create_workflow(task_type:, version: "2.0.0")
    Task.new(
      repository: create_repository,
      sequence: 1,
      title: "Mismatched state",
      task_type:,
      workflow_version: first.fetch(:version),
      workflow_state: second.fetch(:source)
    )
  end

  def unpublished_task
    task_type = create_task_type
    workflow_version = create_workflow_version(task_type, "1.0.0")
    state = create_source_state(workflow_version)
    Task.new(
      repository: create_repository,
      sequence: 1,
      title: "Unpublished workflow",
      task_type:,
      workflow_version:,
      workflow_state: state
    )
  end

  def transition_source_and_other_version
    task_type = create_task_type
    workflow_version = create_workflow_version(task_type, "1.0.0")
    source = create_source_state(workflow_version)
    terminal = WorkflowState.create!(workflow_version:, identifier: "completed", terminal: true)
    WorkflowTransition.create!(workflow_version:, from_state: source, to_state: terminal)

    [ source, create_workflow_version(task_type, "2.0.0") ]
  end

  def repository_with_invalid_uuid
    attributes = create_repository.attributes.merge(
      "id" => "x" * 36,
      "git_common_dir" => "/tmp/#{SecureRandom.uuid}.git",
      "task_prefix" => "BADID"
    )
    described_class.new(attributes.except("created_at", "updated_at"))
  end

  def task_with_sequence(sequence)
    workflow = create_workflow
    Task.new(
      repository: create_repository,
      sequence:,
      title: "Sequence boundary",
      task_type: workflow.fetch(:task_type),
      workflow_version: workflow.fetch(:version),
      workflow_state: workflow.fetch(:source)
    )
  end

  it "derives a repository-scoped public task number" do
    expect(create_task.number).to eq("KOS-000012")
  end

  it "persists workflow associations" do
    task = create_task

    expect(task.workflow_version.workflow_states.map(&:identifier)).to contain_exactly("planning", "completed")
  end

  it "assigns UUID primary keys" do
    expect(create_task.id).to match(/\A[0-9a-f-]{36}\z/)
  end

  it "enforces UUID syntax in SQLite" do
    expect { repository_with_invalid_uuid.save!(validate: false) }
      .to raise_error(ActiveRecord::StatementInvalid, /repositories_id_format/)
  end

  it "uses optimistic locking for workflow drafts" do
    draft, stale_copy = stale_draft_pair
    draft.update!(definition: { "workflow_id" => draft.workflow_id, "version" => "1.0.0" })

    expect { stale_copy.update!(definition: { "workflow_id" => "stale" }) }
      .to raise_error(ActiveRecord::StaleObjectError)
  end

  it "round-trips workflow draft JSON" do
    draft, = stale_draft_pair

    expect(draft.reload.definition).to eq("workflow_id" => draft.workflow_id)
  end

  it "enforces repository prefix syntax in SQLite" do
    attributes = create_repository.attributes.except("id", "task_prefix")

    expect { described_class.new(attributes.merge(task_prefix: "bad")).save!(validate: false) }
      .to raise_error(ActiveRecord::StatementInvalid, /repositories_task_prefix_format/)
  end

  it "enforces repository uniqueness in SQLite" do
    attributes = create_repository.attributes.except("id", "created_at", "updated_at")

    expect { described_class.new(attributes).save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows repository sequence allocation" do
    repository = create_repository

    expect { repository.update!(next_task_sequence: 2) }.to change(repository, :next_task_sequence).from(1).to(2)
  end

  it "protects immutable repository registration fields" do
    expect { create_repository.update_column(:base_ref, "refs/heads/other") }
      .to raise_error(ActiveRecord::StatementInvalid, /repository registration is immutable/)
  end

  it "protects the immutable repository identifier" do
    expect { create_repository.update_column(:id, SecureRandom.uuid) }
      .to raise_error(ActiveRecord::StatementInvalid, /primary key is immutable/)
  end

  it "prevents repository deletion so prefixes cannot be reused" do
    expect { create_repository.delete }
      .to raise_error(ActiveRecord::StatementInvalid, /repository registration cannot be deleted/)
  end

  it "requires task state to belong to its selected version" do
    expect { mismatched_task.save!(validate: false) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "enforces task sequence bounds in SQLite" do
    expect { task_with_sequence(0).save!(validate: false) }
      .to raise_error(ActiveRecord::StatementInvalid, /tasks_sequence_range/)
  end

  it "enforces workflow version uniqueness in SQLite" do
    workflow = create_workflow
    attributes = workflow.fetch(:version).attributes.except("id", "published_at", "created_at", "updated_at")

    expect { WorkflowVersion.new(attributes).save!(validate: false) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "enforces workflow identifier syntax in SQLite" do
    state = create_source_state(create_workflow_version(create_task_type, "1.0.0"))

    expect { state.update_column(:identifier, "Invalid") }
      .to raise_error(ActiveRecord::StatementInvalid, /workflow_states_identifier_format/)
  end

  it "rejects tasks pinned to unpublished workflows" do
    expect { unpublished_task.save!(validate: false) }
      .to raise_error(ActiveRecord::StatementInvalid, /task workflow version must be published/)
  end

  it "allows a task state transition within its workflow version" do
    workflow = create_workflow
    task = create_task(workflow)

    expect { task.update!(workflow_state: workflow.fetch(:terminal)) }.to change(task, :workflow_state)
  end

  it "protects immutable task identity" do
    expect { create_task.update_column(:sequence, 2) }
      .to raise_error(ActiveRecord::StatementInvalid, /task identity and workflow version are immutable/)
  end

  it "protects the immutable task identifier" do
    expect { create_task.update_column(:id, SecureRandom.uuid) }
      .to raise_error(ActiveRecord::StatementInvalid, /primary key is immutable/)
  end

  it "preserves transition membership when a state is moved between versions" do
    source, other_version = transition_source_and_other_version

    expect { source.update_column(:workflow_version_id, other_version.id) }
      .to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "uses optimistic locking for tasks" do
    task = create_task
    stale_copy = Task.find(task.id)
    task.update!(title: "Changed title")

    expect { stale_copy.update!(title: "Stale title") }.to raise_error(ActiveRecord::StaleObjectError)
  end

  it "allows activation of a published version" do
    workflow = create_workflow

    expect { workflow.fetch(:task_type).update!(current_workflow_version: workflow.fetch(:version)) }
      .to change(workflow.fetch(:task_type), :current_workflow_version).from(nil).to(workflow.fetch(:version))
  end

  it "rejects activation for another task type" do
    workflow = create_workflow

    expect { create_task_type.update_column(:current_workflow_version_id, workflow.fetch(:version).id) }
      .to raise_error(ActiveRecord::StatementInvalid, /current workflow version must be published/)
  end

  it "prevents a published workflow version update" do
    expect { create_workflow.fetch(:version).touch }
      .to raise_error(ActiveRecord::StatementInvalid, /published workflow version is immutable/)
  end

  it "prevents a published workflow version deletion" do
    expect { create_workflow.fetch(:version).delete }
      .to raise_error(ActiveRecord::StatementInvalid, /published workflow version cannot be deleted/)
  end

  %i[source template effect requirement requirement_state transition condition].each do |record_name|
    context "with published #{record_name}" do
      subject(:record) { create_workflow.fetch(record_name) }

      it "prevents updates" do
        expect { record.touch }
          .to raise_error(ActiveRecord::StatementInvalid, /published workflow content is immutable/)
      end

      it "prevents inserts" do
        expect { record.dup.save!(validate: false) }
          .to raise_error(ActiveRecord::StatementInvalid, /published workflow content is immutable/)
      end

      it "prevents deletion" do
        expect { record.delete }
          .to raise_error(ActiveRecord::StatementInvalid, /published workflow content is immutable/)
      end
    end
  end

  it "seeds quick-fix idempotently" do
    2.times { load Rails.root.join("db/seeds.rb") }

    expect(TaskType.where(id: "quick-fix").count).to eq(1)
  end

  it "seeds quick-fix without an active workflow" do
    load Rails.root.join("db/seeds.rb")

    expect(TaskType.find("quick-fix").current_workflow_version).to be_nil
  end
end
