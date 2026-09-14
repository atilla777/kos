require "fileutils"
require "json"
require "open3"
require "stringio"
require "tmpdir"
require "spec_helper"
require_relative "../../../../lib/kos/initialize"

module KosInitializeApplicationFixture
  ROOT = File.expand_path("../../../..", __dir__)
  WORKFLOW_ID = "11111111-1111-4111-8111-111111111111"
  REPOSITORY_ID = "22222222-2222-4222-8222-222222222222"
  DIGEST = "sha256:#{'a' * 64}"
end

RSpec.describe Kos::Initialize::Application do
  around do |example|
    Dir.mktmpdir("kos-initialize-spec-") do |directory|
      example.metadata[:directory] = directory
      example.run
    end
  end

  let(:directory) { RSpec.current_example.metadata.fetch(:directory) }
  let(:repository) { File.join(directory, "project") }
  let(:remote) { File.join(directory, "remote.git") }
  let(:test_bin) { File.join(directory, "bin") }

  let(:request) do
    {
      "schema_version" => "1", "task_prefix" => "KOS", "trusted_remote" => "origin",
      "base_ref" => "refs/heads/main", "registration_idempotency_key" => "initialize-spec-1",
      "runtime" => { "target" => "opencode", "version" => "1.18.26" }
    }
  end

  before { prepare_repository }

  it "plans deterministically from a nested worktree and normalizes an scp-like remote" do
    expect(plan_contract_results).to all(be_truthy)
  end

  it "requires kos, kos-repository, and kos-opencode to be executable on PATH" do
    expect(required_executable_results).to all(eq([ "executable_unavailable", true ]))
  end

  it "applies copied files, publishes the manifest last, and then plans unchanged" do
    expect(apply_contract_results).to all(be_truthy)
  end

  it "passes the staged capability probe with pinned OpenCode 1.18.26" do
    File.unlink(File.join(test_bin, "opencode"))
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    result = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json",
      real_capability: true)
    expect(result.fetch(:status)).to eq(0), result.fetch(:stderr)
  end

  it "treats an unmanaged byte-identical file as a conflict requiring force" do
    expect(unmanaged_collision_results)
      .to eq([ { "action" => "conflict", "observed" => "unmanaged" }, "force_required" ])
  end

  it "reports changed and missing owned files as drift" do
    expect(drift_results).to eq(%w[drifted missing force_required])
  end

  it "plans the previous nine-file bundle as an explicitly approved managed upgrade" do
    expect(previous_bundle_upgrade_results)
      .to eq(%w[create update managed_previous capability_changed force_required])
  end

  it "rejects symlink ancestry and malformed manifests" do
    expect(unsafe_ancestry_results).to eq(%w[unsafe_destination manifest_invalid])
  end

  it "rejects stale approval and a managed symlink even with force" do
    expect(stale_and_symlink_results)
      .to eq([ "plan_changed", { "action" => "conflict", "observed" => "symlink" },
      "unsafe_destination" ])
  end

  it "rolls back files published before an injected failure" do
    expect(rollback_results).to eq([ "injected_failure", false, false ])
  end

  it "rejects an ancestry replacement before descriptor-relative publication" do
    expect(ancestry_race_results).to eq([ "unsafe_destination", false ])
  end

  it "does not follow replaced ancestry during retained-descriptor rollback" do
    expect(rollback_ancestry_race_results).to eq([ "rollback_incomplete", false ])
  end

  it "binds and reverifies manifest bytes and registration identity" do
    expect(manifest_binding_results).to eq(%w[destination_changed manifest_invalid])
  end

  it "rejects inconsistent manifest inventory and bound digests" do
    expect(manifest_consistency_results).to eq(%w[manifest_invalid manifest_invalid manifest_invalid])
  end

  it "restores overwritten bytes and mode through retained parent descriptors" do
    expect(mode_rollback_results).to eq([ "injected_failure", "original\n", 0o750 ])
  end

  it "reports rollback_incomplete when a retained-descriptor restore fails" do
    expect(incomplete_rollback_result).to eq("rollback_incomplete")
  end

  it "retains a complete installed copy after its independent source bundle is removed" do
    expect(installed_copy_result).to be(true)
  end

  it "rejects a staged profile that real OpenCode resolves with excess authority" do
    expect(capability_rejection_result).to eq([ "capability_failed", false ])
  end

  it "does not follow an .opencode replacement during stage creation" do
    expect(stage_creation_race_results).to eq([ "destination_changed", false, [] ])
  end

  it "retains a private descriptor-backed stage through capability verification" do
    expect(descriptor_stage_results).to eq([ true, 0o700, [] ])
  end

  it "rechecks staged digests after executable capability verification" do
    expect(capability_mutation_result).to eq([ "staging_failed", false, [] ])
  end

  it "aborts on an intermediate destination directory fsync fault" do
    expect(directory_fsync_fault_results).to eq([ "injected_fsync_failure", false, [] ])
  end

  private

  def invoke(*arguments, failure_injector: nil, real_capability: false, capability_verifier_factory: nil,
    source_root: KosInitializeApplicationFixture::ROOT)
    stdout = StringIO.new
    stderr = StringIO.new
    environment = { "PATH" => "#{test_bin}:#{ENV.fetch('PATH')}" }
    factory = capability_verifier_factory
    unless factory || real_capability
      factory = lambda do |**_arguments|
        Struct.new(:call).new(Kos::Runtime::OpenCode::CapabilityVerifier.expected_report)
      end
    end
    installer = Kos::Initialize::Installer.new(cwd: File.join(repository, "nested/deeper"), environment: environment,
      failure_injector: failure_injector, capability_verifier_factory: factory, source_root: source_root)
    status = described_class.new(arguments, stdin: StringIO.new(JSON.generate(request)), stdout: stdout, stderr: stderr,
      installer: installer).run
    { status: status, document: JSON.parse(stdout.string), stderr: stderr.string }
  end

  def apply_clean_install
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    result = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json")
    raise result.inspect unless result.fetch(:status).zero?
  end

  def required_executable_results
    %w[kos kos-repository kos-opencode].map do |name|
      path = File.join(test_bin, name)
      mode = File.stat(path).mode & 0o777
      File.chmod(0o644, path)
      result = invoke("plan", "--input", "-", "--json")
      File.chmod(mode, path)
      [ result.dig(:document, "error", "code"), result.fetch(:stderr).include?(name) ]
    end
  end

  def write_executables
    write_executable("kos", <<~RUBY)
      #!/usr/bin/env ruby
      require "json"
      workflow_id = "#{KosInitializeApplicationFixture::WORKFLOW_ID}"
      repository_id = "#{KosInitializeApplicationFixture::REPOSITORY_ID}"
      command = ARGV.first(2)
      data = case command
      when ["task-type", "list"]
        {"task_types" => [{"name" => "quick-fix", "current_workflow_version_id" => workflow_id}]}
      when ["workflow", "get"]
        {"id" => workflow_id, "task_type" => "quick-fix", "version" => "1.0.0",
         "content_digest" => "#{KosInitializeApplicationFixture::DIGEST}", "definition" => {"workflow_id" => "quick-fix"}}
      when ["repository", "register"]
        JSON.parse(STDIN.read).merge("id" => repository_id)
      else
        abort "unexpected command"
      end
      identifier = { ["task-type", "list"] => "task_type.list", ["workflow", "get"] => "workflow.get",
                     ["repository", "register"] => "repository.register" }.fetch(command)
      puts JSON.generate("schema_version" => "1", "command" => identifier, "data" => data)
    RUBY
    write_executable("kos-repository", "#!/usr/bin/env ruby\nexit 0\n")
    write_executable("kos-opencode", <<~RUBY)
      #!/usr/bin/env ruby
      exec #{File.join(KosInitializeApplicationFixture::ROOT, "bin/kos-opencode").inspect}, *ARGV
    RUBY
    write_executable("opencode", <<~RUBY)
      #!/usr/bin/env ruby
      require "json"
      if ARGV == ["--version"]
        puts "1.18.26"
      elsif ARGV == ["debug", "skill"]
        names = %w[kos-cli kos-initialize kos-orchestrate kos-repository kos-retrospective kos-workflow-step]
        puts JSON.generate(names.map { |name| {"name" => name} })
      elsif ARGV.first(2) == ["debug", "agent"]
        puts JSON.generate("name" => ARGV.fetch(2), "permission" => {"*" => "deny"})
      else
        abort "unexpected OpenCode command"
      end
    RUBY
  end

  def write_executable(name, content)
    path = File.join(test_bin, name)
    File.write(path, content)
    File.chmod(0o755, path)
  end

  def run(*command, chdir:)
    _stdout, stderr, status = Open3.capture3(*command, chdir: chdir)
    raise stderr unless status.success?
  end

  def prepare_repository
    FileUtils.mkdir_p([ repository, test_bin ])
    run("git", "init", "--bare", "--quiet", remote, chdir: directory)
    run("git", "init", "--quiet", "--initial-branch=main", repository, chdir: directory)
    File.write(File.join(repository, "README"), "fixture\n")
    run("git", "add", "README", chdir: repository)
    run("git", "-c", "user.name=KOS", "-c", "user.email=kos@example.test", "commit", "--quiet", "-m", "fixture",
      chdir: repository)
    run("git", "remote", "add", "origin", "git@example.test:team/project.git", chdir: repository)
    write_executables
    FileUtils.mkdir_p(File.join(repository, "nested", "deeper"))
  end

  def plan_contract_results
    first = invoke("plan", "--input", "-", "--json")
    second = invoke("plan", "--input", "-", "--json")
    plan = first.fetch(:document)
    [ first.fetch(:status).zero?, second.fetch(:document) == plan,
      plan.dig("repository", "worktree_root") == File.realpath(repository),
      plan.dig("repository", "git_common_dir") == File.realpath(File.join(repository, ".git")),
      plan.dig("repository", "trusted_remote_url") == "ssh://git@example.test/team/project.git",
      plan.dig("readiness", "launcher_executable") == File.realpath(File.join(test_bin, "kos-opencode")),
      plan.fetch("managed_files").map { |file| file.fetch("action") }.uniq == [ "create" ],
      plan.fetch("managed_files").length == 10,
      plan.fetch("managed_files").any? { |file| file.fetch("path") == ".opencode/agents/kos-retrospective.md" } ]
  end

  def apply_contract_results
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    result = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json")
    manifest = JSON.parse(File.read(File.join(repository, ".opencode/kos-runtime-manifest.json")))
    copied = manifest.fetch("managed_files").all? do |file|
      installed = File.join(repository, file.fetch("path"))
      File.file?(installed) && !File.symlink?(installed)
    end
    repeated = invoke("plan", "--input", "-", "--json").fetch(:document)
    no_op = invoke("apply", "--input", "-", "--approved-plan", repeated.fetch("plan_digest"), "--json")
    [ result.fetch(:status).zero?, manifest.fetch("repository_id") == KosInitializeApplicationFixture::REPOSITORY_ID,
      manifest.fetch("kos_version") == "0.1.0", manifest.fetch("managed_files").length == 10, copied,
      repeated.fetch("managed_files").all? { |file| file.fetch("action") == "unchanged" },
      no_op.dig(:document, "published_files") == [] ]
  end

  def unmanaged_collision_results
    target = File.join(repository, ".opencode/skills/kos-cli/SKILL.md")
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp(File.join(KosInitializeApplicationFixture::ROOT, "skills/kos-cli/SKILL.md"), target)
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    collision = plan.fetch("managed_files").find { |file| file.fetch("path").include?("kos-cli") }
    rejected = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json")
    [ collision.slice("action", "observed"), rejected.dig(:document, "error", "code") ]
  end

  def drift_results
    apply_clean_install
    File.write(File.join(repository, ".opencode/skills/kos-cli/SKILL.md"), "changed\n")
    File.unlink(File.join(repository, ".opencode/skills/kos-repository/SKILL.md"))
    files = invoke("plan", "--input", "-", "--json").dig(:document, "managed_files")
    observations = files.to_h { |file| [ file.fetch("path"), file.fetch("observed") ] }
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    rejected = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json")
    [ *observations.values_at(".opencode/skills/kos-cli/SKILL.md",
      ".opencode/skills/kos-repository/SKILL.md"), rejected.dig(:document, "error", "code") ]
  end

  def unsafe_ancestry_results
    File.symlink(directory, File.join(repository, ".opencode"))
    symlink = invoke("plan", "--input", "-", "--json")
    File.unlink(File.join(repository, ".opencode"))
    FileUtils.mkdir_p(File.join(repository, ".opencode"))
    File.write(File.join(repository, ".opencode/kos-runtime-manifest.json"), '{"schema_version":"2"}')
    malformed = invoke("plan", "--input", "-", "--json")
    [ symlink, malformed ].map { |result| result.dig(:document, "error", "code") }
  end

  def previous_bundle_upgrade_results
    apply_clean_install
    manifest_path = File.join(repository, ".opencode/kos-runtime-manifest.json")
    manifest = JSON.parse(File.read(manifest_path))
    agent = ".opencode/agents/kos-retrospective.md"
    plugin = ".opencode/plugins/kos-session-guard.js"
    manifest.fetch("managed_files").reject! { |file| file.fetch("path") == agent }
    legacy = "legacy session guard\n"
    File.write(File.join(repository, plugin), legacy)
    manifest.fetch("managed_files").find { |file| file.fetch("path") == plugin }["digest"] =
      "sha256:#{Digest::SHA256.hexdigest(legacy)}"
    manifest["source_bundle_digest"] = Kos::Initialize::CanonicalJson.digest(manifest.fetch("managed_files"))
    manifest["capability_report_digest"] = Kos::Initialize::Installer::PREVIOUS_CAPABILITY_REPORT_DIGEST
    File.write(manifest_path, JSON.generate(manifest))
    File.unlink(File.join(repository, agent))

    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    files = plan.fetch("managed_files").to_h { |file| [ file.fetch("path"), file ] }
    rejected = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json")
    [ files.fetch(agent).fetch("action"), files.fetch(plugin).fetch("action"),
      files.fetch(plugin).fetch("observed"),
      plan.dig("readiness", "capability_report_digest") == manifest.fetch("capability_report_digest") ?
        "capability_unchanged" : "capability_changed", rejected.dig(:document, "error", "code") ]
  end

  def stale_and_symlink_results
    stale = invoke("apply", "--input", "-", "--approved-plan", "sha256:#{'f' * 64}", "--json")
    target = File.join(repository, ".opencode/skills/kos-cli/SKILL.md")
    FileUtils.mkdir_p(File.dirname(target))
    File.symlink(File.join(KosInitializeApplicationFixture::ROOT, "skills/kos-cli/SKILL.md"), target)
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    conflict = plan.fetch("managed_files").find { |file| file.fetch("path").include?("kos-cli") }
    rejected = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--force", "--json")
    [ stale.dig(:document, "error", "code"), conflict.slice("action", "observed"),
      rejected.dig(:document, "error", "code") ]
  end

  def rollback_results
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    injector = lambda do |path|
      raise Kos::Initialize::Error.new("injected_failure", "Injected publication failure") if
        path == ".opencode/skills/kos-orchestrate/SKILL.md"
    end
    failed = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json",
      failure_injector: injector)
    paths = %w[.opencode/skills/kos-cli/SKILL.md .opencode/kos-runtime-manifest.json]
    [ failed.dig(:document, "error", "code"), *paths.map { |path| File.exist?(File.join(repository, path)) } ]
  end

  def ancestry_race_results
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    outside = File.join(directory, "outside")
    FileUtils.mkdir_p(outside)
    injector = lambda do |path|
      File.symlink(outside, File.join(repository, ".opencode/skills")) if
        path == ".opencode/skills/kos-cli/SKILL.md"
    end
    result = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json",
      failure_injector: injector)
    [ result.dig(:document, "error", "code"), File.exist?(File.join(outside, "kos-cli/SKILL.md")) ]
  end

  def rollback_ancestry_race_results
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    outside = File.join(directory, "outside")
    held = File.join(repository, ".opencode/held-skills")
    FileUtils.mkdir_p(outside)
    injector = lambda do |path|
      next unless path == ".opencode/skills/kos-initialize/SKILL.md"

      File.rename(File.join(repository, ".opencode/skills"), held)
      File.symlink(outside, File.join(repository, ".opencode/skills"))
    end
    result = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json",
      failure_injector: injector)
    [ result.dig(:document, "error", "code"), File.exist?(File.join(outside, "kos-cli/SKILL.md")) ]
  end

  def manifest_binding_results
    apply_clean_install
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    manifest_path = File.join(repository, ".opencode/kos-runtime-manifest.json")
    injector = ->(path) { File.write(manifest_path, "\n", mode: "a") if path == "before_destination_revalidation" }
    changed = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json",
      failure_injector: injector)
    write_registration_id("33333333-3333-4333-8333-333333333333")
    mismatched = invoke("apply", "--input", "-", "--approved-plan",
      invoke("plan", "--input", "-", "--json").dig(:document, "plan_digest"), "--json", "--force")
    [ changed, mismatched ].map { |result| result.dig(:document, "error", "code") }
  end

  def mode_rollback_results
    target = File.join(repository, ".opencode/skills/kos-cli/SKILL.md")
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "original\n")
    File.chmod(0o750, target)
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    injector = lambda do |path|
      raise Kos::Initialize::Error.new("injected_failure", "Injected") if
        path == ".opencode/skills/kos-initialize/SKILL.md"
    end
    result = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--force", "--json",
      failure_injector: injector)
    [ result.dig(:document, "error", "code"), File.binread(target), File.stat(target).mode & 0o777 ]
  end

  def incomplete_rollback_result
    target = File.join(repository, ".opencode/skills/kos-cli/SKILL.md")
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "original\n")
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    injector = lambda do |path|
      raise Kos::Initialize::Error.new("injected_failure", "Injected") if
        path == ".opencode/skills/kos-initialize/SKILL.md" || path.start_with?("rollback:")
    end
    result = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--force", "--json",
      failure_injector: injector)
    result.dig(:document, "error", "code")
  end

  def installed_copy_result
    source = copy_source_bundle("independent-source")
    plan = invoke("plan", "--input", "-", "--json", source_root: source).fetch(:document)
    result = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json",
      source_root: source)
    FileUtils.rm_rf(source)
    manifest = JSON.parse(File.read(File.join(repository, ".opencode/kos-runtime-manifest.json")))
    installed = manifest.fetch("managed_files").all? do |entry|
      File.file?(File.join(repository, entry.fetch("path")))
    end
    result.fetch(:status).zero? && !File.exist?(source) && installed && installed_bundle_compatible?
  end

  def capability_rejection_result
    source = copy_source_bundle("permissive-source")
    profile = File.join(source, "runtime/opencode/agents/kos-orchestrate.md")
    File.write(profile, File.read(profile).sub('"*": deny', '"*": allow'))
    File.unlink(File.join(test_bin, "opencode"))
    plan = invoke("plan", "--input", "-", "--json", source_root: source).fetch(:document)
    result = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json",
      source_root: source, real_capability: true)
    [ result.dig(:document, "error", "code"), File.exist?(File.join(repository, ".opencode/agents/kos-orchestrate.md")) ]
  end

  def installed_bundle_compatible?
    verifier = Kos::Runtime::OpenCode::CapabilityVerifier.new(executable: real_opencode,
      launcher_executable: File.join(test_bin, "kos-opencode"), staged_opencode: File.join(repository, ".opencode"))
    check_root = File.join(directory, "installed-check")
    FileUtils.mkdir_p(check_root)
    verifier.send(:verify_installed_bundle, check_root)
    true
  end

  def stage_creation_race_results
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    outside = File.join(directory, "stage-outside")
    held = File.join(repository, ".opencode-held")
    FileUtils.mkdir_p(outside)
    injector = lambda do |event|
      next unless event == "during_stage_creation"

      File.rename(File.join(repository, ".opencode"), held)
      File.symlink(outside, File.join(repository, ".opencode"))
    end
    result = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json",
      failure_injector: injector)
    [ result.dig(:document, "error", "code"), File.exist?(File.join(outside, ".opencode")),
      Dir.glob(File.join(outside, ".kos-stage-*")) ]
  end

  def descriptor_stage_results
    observed = {}
    factory = lambda do |staged_opencode:, **_arguments|
      stage = File.dirname(staged_opencode)
      observed[:proc_path] = stage.start_with?("/proc/self/fd/")
      observed[:mode] = File.stat(stage).mode & 0o777
      Struct.new(:call).new(Kos::Runtime::OpenCode::CapabilityVerifier.expected_report)
    end
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    result = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json",
      capability_verifier_factory: factory)
    [ result.fetch(:status).zero? && observed.fetch(:proc_path), observed.fetch(:mode), stage_entries ]
  end

  def capability_mutation_result
    factory = lambda do |staged_opencode:, **_arguments|
      verifier = lambda do
        File.write(File.join(staged_opencode, "skills/kos-cli/SKILL.md"), "mutated\n")
        Kos::Runtime::OpenCode::CapabilityVerifier.expected_report
      end
      Object.new.tap { |object| object.define_singleton_method(:call, &verifier) }
    end
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    result = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json",
      capability_verifier_factory: factory)
    [ result.dig(:document, "error", "code"),
      File.exist?(File.join(repository, ".opencode/skills/kos-cli/SKILL.md")), stage_entries ]
  end

  def directory_fsync_fault_results
    count = 0
    injector = lambda do |event|
      next unless event == "fsync:#{File.join(repository, '.opencode')}"

      count += 1
      raise Kos::Initialize::Error.new("injected_fsync_failure", "Injected fsync failure") if count == 2
    end
    plan = invoke("plan", "--input", "-", "--json").fetch(:document)
    result = invoke("apply", "--input", "-", "--approved-plan", plan.fetch("plan_digest"), "--json",
      failure_injector: injector)
    [ result.dig(:document, "error", "code"),
      File.exist?(File.join(repository, ".opencode/skills/kos-cli/SKILL.md")), stage_entries ]
  end

  def stage_entries
    Dir.glob(File.join(repository, ".opencode/.kos-stage-*"))
  end

  def manifest_consistency_results
    apply_clean_install
    path = File.join(repository, ".opencode/kos-runtime-manifest.json")
    original = File.read(path)
    variants = [
      JSON.parse(original).tap { |value| value["managed_files"][0]["source"] = "skills/other/SKILL.md" },
      JSON.parse(original).tap { |value| value["source_bundle_digest"] = "sha256:#{'f' * 64}" },
      JSON.parse(original).tap { |value| value["capability_report_digest"] = "sha256:#{'f' * 64}" }
    ]
    variants.map do |manifest|
      File.write(path, JSON.generate(manifest))
      invoke("plan", "--input", "-", "--json").dig(:document, "error", "code")
    end
  end

  def copy_source_bundle(name)
    source = File.join(directory, name)
    FileUtils.mkdir_p(source)
    FileUtils.cp_r(File.join(KosInitializeApplicationFixture::ROOT, "skills"), source)
    FileUtils.mkdir_p(File.join(source, "runtime"))
    FileUtils.cp_r(File.join(KosInitializeApplicationFixture::ROOT, "runtime/opencode"), File.join(source, "runtime"))
    source
  end

  def real_opencode
    ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |entry| File.join(entry, "opencode") }
      .find { |path| File.file?(path) && File.executable?(path) }
  end

  def write_registration_id(identifier)
    path = File.join(test_bin, "kos")
    File.write(path, File.read(path).sub(KosInitializeApplicationFixture::REPOSITORY_ID, identifier))
  end
end
