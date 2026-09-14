require "rails_helper"

RSpec.describe RepositoryRegistration::Inspect do
  let(:attributes) { { "git_common_dir" => "/tmp/project.git" } }

  it "maps adapter validation to the stable registration error" do
    expect(mapped_code("validation", "repository_registration_invalid"))
      .to eq("repository_registration_invalid")
  end

  it "maps a transient adapter timeout to request_timeout" do
    expect(mapped_code("transient", "git_timeout")).to eq("request_timeout")
  end

  private

  def mapped_code(category, code)
    adapter = instance_double(Kos::Repository::Registration)
    allow(adapter).to receive(:call).and_raise(
      Kos::Repository::Error.new(category, code, "Inspection failed", retryable: category == "transient")
    )
    described_class.call(attributes, adapter:)
  rescue OperationError => error
    error.code
  end
end
