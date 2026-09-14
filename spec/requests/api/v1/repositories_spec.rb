require "fileutils"
require "open3"
require "rails_helper"

RSpec.describe "API v1 repository registration", :aggregate_failures, type: :request do
  let(:directory) { File.realpath(Dir.mktmpdir("kos-api-registration-spec")) }
  let(:repository_path) { File.join(directory, "project") }
  let(:common_dir) { File.join(repository_path, ".git") }
  let(:body) do
    { "git_common_dir" => common_dir, "task_prefix" => "KOS", "trusted_remote" => "origin",
      "trusted_remote_url" => "ssh://git@example.test/team/project.git", "base_ref" => "refs/heads/main" }
  end

  around do |example|
    previous = ENV["KOS_API_TOKEN"]
    ENV["KOS_API_TOKEN"] = "repository-test-token"
    initialize_repository
    example.run
  ensure
    ENV["KOS_API_TOKEN"] = previous
    FileUtils.remove_entry(directory) if directory && File.exist?(directory)
  end

  it "creates and matching-repeats one normalized immutable repository with HTTP 200" do
    summary, first = creation_repeat_summary
    expect(summary).to eq([ 200, first, 1, 2 ])
    expect(first.slice("git_common_dir", "trusted_remote_url", "base_ref"))
      .to eq(body.slice("git_common_dir", "trusted_remote_url", "base_ref"))
  end

  it "replays globally without repeating Git inspection" do
    expect(global_replay_summary)
      .to eq([ 200, true, 1, 1 ])
  end

  it "rejects idempotency reuse and immutable registration changes" do
    expect(idempotency_and_conflict_summary)
      .to eq([ [ 409, "idempotency_conflict" ], 409, "repository_registration_conflict", 1 ])
  end

  it "returns a stable safe validation error for observed trust mismatch" do
    register(body.merge("trusted_remote_url" => "ssh://git@example.test/other.git"))

    expect([ response.status, document.dig("error", "code"), response.body.include?(directory) ])
      .to eq([ 422, "repository_registration_invalid", false ])
  end

  it "does not persist or replay a transient inspection timeout" do
    expect(transient_inspection_summary).to eq([ 504, "request_timeout", 0, 2 ])
  end

  def transient_inspection_summary
    adapter = instance_double(Kos::Repository::Registration)
    calls = 0
    allow(adapter).to receive(:call) do
      calls += 1
      raise Kos::Repository::Error.new("transient", "git_timeout", "Timed out", retryable: true)
    end
    allow(Kos::Repository::Registration).to receive(:new).and_return(adapter)
    2.times { register }
    [ response.status, document.dig("error", "code"), IdempotencyRecord.count, calls ]
  end

  it "requires authentication and the closed registration request" do
    register(request_headers: headers.except("Authorization"))
    authentication = [ response.status, document.dig("error", "code") ]
    register(body.merge("unexpected" => true))

    expect([ authentication, response.status, document.dig("error", "code"), Repository.count ])
      .to eq([ [ 401, "authentication_required" ], 400, "malformed_input", 0 ])
  end

  private

  def creation_repeat_summary
    register
    first = document.fetch("data")
    register(key: "repository-key-2")
    [ [ response.status, document.fetch("data"), Repository.count, IdempotencyRecord.count ], first ]
  end

  def global_replay_summary
    register
    first_id = document.dig("data", "id")
    FileUtils.mv(common_dir, "#{common_dir}.moved")
    register
    [ response.status, document.dig("data", "id") == first_id, Repository.count, IdempotencyRecord.count ]
  end

  def idempotency_and_conflict_summary
    register
    register(body.merge("task_prefix" => "APP"))
    key_reuse = [ response.status, document.dig("error", "code") ]
    register(body.merge("task_prefix" => "APP"), key: "repository-key-2")
    [ key_reuse, response.status, document.dig("error", "code"), Repository.count ]
  end

  def initialize_repository
    FileUtils.mkdir_p(repository_path)
    git("init", "--initial-branch=main")
    git("config", "user.name", "KOS Test")
    git("config", "user.email", "kos@example.test")
    File.write(File.join(repository_path, "README.md"), "initial\n")
    git("add", "README.md")
    git("commit", "-m", "Initial")
    git("remote", "add", "origin", "git@example.test:team/project.git")
  end

  def git(*arguments)
    _stdout, stderr, status = Open3.capture3("git", "-C", repository_path, *arguments)
    raise stderr unless status.success?
  end

  def register(request_body = body, key: "repository-key-1", request_headers: headers)
    request_document = { "schema_version" => "1", "command" => "repository.register", "body" => request_body }
    post "/api/v1/repositories", params: request_document, headers: request_headers.merge("Idempotency-Key" => key),
      as: :json
  end

  def headers
    { "Authorization" => "Bearer repository-test-token", "Accept" => "application/json" }
  end

  def document
    JSON.parse(response.body)
  end
end
