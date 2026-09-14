require "rails_helper"

RSpec.describe RepositoryRegistration::Register, :aggregate_failures do
  let(:attributes) do
    { "git_common_dir" => "/tmp/#{SecureRandom.uuid}.git", "task_prefix" => "KOS",
      "trusted_remote" => "origin", "trusted_remote_url" => "ssh://git@example.test/team/project.git",
      "base_ref" => "refs/heads/main" }
  end

  it "creates once and returns the immutable matching registration" do
    first = described_class.call(attributes)
    second = described_class.call(attributes)

    expect([ second.id, Repository.count ]).to eq([ first.id, 1 ])
  end

  it "rejects changed trust settings for an existing common directory" do
    described_class.call(attributes)

    expect { described_class.call(attributes.merge("base_ref" => "refs/heads/other")) }
      .to raise_error(OperationError) { |error| expect(error.code).to eq("repository_registration_conflict") }
  end

  it "rejects an occupied task prefix for another common directory" do
    described_class.call(attributes)

    expect { described_class.call(attributes.merge("git_common_dir" => "/tmp/#{SecureRandom.uuid}.git")) }
      .to raise_error(OperationError) { |error| expect(error.code).to eq("repository_registration_conflict") }
  end
end
