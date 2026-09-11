require "rails_helper"

RSpec.describe Idempotency::Execute, :aggregate_failures do
  let(:body) { { "workflow_id" => "quick-fix", "expected_lock_version" => 0 } }
  let(:serializer) { ->(value) { { "value" => value } } }

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
      .to raise_error(WorkflowCatalog::Error) { |error| expect(error.code).to eq("idempotency_conflict") }
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

    expect { execute }.to raise_error(WorkflowCatalog::Error) { |failure| expect(failure.code).to eq("request_timeout") }
  end

  it "recovers when bounded SQLite contention clears" do
    error = ActiveRecord::StatementInvalid.new("busy")
    allow(error).to receive(:cause).and_return(SQLite3::BusyException.new)
    allow(described_class).to receive(:execute).and_raise(error).once.and_call_original

    expect(execute.data).to eq("value" => "first")
  end
end
