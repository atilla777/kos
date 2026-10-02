require "minitest/autorun"
require "fileutils"
require "json"
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

      %w[kos-setup kos-orchestrator kos-executor kos-git kos-github-cli kos-project-docs kos-project-onboarding kos-task-worktree].each do |name|
        assert_equal File.binread(File.join(SOURCE, "skills", name, "SKILL.md")),
          File.binread(File.join(home, "opencode", "skills", name, "SKILL.md"))
      end
      %w[kos-standard kos-advanced].each do |name|
        assert_equal File.binread(File.join(SOURCE, "agent", "#{name}.md")),
          File.binread(File.join(home, "opencode", "agent", "#{name}.md"))
      end
      %w[kos-init kos-update kos kos-brief kos-fix].each do |name|
        assert_equal File.binread(File.join(SOURCE, "command", "#{name}.md")),
          File.binread(File.join(home, "opencode", "command", "#{name}.md"))
      end
      refute File.exist?(File.join(home, "opencode", "task-worktree.md"))
      refute File.exist?(File.join(home, "opencode", "project-onboarding.md"))
      refute File.exist?(File.join(home, "opencode", "agent", "kos-orchestrator.md"))
    end
  end

  def test_replaces_known_previous_kos_copy
    Dir.mktmpdir do |home|
      target = File.join(home, "opencode", "skills", "kos-setup", "SKILL.md")
      previous = previous_setup_skill
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite(target, previous)

      stdout, stderr, status = install(home)
      assert status.success?, stderr
      assert_includes stdout, "1 updated"
      assert_equal File.binread(File.join(SOURCE, "skills", "kos-setup", "SKILL.md")), File.binread(target)
    end
  end

  def test_check_distinguishes_outdated_and_missing_files_without_writing
    Dir.mktmpdir do |home|
      config = File.join(home, "opencode")
      target = File.join(config, "skills", "kos-setup", "SKILL.md")
      stdout, stderr, status = install(home, "--check")
      refute status.success?
      assert_empty stdout
      assert_includes stderr, "skills/kos-setup/SKILL.md: missing"
      refute File.exist?(config)

      assert install(home).last.success?
      File.binwrite(target, previous_setup_skill)
      before = File.binread(target)
      stdout, stderr, status = install(home, "--check")
      refute status.success?
      assert_empty stdout
      assert_includes stderr, "skills/kos-setup/SKILL.md: differs from checkout"
      assert_equal before, File.binread(target)

      assert install(home).last.success?
      stdout, stderr, status = install(home, "--check")
      assert status.success?, stderr
      assert_includes stdout, "cannot inspect a running session"
    end
  end

  def test_installed_skills_contain_both_procedures_without_external_file_references
    Dir.mktmpdir do |home|
      assert install(home).last.success?
      config = File.join(home, "opencode")
      onboarding = File.read(File.join(config, "skills", "kos-project-onboarding", "SKILL.md"))
      worktree = File.read(File.join(config, "skills", "kos-task-worktree", "SKILL.md"))
      assert_includes onboarding, "## Details and recovery"
      assert_includes onboarding, "**separate explicit approvals**"
      assert_includes worktree, "## Prepare or recover"
      assert_includes worktree, "## Publish and clean up"

      Dir.glob(File.join(config, "{skills,command,agent}", "**", "*.md")).each do |path|
        refute_match %r{(?:\.\./)*\.\./(?:project-onboarding|task-worktree)\.md}, File.read(path), path
      end
    end
  end

  def test_update_preserves_legacy_standalone_files
    Dir.mktmpdir do |home|
      config = File.join(home, "opencode")
      FileUtils.mkdir_p(config)
      %w[project-onboarding.md task-worktree.md].each do |name|
        File.write(File.join(config, name), "existing local file")
      end

      assert install(home).last.success?
      %w[project-onboarding.md task-worktree.md].each do |name|
        assert_equal "existing local file", File.read(File.join(config, name))
      end
    end
  end

  def test_modified_previous_copy_stops_before_updating_or_copying
    Dir.mktmpdir do |home|
      target = File.join(home, "opencode", "skills", "kos-setup", "SKILL.md")
      previous = previous_setup_skill
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite(target, "#{previous}\nuser edit\n")

      _stdout, stderr, status = install(home)
      refute status.success?
      assert_includes stderr, "not a known previous KOS copy"
      assert_equal "#{previous}\nuser edit\n", File.binread(target)
      refute File.exist?(File.join(home, "opencode", "command", "kos-update.md"))
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

  def test_conflicting_new_skill_stops_before_copying_other_files
    Dir.mktmpdir do |home|
      target = File.join(home, "opencode", "skills", "kos-github-cli", "SKILL.md")
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "my own skill")

      _stdout, stderr, status = install(home)
      refute status.success?
      assert_includes stderr, "existing file differs"
      assert_equal "my own skill", File.read(target)
      refute File.exist?(File.join(home, "opencode", "skills", "kos-git", "SKILL.md"))
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
      skill_names = %w[kos-setup kos-orchestrator kos-executor kos-git kos-github-cli kos-project-docs kos-project-onboarding kos-task-worktree]
      # The debug listing includes skill bodies and may be truncated before all names appear.
      missing = skill_names.reject { |name| skills.include?(%Q("name": "#{name}")) }
      missing.each do |name|
        Dir.mktmpdir do |isolated_home|
          assert install(isolated_home).last.success?
          Dir.glob(File.join(isolated_home, "opencode", "skills", "*")).each do |path|
            FileUtils.rm_rf(path) unless File.basename(path) == name
          end
          isolated, error, status = Open3.capture3({ "XDG_CONFIG_HOME" => isolated_home, "OPENCODE_PURE" => "1" },
            "opencode", "debug", "skill", chdir: isolated_home)
          assert status.success?, error
          assert_includes isolated, %Q("name": "#{name}")
        end
      end

      commands, error, status = Open3.capture3(env, "opencode", "debug", "config", chdir: home)
      assert status.success?, error
      %w[kos-init kos-update kos kos-brief kos-fix].each { |name| assert_includes commands, %Q("#{name}") }
      %w[kos-brief kos-fix].each do |name|
        template = JSON.parse(commands).fetch("command").fetch(name).fetch("template")
        assert_includes template, "kos-orchestrator"
        assert_includes template, "$ARGUMENTS"
      end

      %w[kos-standard kos-advanced].zip(%w[gpt-6-luna gpt-6-sol]).each do |name, model|
        details, error, status = Open3.capture3(env, "opencode", "debug", "agent", name, chdir: home)
        assert status.success?, error
        assert_includes details, model
      end
    end
  end

  def test_updated_skill_is_discoverable_in_a_fresh_opencode_process
    skip "OpenCode executable is not installed" unless ENV.fetch("PATH").split(File::PATH_SEPARATOR).any? { |path| File.executable?(File.join(path, "opencode")) }

    Dir.mktmpdir do |home|
      target = File.join(home, "opencode", "skills", "kos-orchestrator", "SKILL.md")
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite(target, previous_orchestrator_skill)
      assert install(home).last.success?
      assert install(home, "--check").last.success?

      skills, error, status = Open3.capture3({ "XDG_CONFIG_HOME" => home, "OPENCODE_PURE" => "1" },
        "opencode", "debug", "skill", chdir: home)
      assert status.success?, error
      assert_includes skills, '"name": "kos-orchestrator"'
      assert_includes skills, "KOS Brief v7"
    end
  end

  private

  def previous_setup_skill
    relative = "integrations/opencode/skills/kos-setup/SKILL.md"
    commits, error, status = Open3.capture3("git", "log", "--format=%H", "HEAD", "--", relative, chdir: ROOT)
    assert status.success?, error
    commits.each_line do |commit|
      old, _error, result = Open3.capture3("git", "show", "#{commit.strip}:#{relative}", chdir: ROOT)
      return old if result.success? && old != File.binread(File.join(SOURCE, "skills", "kos-setup", "SKILL.md"))
    end
    flunk "No previous KOS setup skill revision found"
  end

  def previous_orchestrator_skill
    relative = "integrations/opencode/skills/kos-orchestrator/SKILL.md"
    commits, error, status = Open3.capture3("git", "log", "--format=%H", "HEAD", "--", relative, chdir: ROOT)
    assert status.success?, error
    commits.each_line do |commit|
      old, _error, result = Open3.capture3("git", "show", "#{commit.strip}:#{relative}", chdir: ROOT)
      return old if result.success? && old.include?("KOS Brief v5") && !old.include?("KOS Brief v6")
    end
    flunk "No previous v5 orchestrator revision found"
  end

  def install(home, *args)
    Open3.capture3({ "XDG_CONFIG_HOME" => home }, "ruby", File.join(ROOT, "script", "install-opencode"), *args)
  end
end
