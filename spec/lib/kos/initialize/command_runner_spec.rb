require "rbconfig"
require "tmpdir"
require "spec_helper"
require_relative "../../../../lib/kos/initialize"

RSpec.describe Kos::Initialize::CommandRunner do
  around do |example|
    Dir.mktmpdir("kos-command-runner-spec-") do |directory|
      example.metadata[:directory] = directory
      example.run
    end
  end

  let(:directory) { RSpec.current_example.metadata.fetch(:directory) }

  it "returns bounded output for a completed subprocess" do
    result = described_class.new(timeout: 1).capture(RbConfig.ruby, "-e", "puts 'ok'", chdir: directory)
    expect([ result.stdout, result.status.success?, result.timed_out ]).to eq([ "ok\n", true, false ])
  end

  it "kills descendants that retain output pipes after their parent exits" do
    pid_path = File.join(directory, "child.pid")
    script = descendant_script(pid_path)
    result = described_class.new(timeout: 0.1).capture(RbConfig.ruby, "-e", script, chdir: directory)
    sleep(0.05)
    expect([ result.timed_out, process_alive?(Integer(File.read(pid_path), 10)) ]).to eq([ true, false ])
  end

  private

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def descendant_script(pid_path)
    "r,w=IO.pipe; fork { r.close; File.write(#{pid_path.inspect}, Process.pid); w.write('x'); sleep 30 }; " \
      "w.close; r.read(1); exit! 0"
  end
end
