require "rails_helper"

RSpec.describe Idempotency::Execute, :aggregate_failures do
  let(:body) { { "workflow_id" => "quick-fix", "expected_lock_version" => 0 } }
  let(:serializer) { ->(value) { { "value" => value } } }

  def repository(prefix = "KOS")
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: prefix,
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end

  def execute_for(scope)
    described_class.call(command: "task.create", key: "task-key-1", body: { "title" => "Fix" },
      status: 201, serialize: serializer, repository: scope) { scope.task_prefix }
  end

  def replay_final_failure
    calls = 0
    2.times do
      expect { execute { calls += 1; raise OperationError.new("task_type_unavailable", "Unavailable") } }
        .to raise_error(OperationError) { |error| expect(error.code).to eq("task_type_unavailable") }
    end
    calls
  end

  def execute_partial_failure
    execute do
      TaskType.create!(id: "partial", name: "partial", workflow_id: "partial")
      raise OperationError.new("task_type_unavailable", "Unavailable")
    end
  end

  def execute(value = "first", request_body: body, &block)
    described_class.call(command: "workflow.publish", key: "publish-key-1", body: request_body,
      status: 201, serialize: serializer) { block ? block.call : value }
  end

  it "records and replays the original completed result" do
    first = execute
    replay = execute("second")

    expect([ first.data, first.status, first.replayed ]).to eq([ { "value" => "first" }, 201, false ])
    expect([ replay.data, replay.status, replay.replayed ]).to eq([ first.data, 201, true ])
    expect(IdempotencyRecord.count).to eq(1)
  end

  it "rejects key reuse with a different canonical body" do
    execute

    expect { execute(request_body: body.merge("expected_lock_version" => 1)) }
      .to raise_error(OperationError) { |error| expect(error.code).to eq("idempotency_conflict") }
  end

  it "records and replays a final operation failure" do
    calls = replay_final_failure
    record = IdempotencyRecord.find_by!(command: "workflow.publish")

    expect([ calls, record.response_status, record.response_data.dig("_operation_error", "code") ])
      .to eq([ 1, 409, "task_type_unavailable" ])
  end

  it "rolls back partial operation state before recording its failure" do
    expect { execute_partial_failure }.to raise_error(OperationError)

    expect([ TaskType.exists?("partial"), IdempotencyRecord.count ]).to eq([ false, 1 ])
  end

  it "replays integer schema values represented as integral JSON floats" do
    execute(request_body: body.merge("expected_lock_version" => 1))
    replay = execute(request_body: body.merge("expected_lock_version" => 1.0))
    expect(replay.replayed).to be(true)
  end

  it "rolls back state and the idempotency result together" do
    expect { execute { TaskType.create!(id: "temporary", name: "temporary", workflow_id: "temporary"); raise "failed" } }
      .to raise_error("failed")
    expect([ TaskType.exists?("temporary"), IdempotencyRecord.exists? ]).to eq([ false, false ])
  end

  it "retries bounded SQLite contention before returning a timeout" do
    error = ActiveRecord::StatementInvalid.new("busy")
    allow(error).to receive(:cause).and_return(SQLite3::BusyException.new)
    allow(described_class).to receive(:execute).exactly(3).times.and_raise(error)

    expect { execute }.to raise_error(OperationError) { |failure| expect(failure.code).to eq("request_timeout") }
  end

  it "recovers when bounded SQLite contention clears" do
    error = ActiveRecord::StatementInvalid.new("busy")
    allow(error).to receive(:cause).and_return(SQLite3::BusyException.new)
    allow(described_class).to receive(:execute).and_raise(error).once.and_call_original

    expect(execute.data).to eq("value" => "first")
  end

  it "scopes records and fingerprints by repository" do
    results = [ repository, repository("APP") ].map { |scope| execute_for(scope) }

    expect(results.map(&:data)).to eq([ { "value" => "KOS" }, { "value" => "APP" } ])
    expect(IdempotencyRecord.where(command: "task.create", idempotency_key: "task-key-1").count).to eq(2)
  end
end
