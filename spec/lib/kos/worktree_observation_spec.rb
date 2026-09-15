require "spec_helper"
require_relative "../../../lib/kos/worktree_observation"

RSpec.describe Kos::WorktreeObservation do
  let(:attributes) do
    { repository_id: "e37ee751-37a6-4f99-98e6-ac930fe20a80",
      reservation_id: "6412099f-08cf-4c0c-a7a4-e8dfe9cf8758", fencing_token: 3,
      path: "/tmp/worktrees/KOS-000001", branch: "kos/task-KOS-000001", state: "clean",
      head_sha: "a" * 40, git_common_dir_digest: "sha256:#{'b' * 64}" }
  end

  it "produces the adapter-compatible canonical digest for string or keyword evidence fields" do
    keyword_digest = described_class.digest(**attributes)
    string_fields = attributes.slice(:head_sha, :git_common_dir_digest).transform_keys(&:to_s)
    base = attributes.except(:head_sha, :git_common_dir_digest)

    expect(described_class.digest(**base, **string_fields)).to eq(keyword_digest)
  end

  it "binds evidence to the current fencing token" do
    expect(described_class.digest(**attributes.merge(fencing_token: 4)))
      .not_to eq(described_class.digest(**attributes))
  end

  it "binds post-context evidence to the frozen input" do
    context = { input_context_digest: "sha256:#{'c' * 64}" }
    expect(described_class.digest(**attributes, **context)).not_to eq(described_class.digest(**attributes))
  end
end
