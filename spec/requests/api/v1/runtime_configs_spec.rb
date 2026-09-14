require "rails_helper"

RSpec.describe "API v1 runtime configuration", :aggregate_failures, type: :request do
  around do |example|
    previous = ENV["KOS_API_TOKEN"]
    ENV["KOS_API_TOKEN"] = "runtime-config-test-token"
    example.run
  ensure
    ENV["KOS_API_TOKEN"] = previous
  end

  def headers(key: nil)
    value = { "Authorization" => "Bearer runtime-config-test-token", "Accept" => "application/json" }
    value["Idempotency-Key"] = key if key
    value
  end

  def document
    JSON.parse(response.body)
  end

  def update_body(enabled: true, expected_lock_version: 0)
    { "retrospective_enabled" => enabled, "expected_lock_version" => expected_lock_version }
  end

  def post_update(body = update_body, key: "runtime-config-key-1")
    request = { "schema_version" => "1", "command" => "runtime_config.update", "body" => body }
    post "/api/v1/runtime-config", params: request, headers: headers(key: key), as: :json
  end

  def expect_result_schema
    expect(Kos::Cli::SchemaRegistry.new).to be_valid("commands.json", "result", document)
  end

  it "requires authentication" do
    get "/api/v1/runtime-config", headers: { "Accept" => "application/json" }

    expect([ response.status, document.dig("error", "code") ]).to eq([ 401, "authentication_required" ])
  end

  it "returns the disabled singleton through the closed resource contract" do
    get "/api/v1/runtime-config", headers: headers

    expect([ response.status, document.fetch("command"), document.dig("data", "retrospective_enabled"),
      document.dig("data", "lock_version") ]).to eq([ 200, "runtime_config.get", false, 0 ])
    expect_result_schema
  end

  it "updates under optimistic locking and replays the original result" do
    2.times { post_update }

    expect([ response.status, document.dig("data", "retrospective_enabled"), document.dig("data", "lock_version"),
      RuntimeConfig.current.lock_version, IdempotencyRecord.count ]).to eq([ 200, true, 1, 1, 1 ])
    expect_result_schema
  end

  it "returns stable conflicts for stale locks and key reuse" do
    expect(conflict_summary)
      .to eq([ [ 409, "stale_lock_version" ], 409, "idempotency_conflict", true ])
  end

  it "rejects repository scope, query parameters, and missing keys" do
    expect(malformed_scope_failures).to eq([ [ 403, "repository_access_denied" ],
      [ 400, "malformed_input" ], [ 400, "malformed_input" ] ])
  end

  def conflict_summary
    post_update
    post_update(update_body(enabled: false), key: "runtime-config-key-2")
    stale = [ response.status, document.dig("error", "code") ]
    post_update(update_body(enabled: false))
    [ stale, response.status, document.dig("error", "code"), RuntimeConfig.current.retrospective_enabled ]
  end

  def malformed_scope_failures
    scoped = { "schema_version" => "1", "command" => "runtime_config.update", "repository_id" => SecureRandom.uuid,
      "body" => update_body }
    post "/api/v1/runtime-config", params: scoped, headers: headers(key: "runtime-config-key-1"), as: :json
    failures = [ [ response.status, document.dig("error", "code") ] ]
    get "/api/v1/runtime-config?extra=true", headers: headers
    failures << [ response.status, document.dig("error", "code") ]
    request = { "schema_version" => "1", "command" => "runtime_config.update", "body" => update_body }
    post "/api/v1/runtime-config", params: request, headers: headers, as: :json
    failures << [ response.status, document.dig("error", "code") ]
    failures
  end
end
