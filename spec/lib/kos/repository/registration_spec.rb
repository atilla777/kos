require "fileutils"
require "open3"
require "tmpdir"
require "spec_helper"
require_relative "../../../../lib/kos/repository"

RSpec.describe Kos::Repository::Registration, :aggregate_failures do
  let(:directory) { File.realpath(Dir.mktmpdir("kos-registration-spec")) }
  let(:repository_path) { File.join(directory, "project") }
  let(:common_dir) { File.join(repository_path, ".git") }
  let(:attributes) do
    { "git_common_dir" => common_dir, "task_prefix" => "KOS", "trusted_remote" => "origin",
      "trusted_remote_url" => "ssh://git@example.test/team/project.git", "base_ref" => "refs/heads/main" }
  end

  before do
    FileUtils.mkdir_p(repository_path)
    git("init", "--initial-branch=main")
    git("config", "user.name", "KOS Test")
    git("config", "user.email", "kos@example.test")
    File.write(File.join(repository_path, "README.md"), "initial\n")
    git("add", "README.md")
    git("commit", "-m", "Initial")
    git("remote", "add", "origin", "git@example.test:team/project.git")
  end

  after do
    FileUtils.remove_entry(directory) if File.exist?(directory)
  end

  it "independently observes canonical identity, normalized trust, and a local base ref" do
    expect(described_class.new(attributes).call).to eq(attributes)
  end

  it "rejects a non-canonical common directory" do
    input = attributes.merge("git_common_dir" => File.join(repository_path, "..", "project", ".git"))

    expect { described_class.new(input).call }.to raise_error(Kos::Repository::Error) do |error|
      expect(error.code).to eq("repository_registration_invalid")
    end
  end

  it "rejects mismatched trust and a missing local base ref" do
    failures = [ attributes.merge("trusted_remote_url" => "ssh://git@example.test/other.git"),
      attributes.merge("base_ref" => "refs/heads/missing") ]

    expect(failures.map { |input| capture_error(input).code })
      .to eq(%w[repository_registration_invalid repository_registration_invalid])
  end

  private

  def capture_error(input)
    described_class.new(input).call
  rescue Kos::Repository::Error => error
    error
  end

  def git(*arguments)
    _stdout, stderr, status = Open3.capture3("git", "-C", repository_path, *arguments)
    raise stderr unless status.success?
  end
end
