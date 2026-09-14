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
    verifier = described_class.new(executable: executable, staged_opencode: staged_opencode, timeout: 1)
    expect { verifier.call }.to raise_error(described_class::Incompatible, "OpenCode 1.18.26 is required")
  end

  it "terminates a timed-out runtime process group" do
    pid_path = File.join(directory, "runtime.pid")
    executable = write_executable(descendant_script(pid_path))
    verifier = described_class.new(executable: executable, staged_opencode: staged_opencode, timeout: 0.1)
    expect(timeout_result(verifier, pid_path)).to eq([ described_class::Incompatible, false ])
  end

  private

  def write_executable(body)
    path = File.join(directory, "opencode")
    File.write(path, "#!/usr/bin/env ruby\n#{body}\n")
    File.chmod(0o755, path)
    path
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
