require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"

class InstallOpencodeTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SOURCE = File.join(ROOT, "integrations", "opencode")

  def test_installs_global_executors_and_skills_and_is_idempotent
    Dir.mktmpdir do |home|
      2.times do
        stdout, stderr, status = install(home)
        assert status.success?, stderr
        assert_includes stdout, "Restart OpenCode"
      end

      %w[kos-setup kos-orchestrator kos-executor].each do |name|
        assert_equal File.binread(File.join(SOURCE, "skills", name, "SKILL.md")),
          File.binread(File.join(home, "opencode", "skills", name, "SKILL.md"))
      end
      %w[kos-standard kos-advanced].each do |name|
        assert_equal File.binread(File.join(SOURCE, "agent", "#{name}.md")),
          File.binread(File.join(home, "opencode", "agent", "#{name}.md"))
      end
      refute File.exist?(File.join(home, "opencode", "agent", "kos-orchestrator.md"))
    end
  end

  def test_existing_different_file_stops_before_any_copy
    Dir.mktmpdir do |home|
      target = File.join(home, "opencode", "agent", "kos-standard.md")
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "user's agent")

      _stdout, stderr, status = install(home)
      refute status.success?
      assert_includes stderr, "existing file differs"
      assert_equal "user's agent", File.read(target)
      refute File.exist?(File.join(home, "opencode", "agent", "kos-advanced.md"))
    end
  end

  def test_opencode_discovers_agents_and_skills_when_available
    skip "OpenCode executable is not installed" unless ENV.fetch("PATH").split(File::PATH_SEPARATOR).any? { |path| File.executable?(File.join(path, "opencode")) }

    Dir.mktmpdir do |home|
      assert install(home).last.success?
      env = { "XDG_CONFIG_HOME" => home, "OPENCODE_PURE" => "1" }
      agents, error, status = Open3.capture3(env, "opencode", "agent", "list", chdir: home)
      assert status.success?, error
      %w[kos-standard kos-advanced].each { |name| assert_includes agents, name }
      refute_match(/^kos-orchestrator \(/, agents)

      skills, error, status = Open3.capture3(env, "opencode", "debug", "skill", chdir: home)
      assert status.success?, error
      %w[kos-setup kos-orchestrator kos-executor].each { |name| assert_includes skills, name }

      %w[kos-standard kos-advanced].zip(%w[gpt-6-luna gpt-6-sol]).each do |name, model|
        details, error, status = Open3.capture3(env, "opencode", "debug", "agent", name, chdir: home)
        assert status.success?, error
        assert_includes details, model
      end
    end
  end

  private

  def install(home)
    Open3.capture3({ "XDG_CONFIG_HOME" => home }, "ruby", File.join(ROOT, "script", "install-opencode"))
  end
end
