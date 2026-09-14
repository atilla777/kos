require "fileutils"
require "tmpdir"
require "spec_helper"
require_relative "../../../../../lib/kos/runtime/open_code/capability_verifier"

RSpec.describe Kos::Runtime::OpenCode::CapabilityVerifier do
  around do |example|
    Dir.mktmpdir("kos-capability-verifier-spec-") do |directory|
      example.metadata[:directory] = directory
      example.run
    end
  end

  let(:directory) { RSpec.current_example.metadata.fetch(:directory) }
  let(:staged_opencode) { File.join(directory, ".opencode") }

  before { FileUtils.mkdir_p(staged_opencode) }

  it "provides a deterministic closed compatible report and digest" do
    report = described_class.expected_report
    results = [ Kos::Runtime::OpenCode::Transport.schema.ref("#/$defs/capability_report").valid?(report),
      described_class.report_digest(report) == described_class.report_digest ]
    expect(results).to all(be(true))
  end

  it "rejects another runtime version" do
    executable = write_executable("puts '1.18.27'")
    verifier = described_class.new(executable: executable, launcher_executable: executable,
      staged_opencode: staged_opencode, timeout: 1)
    expect { verifier.call }.to raise_error(described_class::Incompatible, "OpenCode 1.18.26 is required")
  end

  it "terminates a timed-out runtime process group" do
    pid_path = File.join(directory, "runtime.pid")
    executable = write_executable(descendant_script(pid_path))
    verifier = described_class.new(executable: executable, launcher_executable: executable,
      staged_opencode: staged_opencode, timeout: 0.1)
    expect(timeout_result(verifier, pid_path)).to eq([ described_class::Incompatible, false ])
  end

  it "rejects every extra enabled built-in or custom agent tool" do
    extras = %w[webfetch read write patch question rogue_runtime_tool]
    expect(extras.map { |tool| extra_tool_rejected?(tool) }).to all(be(true))
  end

  it "rejects malformed agent identity, mode, authority, and retrospective procedure directly" do
    expect(%i[identity mode authority procedure].map { |failure| agent_contract_rejected?(failure) }).to all(be(true))
  end

  it "does not copy a repository-bound manifest into a temporary capability worktree" do
    File.write(File.join(staged_opencode, "kos-runtime-manifest.json"), "repository-bound\n")
    verifier = described_class.new(executable: "opencode", launcher_executable: "kos-opencode",
      staged_opencode: staged_opencode)
    project = verifier.send(:prepare_project, directory, "pre-manifest", "http://127.0.0.1:1", read_only: false)

    expect(File.exist?(File.join(project, ".opencode", "kos-runtime-manifest.json"))).to be(false)
  end

  private

  def write_executable(body)
    path = File.join(directory, "opencode")
    File.write(path, "#!/usr/bin/env ruby\n#{body}\n")
    File.chmod(0o755, path)
    path
  end

  def extra_tool_rejected?(tool)
    contract = described_class::AGENT_CONTRACTS.fetch("kos-orchestrate")
    enabled = described_class::AGENT_ENABLED_TOOLS.fetch("kos-orchestrate")
    tools = (enabled + %w[webfetch read write patch question rogue_runtime_tool]).uniq.to_h do |name|
      [ name, enabled.include?(name) ]
    end
    tools[tool] = true
    permissions = contract.fetch("permissions").map do |permission, pattern, action|
      { "permission" => permission, "pattern" => pattern, "action" => action }
    end
    permissions << { "permission" => tool, "pattern" => "*", "action" => "allow" }
    definition = { "name" => "kos-orchestrate", "mode" => "primary", "tools" => tools,
      "permission" => permissions }
    verifier = described_class.allocate
    verifier.send(:verify_agent_definition!, "kos-orchestrate", definition)
    false
  rescue described_class::Incompatible
    true
  end

  def agent_contract_rejected?(failure)
    name = failure == :procedure ? "kos-retrospective" : "kos-orchestrate"
    contract = described_class::AGENT_CONTRACTS.fetch(name)
    enabled = described_class::AGENT_ENABLED_TOOLS.fetch(name)
    definition = { "name" => name, "mode" => contract.fetch("mode"),
      "tools" => enabled.to_h { |tool| [ tool, true ] },
      "permission" => contract.fetch("permissions").map do |permission, pattern, action|
        { "permission" => permission, "pattern" => pattern, "action" => action }
      end,
      "prompt" => described_class::RETROSPECTIVE_PROCEDURE_MARKERS.join("\n") }
    definition["name"] = "other" if failure == :identity
    definition["mode"] = "invalid" if failure == :mode
    definition["permission"] << { "permission" => "*", "pattern" => "*", "action" => "allow" } if
      failure == :authority
    definition["prompt"] = "incomplete" if failure == :procedure
    described_class.allocate.send(:verify_agent_definition!, name, definition)
    false
  rescue described_class::Incompatible
    true
  end

  def timeout_result(verifier, pid_path)
    error_class = begin
      verifier.call
      nil
    rescue described_class::Incompatible => error
      error.class
    end
    pid = Integer(File.read(pid_path), 10)
    alive = begin
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end
    [ error_class, alive ]
  end

  def descendant_script(pid_path)
    "r,w=IO.pipe; fork { r.close; File.write(#{pid_path.inspect}, Process.pid); w.write('x'); sleep 30 }; " \
      "w.close; r.read(1); exit! 0"
  end
end
