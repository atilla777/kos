require "digest"
require "fileutils"
require "json"
require "rbconfig"
require "stringio"
require "tmpdir"
require "spec_helper"
require_relative "../../../../../lib/kos/runtime/open_code/launcher"

module OpenCodeLauncherSpecSupport
  ROOT = File.expand_path("../../../../..", __dir__)
  Status = Data.define(:successful, :exitstatus, :signal) do
    def success? = successful
    def exited? = signal.nil?
    def signaled? = !signal.nil?
    def termsig = signal
  end

  Runner = Struct.new(:results, :calls) do
    def call(command, **options)
      calls << [ command, options ]
      result = results.shift
      raise result if result.is_a?(Exception)
      result = result.call(command) if result.respond_to?(:call)
      options[:stdout]&.write(result.stdout)
      options[:stderr]&.write(result.stderr)
      result
    end
  end
end

RSpec.describe Kos::Runtime::OpenCode::Launcher do
  let(:directory) { RSpec.current_example.metadata.fetch(:directory) }
  let(:streams) { { stdout: StringIO.new, stderr: StringIO.new, delivery: StringIO.new } }
  let(:primary_output) do
    " {not-json}\n" \
      "{\"type\":\"text\",\"timestamp\":1,\"sessionID\":\"ses_root\",\"part\":{\"type\":\"text\",\"text\":\"primary\",\"time\":{\"end\":1}}}\n"
  end

  around do |example|
    Dir.mktmpdir("kos-opencode-launcher-") do |directory|
      example.metadata[:directory] = File.realpath(directory)
      install_runtime(example.metadata.fetch(:directory))
      example.run
    end
  end

  it "preserves primary bytes and delivers a separately bound retrospective result" do
    expect(successful_run).to eq([ 7, primary_output, "primary warning\n", "result", true,
      [ "--pure", "--session", "ses_root", "--agent", "kos-retrospective" ], 30, true, true ])
  end

  it "preserves primary output and status across every retrospective outcome" do
    expect(primary_preservation_observations).to all(eq([ 7, primary_output, "primary warning\n" ]))
  end

  it "does not invoke retrospective when the sampled setting is disabled" do
    runner = runner(success("1.18.26\n"), disabled_config, success(primary_output))
    status = launcher(runner).run([ "--worktree", directory, "--", "perform task" ])

    expect([ status, runner.calls.length, streams.fetch(:stdout).string, streams.fetch(:delivery).string ])
      .to eq([ 0, 3, primary_output, "" ])
  end

  it "fails closed for malformed or mismatched runtime configuration envelopes" do
    expect(malformed_config_observations).to all(eq([ 3, "" ]))
  end

  it "preserves primary bytes for malformed, failed, and timed-out retrospective outcomes" do
    expect(failure_observations).to eq([
      [ primary_output, "malformed_result" ], [ primary_output, "provider_failure" ], [ primary_output, "timeout" ]
    ])
  end

  it "runs retrospective after normal nonzero exit but not after signaled or abrupt completion" do
    expect(completion_observations).to eq([ [ 7, 4 ], [ 143, 3 ], [ 143, 3 ] ])
  end

  it "parses only options before the separator and preserves option-looking prompt arguments" do
    expect(option_observations).to eq([ true, %w[-- --model prompt/value], [ 2, 2, 2, 2, 2 ] ])
  end

  it "removes KOS, Git, and SSH secrets only from the retrospective process" do
    expect(retrospective_environment_observation).to eq([ false, false, false, false, "1", true ])
  end

  it "retains only the explicitly selected known provider credential" do
    expect(provider_environment_observations).to eq([ [ "openai", nil, nil ], [ nil, "anthropic", nil ],
      [ nil, nil, nil ] ])
  end

  it "uses unsetenv_others in a real child process" do
    expect(isolated_child_environment).to eq({ "PATH" => ENV.fetch("PATH"), "OPENAI_API_KEY" => "selected" })
  end

  it "rejects sensitive and verbatim proposal text before delivery" do
    expect(sanitation_observations).to eq(%w[malformed_result malformed_result malformed_result])
  end

  it "fails closed when primary dialogue traversal exceeds its bound" do
    expect(oversized_dialogue_reason).to eq("malformed_result")
  end

  def oversized_dialogue_reason
    event = { "type" => "text", "sessionID" => "ses_root", "part" => Array.new(10_001, "") }
    delivery = StringIO.new
    process = runner(success("1.18.26\n"), enabled_config, success("#{JSON.generate(event)}\n"), retrospective_response)
    described_class.new(environment: {}, stdout: StringIO.new, stderr: StringIO.new, runner: process,
      retrospective_output: delivery).run([ "--worktree", directory, "--", "task" ])
    JSON.parse(delivery.string).fetch("reason")
  end

  it "rejects pipe and standard-stream delivery descriptors and does not block on nonblocking backpressure" do
    expect(delivery_boundary_observations).to eq([ 0, "wait_readable", 0, 0, "", 0 ])
  end

  it "kills a retrospective process group at the fixed timeout boundary" do
    runner = described_class::ProcessRunner.new
    result = runner.call([ RbConfig.ruby, "-e", "sleep 30" ], chdir: directory, timeout: 0.05)
    expect(result.timed_out).to be(true)
  end

  it "records bounded capture truncation without truncating the primary destination" do
    stub_const("#{described_class}::ProcessRunner::CAPTURE_LIMIT", 64)
    destination = StringIO.new
    observed = described_class::ProcessRunner.new.call([ RbConfig.ruby, "-e", "print 'x' * 65" ], chdir: directory,
      stdout: destination)
    expect([ observed.stdout.bytesize, observed.stdout_truncated, destination.string.bytesize ]).to eq([ 64, true, 65 ])
  end

  it "does not start retrospective from a truncated primary capture" do
    expect(truncated_primary_observation).to eq([ 0, 3, "transport_failure" ])
  end

  it "skips the second process if config, profile, skill, or plugin bytes changed during primary" do
    expect(integrity_drift_observations).to all(eq([ 0, 3, "transport_failure" ]))
  end

  it "disables retrospective before primary when the installed manifest is invalid" do
    File.write(File.join(directory, ".opencode/kos-runtime-manifest.json"), "{}")
    process = runner(success("1.18.26\n"), enabled_config, success(primary_output))
    status = launcher(process).run([ "--worktree", directory, "--", "task" ])
    expect([ status, process.calls.length, process.calls.last.last.dig(:environment, "KOS_RETROSPECTIVE_ENABLED"),
      streams.fetch(:delivery).string ]).to eq([ 0, 3, "0", "" ])
  end

  it "supports absent config and exactly one JSON or JSONC project config" do
    expect(project_configuration_observations).to eq([ [ 0, 4, "result" ], [ 0, 4, "result" ], [ 0, 3, "" ] ])
  end

  it "snapshots JSONC bytes and rejects custom explicit config" do
    expect(configuration_boundary_observations).to eq([ [ 0, 3, "transport_failure" ], [ 0, 3, "0" ] ])
  end

  it "rejects project configuration appearing or becoming ambiguous after primary" do
    expect(configuration_state_drift_observations).to all(eq([ 0, 3, "transport_failure" ]))
  end

  it "rejects forged, wrongly bound, and structurally changed runtime manifests" do
    expect(manifest_contract_observations).to all(eq([ 0, 3, "0" ]))
  end

  it "rejects NUL in the worktree path without raising" do
    expect(launcher(runner).run([ "--worktree", "#{directory}\0bad", "--", "task" ])).to eq(2)
  end

  private

  def truncated_primary_observation
    delivery = StringIO.new
    process = runner(success("1.18.26\n"), enabled_config,
      result(primary_output, "", true, 0, stdout_truncated: true), retrospective_response)
    status = described_class.new(environment: {}, stdout: StringIO.new, stderr: StringIO.new, runner: process,
      retrospective_output: delivery).run([ "--worktree", directory, "--", "task" ])
    [ status, process.calls.length, JSON.parse(delivery.string).fetch("reason") ]
  end

  def launcher(runner)
    described_class.new(environment: {}, stdout: streams.fetch(:stdout), stderr: streams.fetch(:stderr), runner: runner,
      retrospective_output: streams.fetch(:delivery))
  end

  def runner(*results)
    OpenCodeLauncherSpecSupport::Runner.new(results, [])
  end

  def result(out, err, ok, code, timed_out: false, signal: nil, stdout_truncated: false, stderr_truncated: false)
    status = OpenCodeLauncherSpecSupport::Status.new(ok, code, signal)
    described_class::Result.new(stdout: out, stderr: err, status: status, timed_out: timed_out,
      stdout_truncated: stdout_truncated, stderr_truncated: stderr_truncated)
  end

  def success(out, err = "", code = 0) = result(out, err, true, code)
  def failed(err) = result("", err, false, 1)
  def timed_out = result("", "", false, nil, timed_out: true)
  def signaled(signal = 15, timed_out: false) = result(primary_output, "primary warning\n", false, nil,
    timed_out: timed_out, signal: signal)

  def enabled_config
    success("#{JSON.generate(config_envelope(true))}\n")
  end

  def disabled_config
    success("#{JSON.generate(config_envelope(false))}\n")
  end

  def config_envelope(enabled)
    { "schema_version" => "1", "request_id" => "99999999-9999-4999-8999-999999999999",
      "command" => "runtime_config.get", "data" => { "schema_version" => "1",
        "retrospective_enabled" => enabled, "lock_version" => 0, "updated_at" => "2026-09-14T09:00:00Z" } }
  end

  def malformed_config_observations
    malformed = [ config_envelope(true).merge("unexpected" => true),
      config_envelope(true).merge("command" => "runtime_config.update"),
      config_envelope(true).merge("schema_version" => "2"), RuntimeError.new("config unavailable") ]
    malformed.map do |document|
      configuration = document.is_a?(Exception) ? document : success("#{JSON.generate(document)}\n")
      process = runner(success("1.18.26\n"), configuration, success(primary_output))
      output = StringIO.new
      delivery = StringIO.new
      described_class.new(environment: {}, stdout: output, stderr: StringIO.new, runner: process,
        retrospective_output: delivery).run([ "--worktree", directory, "--", "task" ])
      [ process.calls.length, delivery.string ]
    end
  end

  def retrospective_response
    lambda do |command|
      invocation = JSON.parse(command.last)
      document = { "schema_version" => "1", "session_id" => invocation.fetch("session_id"),
        "source" => "orchestrator", "primary_result_acknowledged" => true,
        "outcome" => "no_action", "proposals" => [] }
      event = { "type" => "text", "sessionID" => "ses_root",
        "part" => { "type" => "text", "text" => JSON.generate(document), "time" => { "end" => 1 } } }
      success("#{JSON.generate(event)}\n")
    end
  end

  def proposal_response(text)
    lambda do |command|
      invocation = JSON.parse(command.last)
      proposal = { "category" => "project", "problem" => text, "observed_impact" => "Observed impact",
        "sanitized_evidence" => "Sanitized evidence", "proposed_outcome" => "Proposed outcome",
        "suggested_task_type" => "quick-fix", "uncertainties" => [] }
      document = { "schema_version" => "1", "session_id" => invocation.fetch("session_id"),
        "source" => "orchestrator", "primary_result_acknowledged" => true,
        "outcome" => "proposals", "proposals" => [ proposal ] }
      event = { "type" => "text", "sessionID" => "ses_root",
        "part" => { "type" => "text", "text" => JSON.generate(document), "time" => { "end" => 1 } } }
      success("#{JSON.generate(event)}\n")
    end
  end

  def successful_run
    process = runner(success("1.18.26\n"), enabled_config, success(primary_output, "primary warning\n", 7),
      retrospective_response)
    status = launcher(process).run([ "--worktree", directory, "--", "perform", "task" ])
    delivery = JSON.parse(streams.fetch(:delivery).string)
    command, options = process.calls.last
    selected = %w[--pure --session ses_root --agent kos-retrospective].select { |argument| command.include?(argument) }
    [ status, streams.fetch(:stdout).string, streams.fetch(:stderr).string, delivery.fetch("outcome"),
      delivery.dig("result", "session_id") == delivery.dig("invocation", "session_id"), selected,
      options.fetch(:timeout), options.fetch(:unsetenv_others), command.take(3) == [ "opencode", "--pure", "run" ] ]
  end

  def primary_preservation_observations
    retrospectives = [ retrospective_response, malformed_response, failed("provider failed"), timed_out,
      RuntimeError.new("spawn failed") ]
    retrospectives.map do |retrospective|
      output = StringIO.new
      errors = StringIO.new
      process = runner(success("1.18.26\n"), enabled_config,
        success(primary_output, "primary warning\n", 7), retrospective)
      status = described_class.new(environment: {}, stdout: output, stderr: errors, runner: process,
        retrospective_output: StringIO.new).run([ "--worktree", directory, "--", "task" ])
      [ status, output.string, errors.string ]
    end
  end

  def completion_observations
    [ success(primary_output, "", 7), signaled, signaled(15, timed_out: true) ].map do |primary|
      process = runner(success("1.18.26\n"), enabled_config, primary, retrospective_response)
      status = described_class.new(environment: {}, stdout: StringIO.new, stderr: StringIO.new, runner: process,
        retrospective_output: StringIO.new).run([ "--worktree", directory, "--", "task" ])
      [ status, process.calls.length ]
    end
  end

  def option_observations
    process = runner(success("1.18.26\n"), disabled_config, success(primary_output))
    status = launcher(process).run([ "--model", "provider/model", "--worktree", directory,
      "--", "--model", "prompt/value" ])
    prompt_tail = process.calls.last.first.last(3)
    invalid = [ [ "--worktree", directory, "task" ], [ "--worktree", directory, "--worktree", directory, "--", "x" ],
      [ "--unknown", "x", "--worktree", directory, "--", "x" ], [ "--worktree", "--", "x" ],
      [ "--worktree", directory, "--model", "invalid", "--", "x" ] ]
    [ status.zero?, prompt_tail, invalid.map { |arguments| launcher(runner).run(arguments) } ]
  end

  def retrospective_environment_observation
    environment = { "KOS_API_TOKEN" => "primary-token", "KOS_API_URL" => "http://secret",
      "GIT_SSH_COMMAND" => "secret ssh", "SSH_AUTH_SOCK" => "/secret/socket", "OPENAI_API_KEY" => "provider",
      "AWS_SECRET_ACCESS_KEY" => "cloud-secret", "OPENCODE_CONFIG_DIR" => "/hostile", "PATH" => ENV.fetch("PATH") }
    process = runner(success("1.18.26\n"), enabled_config, success(primary_output), retrospective_response)
    described_class.new(environment: environment, stdout: StringIO.new, stderr: StringIO.new, runner: process,
      retrospective_output: StringIO.new).run([ "--worktree", directory, "--", "task" ])
    retrospective_env = process.calls[3].last.fetch(:environment)
    [ retrospective_env.key?("KOS_API_TOKEN"), retrospective_env.key?("OPENAI_API_KEY"),
      retrospective_env.key?("AWS_SECRET_ACCESS_KEY"), retrospective_env.key?("OPENCODE_CONFIG_DIR"),
      retrospective_env["KOS_RETROSPECTIVE_ACTIVE"],
      process.calls[3].last.fetch(:unsetenv_others) ]
  end

  def provider_environment_observations
    { "openai/model" => { "OPENAI_API_KEY" => "openai" },
      "anthropic/model" => { "ANTHROPIC_API_KEY" => "anthropic" },
      "unknown/model" => {} }.map do |model, expected|
      environment = { "OPENAI_API_KEY" => "openai", "ANTHROPIC_API_KEY" => "anthropic",
        "AWS_SECRET_ACCESS_KEY" => "aws", "PATH" => ENV.fetch("PATH") }
      process = runner(success("1.18.26\n"), enabled_config, success(primary_output), retrospective_response)
      described_class.new(environment: environment, stdout: StringIO.new, stderr: StringIO.new, runner: process,
        retrospective_output: StringIO.new).run([ "--model", model, "--worktree", directory, "--", "task" ])
      child = process.calls[3].last.fetch(:environment)
      [ child["OPENAI_API_KEY"], child["ANTHROPIC_API_KEY"], child["AWS_SECRET_ACCESS_KEY"] ]
    end
  end

  def isolated_child_environment
    previous = ENV["AWS_SECRET_ACCESS_KEY"]
    ENV["AWS_SECRET_ACCESS_KEY"] = "must-not-leak"
    command = [ RbConfig.ruby, "-rjson", "-e",
      "print JSON.generate(ENV.to_h.slice('PATH', 'OPENAI_API_KEY', 'AWS_SECRET_ACCESS_KEY'))" ]
    process = described_class::ProcessRunner.new.call(command, chdir: directory,
      environment: { "PATH" => ENV.fetch("PATH"), "OPENAI_API_KEY" => "selected" }, unsetenv_others: true)
    JSON.parse(process.stdout)
  ensure
    previous.nil? ? ENV.delete("AWS_SECRET_ACCESS_KEY") : ENV["AWS_SECRET_ACCESS_KEY"] = previous
  end

  def integrity_drift_observations
    [ "opencode.json", ".opencode/agents/kos-retrospective.md", ".opencode/skills/kos-retrospective/SKILL.md",
      ".opencode/plugins/kos-session-guard.js" ].map do |path|
      delivery = StringIO.new
      primary = lambda do |_command|
        File.binwrite(File.join(directory, path), "changed")
        success(primary_output)
      end
      process = runner(success("1.18.26\n"), enabled_config, primary, retrospective_response)
      status = described_class.new(environment: {}, stdout: StringIO.new, stderr: StringIO.new, runner: process,
        retrospective_output: delivery).run([ "--worktree", directory, "--", "task" ])
      install_runtime(directory)
      [ status, process.calls.length, JSON.parse(delivery.string).fetch("reason") ]
    end
  end

  def project_configuration_observations
    [ :absent, :jsonc, :ambiguous ].map do |mode|
      install_runtime(directory)
      FileUtils.mv(File.join(directory, "opencode.json"), File.join(directory, "opencode.jsonc")) if mode == :jsonc
      File.delete(File.join(directory, "opencode.json")) if mode == :absent
      File.write(File.join(directory, "opencode.jsonc"), "{}\n") if mode == :ambiguous
      delivery = StringIO.new
      process = runner(success("1.18.26\n"), enabled_config, success(primary_output), retrospective_response)
      status = described_class.new(environment: {}, stdout: StringIO.new, stderr: StringIO.new, runner: process,
        retrospective_output: delivery).run([ "--worktree", directory, "--", "task" ])
      [ status, process.calls.length, delivery.string.empty? ? "" : JSON.parse(delivery.string).fetch("outcome") ]
    end
  end

  def configuration_boundary_observations
    install_runtime(directory)
    FileUtils.mv(File.join(directory, "opencode.json"), File.join(directory, "opencode.jsonc"))
    primary = lambda do |_command|
      File.write(File.join(directory, "opencode.jsonc"), "changed")
      success(primary_output)
    end
    delivery = StringIO.new
    process = runner(success("1.18.26\n"), enabled_config, primary, retrospective_response)
    status = described_class.new(environment: {}, stdout: StringIO.new, stderr: StringIO.new, runner: process,
      retrospective_output: delivery).run([ "--worktree", directory, "--", "task" ])
    custom = runner(success("1.18.26\n"), enabled_config, success(primary_output))
    custom_status = described_class.new(environment: { "OPENCODE_CONFIG" => "/hostile/config.json" },
      stdout: StringIO.new, stderr: StringIO.new, runner: custom, retrospective_output: StringIO.new)
      .run([ "--worktree", directory, "--", "task" ])
    [ [ status, process.calls.length, JSON.parse(delivery.string).fetch("reason") ],
      [ custom_status, custom.calls.length, custom.calls.last.last.dig(:environment, "KOS_RETROSPECTIVE_ENABLED") ] ]
  end

  def configuration_state_drift_observations
    [ :appeared, :ambiguous ].map do |change|
      install_runtime(directory)
      File.delete(File.join(directory, "opencode.json")) if change == :appeared
      primary = lambda do |_command|
        name = change == :appeared ? "opencode.json" : "opencode.jsonc"
        File.write(File.join(directory, name), "{}\n")
        success(primary_output)
      end
      delivery = StringIO.new
      process = runner(success("1.18.26\n"), enabled_config, primary, retrospective_response)
      status = described_class.new(environment: {}, stdout: StringIO.new, stderr: StringIO.new, runner: process,
        retrospective_output: delivery).run([ "--worktree", directory, "--", "task" ])
      [ status, process.calls.length, JSON.parse(delivery.string).fetch("reason") ]
    end
  end

  def manifest_contract_observations
    mutations = [
      ->(manifest) { manifest["repository"]["worktree_root"] = "/wrong" },
      ->(manifest) { manifest["capability_report_digest"] = "sha256:#{'f' * 64}" },
      ->(manifest) { manifest["source_bundle_digest"] = "sha256:#{'f' * 64}" },
      ->(manifest) { manifest["managed_files"].rotate! },
      method(:forge_critical_runtime)
    ]
    mutations.map do |mutation|
      install_runtime(directory)
      manifest = runtime_manifest
      mutation.call(manifest)
      write_runtime_manifest(manifest)
      process = runner(success("1.18.26\n"), enabled_config, success(primary_output))
      status = launcher(process).run([ "--worktree", directory, "--", "task" ])
      [ status, process.calls.length, process.calls.last.last.dig(:environment, "KOS_RETROSPECTIVE_ENABLED") ]
    end
  end

  def forge_critical_runtime(manifest)
    path = ".opencode/agents/kos-retrospective.md"
    File.write(File.join(directory, path), "malicious allow-all agent")
    manifest.fetch("managed_files").find { |entry| entry.fetch("path") == path }["digest"] =
      "sha256:#{Digest::SHA256.file(File.join(directory, path)).hexdigest}"
    manifest["source_bundle_digest"] = "sha256:#{Digest::SHA256.hexdigest(canonical_json(manifest.fetch('managed_files')))}"
  end

  def runtime_manifest
    JSON.parse(File.read(File.join(directory, ".opencode/kos-runtime-manifest.json")))
  end

  def write_runtime_manifest(manifest)
    File.write(File.join(directory, ".opencode/kos-runtime-manifest.json"), JSON.generate(manifest))
  end

  def sanitation_observations
    [ "API_TOKEN=secret", "/home/private/repository", "prefix verbatim source phrase suffix" ].map do |text|
      prompt = text.include?("verbatim source phrase") ? "verbatim source phrase" : "task"
      delivery = StringIO.new
      process = runner(success("1.18.26\n"), enabled_config, success(primary_output), proposal_response(text))
      described_class.new(environment: {}, stdout: StringIO.new, stderr: StringIO.new, runner: process,
        retrospective_output: delivery).run([ "--worktree", directory, "--", prompt ])
      JSON.parse(delivery.string).fetch("reason")
    end
  end

  def delivery_boundary_observations
    read_pipe, write_pipe = IO.pipe
    pipe_process = runner(success("1.18.26\n"), enabled_config, success(primary_output), retrospective_response)
    pipe_status = described_class.new(environment: { "KOS_RETROSPECTIVE_FD" => write_pipe.fileno.to_s },
      stdout: StringIO.new, stderr: StringIO.new, runner: pipe_process).run([ "--worktree", directory, "--", "task" ])
    standard_process = runner(success("1.18.26\n"), enabled_config, success(primary_output), retrospective_response)
    standard_status = described_class.new(environment: { "KOS_RETROSPECTIVE_FD" => "1" }, stdout: StringIO.new,
      stderr: StringIO.new, runner: standard_process).run([ "--worktree", directory, "--", "task" ])
    blocked = Struct.new(:content) { def write_nonblock(*) = :wait_writable }.new("")
    blocked_process = runner(success("1.18.26\n"), enabled_config, success(primary_output), retrospective_response)
    blocked_status = described_class.new(environment: {}, stdout: StringIO.new, stderr: StringIO.new,
      runner: blocked_process, retrospective_output: blocked).run([ "--worktree", directory, "--", "task" ])
    raising = Object.new
    def raising.write_nonblock(*) = raise("delivery failed")
    raising_process = runner(success("1.18.26\n"), enabled_config, success(primary_output), retrospective_response)
    raising_status = described_class.new(environment: {}, stdout: StringIO.new, stderr: StringIO.new,
      runner: raising_process, retrospective_output: raising).run([ "--worktree", directory, "--", "task" ])
    [ pipe_status, read_pipe.read_nonblock(1, exception: false).to_s, standard_status, blocked_status, blocked.content,
      raising_status ]
  ensure
    read_pipe&.close
    write_pipe&.close
  end

  def failure_observations
    [ malformed_response, failed("provider failed"), timed_out ].map do |retrospective|
      output = StringIO.new
      delivery = StringIO.new
      process = runner(success("1.18.26\n"), enabled_config, success(primary_output), retrospective)
      described_class.new(environment: {}, stdout: output, stderr: StringIO.new, runner: process,
        retrospective_output: delivery).run([ "--worktree", directory, "--", "task" ])
      [ output.string, JSON.parse(delivery.string).fetch("reason") ]
    end
  end

  def malformed_response
    success("{\"type\":\"text\",\"sessionID\":\"ses_root\",\"part\":{\"type\":\"text\",\"text\":\"not json\",\"time\":{\"end\":1}}}\n")
  end


  def install_runtime(worktree)
    sources = described_class::MANAGED_RUNTIME_FILES
    sources.each do |path, source|
      destination = File.join(worktree, path)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(File.join(OpenCodeLauncherSpecSupport::ROOT, source), destination)
    end
    File.write(File.join(worktree, "opencode.json"), "{}\n")
    managed = sources.map do |path, source|
      { "path" => path, "source" => source,
        "digest" => "sha256:#{Digest::SHA256.file(File.join(worktree, path)).hexdigest}" }
    end
    source_bundle_digest = "sha256:#{Digest::SHA256.hexdigest(canonical_json(managed))}"
    manifest = { "schema_version" => "1", "kos_version" => "0.1.0", "cli_protocol_version" => "1",
      "runtime" => { "target" => "opencode", "version" => "1.18.26" },
      "repository" => { "worktree_root" => worktree, "git_common_dir" => File.join(worktree, ".git"),
        "task_prefix" => "KOS", "trusted_remote" => "origin",
        "trusted_remote_url" => "https://example.test/repository.git", "base_ref" => "refs/heads/main" },
      "repository_id" => "11111111-1111-4111-8111-111111111111", "source_bundle_digest" => source_bundle_digest,
      "capability_report_digest" => described_class::CAPABILITY_REPORT_DIGEST, "managed_files" => managed }
    File.write(File.join(worktree, ".opencode/kos-runtime-manifest.json"), JSON.generate(manifest))
  end

  def canonical_json(value)
    case value
    when Hash
      "{#{value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(',')}}"
    when Array then "[#{value.map { |item| canonical_json(item) }.join(',')}]"
    else JSON.generate(value)
    end
  end
end
