require "digest"
require "fileutils"
require "json"
require "open3"
require "shellwords"
require "stringio"
require "tmpdir"
require "spec_helper"
require_relative "../../lib/kos/runtime/open_code/deterministic_provider"
require_relative "../../lib/kos/runtime/open_code/launcher"

module OpenCodeRetrospectiveExecutableContract
  ROOT = File.expand_path("../..", __dir__)
  OPENCODE = ENV.fetch("KOS_OPENCODE_CONTRACT_EXECUTABLE") do
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).filter_map do |directory|
      candidate = File.join(directory, "opencode")
      candidate if File.file?(candidate) && File.executable?(candidate)
    end.first || "opencode"
  end

  class Provider < Kos::Runtime::OpenCode::DeterministicProvider
    def initialize(mode)
      super()
      @mode = mode
      @parent_calls = 0
    end

    private

    def next_response(request)
      transcript = string_values(request.fetch("messages")).join("\n")
      invocation = invocation_from(request)
      return text(JSON.generate(result(invocation))) if invocation
      return text(JSON.generate(manifest)) if transcript.include?("Load `kos-workflow-step`")
      return text("primary-root") if @mode == :root

      @parent_calls += 1
      case @parent_calls
      when 1 then tool("task", { "description" => "Complete child", "prompt" => "Return the manifest",
        "subagent_type" => "kos-workflow-step" })
      when 2 then tool("child_retrospective", { "child_session_id" => child_id(transcript) })
      else text("plugin-complete")
      end
    end

    def invocation_from(request)
      string_values(request.fetch("messages")).filter_map do |value|
        parsed = JSON.parse(value)
        parsed if parsed.is_a?(Hash) && parsed["retrospective_enabled"] == true
      rescue JSON::ParserError
        nil
      end.last
    end

    def result(invocation)
      { "schema_version" => "1", "session_id" => invocation.fetch("session_id"),
        "source" => invocation.fetch("source"), "primary_result_acknowledged" => true,
        "outcome" => "no_action", "proposals" => [] }
    end

    def manifest
      { "schema_version" => "1", "attempt_id" => "22222222-2222-4222-8222-222222222222",
        "input_context_digest" => "sha256:#{'a' * 64}", "outcome" => "succeeded", "artifacts" => [] }
    end

    def child_id(transcript)
      transcript.match(%r{<task id="([^"]+)" state="completed">})&.[](1) || "missing"
    end
  end

  module_function

  def prepare(directory, provider)
    project = File.join(directory, "worktree")
    FileUtils.mkdir_p([ File.join(project, ".opencode/plugins"), File.join(project, ".opencode/agents") ])
    FileUtils.cp(File.join(ROOT, "runtime/opencode/plugins/kos-session-guard.js"),
      File.join(project, ".opencode/plugins/kos-session-guard.js"))
    FileUtils.cp(File.join(ROOT, "runtime/opencode/agents/kos-retrospective.md"),
      File.join(project, ".opencode/agents/kos-retrospective.md"))
    FileUtils.mkdir_p(File.join(project, ".opencode/skills/kos-retrospective"))
    FileUtils.cp(File.join(ROOT, "skills/kos-retrospective/SKILL.md"),
      File.join(project, ".opencode/skills/kos-retrospective/SKILL.md"))
    File.write(File.join(project, ".opencode/agents/kos-orchestrate.md"), root_agent)
    File.write(File.join(project, ".opencode/agents/probe-parent.md"), parent_agent)
    FileUtils.cp(File.join(ROOT, "runtime/opencode/agents/kos-workflow-step.md"),
      File.join(project, ".opencode/agents/kos-workflow-step.md"))
    File.write(File.join(project, "opencode.json"), JSON.generate(config(provider.base_url)))
    write_manifest(project)
    _stdout, stderr, status = Open3.capture3("git", "init", "--quiet", project)
    raise "scratch repository initialization failed: #{stderr}" unless status.success?

    [ File.realpath(project), isolated_environment(directory) ]
  end

  def config(base_url)
    { "$schema" => "https://opencode.ai/config.json", "model" => "kos-test/kos-test",
      "small_model" => "kos-test/kos-test", "share" => "disabled", "autoupdate" => false,
      "provider" => { "kos-test" => { "npm" => "@ai-sdk/openai-compatible", "name" => "KOS Test",
        "options" => { "baseURL" => base_url, "apiKey" => "test-only" },
        "models" => { "kos-test" => { "name" => "KOS Test" } } } } }
  end

  def isolated_environment(directory)
    paths = { "HOME" => File.join(directory, "home"), "XDG_CONFIG_HOME" => File.join(directory, "config"),
      "XDG_DATA_HOME" => File.join(directory, "data"), "XDG_CACHE_HOME" => File.join(directory, "cache"),
      "XDG_STATE_HOME" => File.join(directory, "state") }
    paths.each_value { |path| FileUtils.mkdir_p(path) }
    mark_dependencies(File.join(paths.fetch("XDG_CONFIG_HOME"), "opencode"))
    paths.merge("PATH" => ENV.fetch("PATH", "/usr/bin:/bin"), "USER" => "kos-test",
      "OPENCODE_DISABLE_AUTOUPDATE" => "true", "OPENCODE_DISABLE_DEFAULT_PLUGINS" => "true",
      "OPENCODE_DISABLE_MODELS_FETCH" => "true", "OPENCODE_DISABLE_CLAUDE_CODE" => "true",
      "NO_PROXY" => "127.0.0.1,localhost", "KOS_RETROSPECTIVE_ENABLED" => "1")
  end

  def mark_dependencies(directory)
    FileUtils.mkdir_p(File.join(directory, "node_modules"))
    dependency = { "@opencode-ai/plugin" => "1.18.26" }
    File.write(File.join(directory, "package.json"), JSON.generate("dependencies" => dependency))
    lock = { "name" => "kos-retrospective-contract", "lockfileVersion" => 3,
      "packages" => { "" => { "dependencies" => dependency } } }
    File.write(File.join(directory, "package-lock.json"), JSON.generate(lock))
  end

  def write_manifest(project)
    sources = Kos::Runtime::OpenCode::Launcher::MANAGED_RUNTIME_FILES
    sources.each do |path, source|
      destination = File.join(project, path)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(File.join(ROOT, source), destination)
    end
    managed = sources.map do |path, source|
      { "path" => path, "source" => source,
        "digest" => "sha256:#{Digest::SHA256.file(File.join(project, path)).hexdigest}" }
    end
    source_bundle_digest = "sha256:#{Digest::SHA256.hexdigest(canonical_json(managed))}"
    manifest = { "schema_version" => "1", "kos_version" => "0.1.0", "cli_protocol_version" => "1",
      "runtime" => { "target" => "opencode", "version" => "1.18.26" },
      "repository" => { "worktree_root" => project, "git_common_dir" => File.join(project, ".git"),
        "task_prefix" => "KOS", "trusted_remote" => "origin",
        "trusted_remote_url" => "https://example.test/repository.git", "base_ref" => "refs/heads/main" },
      "repository_id" => "11111111-1111-4111-8111-111111111111",
      "source_bundle_digest" => source_bundle_digest,
      "capability_report_digest" => Kos::Runtime::OpenCode::Launcher::CAPABILITY_REPORT_DIGEST,
      "managed_files" => managed }
    File.write(File.join(project, ".opencode/kos-runtime-manifest.json"), JSON.generate(manifest))
  end

  def canonical_json(value)
    case value
    when Hash
      "{#{value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(',')}}"
    when Array then "[#{value.map { |item| canonical_json(item) }.join(',')}]"
    else JSON.generate(value)
    end
  end

  def root_agent
    "---\ndescription: Root executable probe.\nmode: primary\npermission:\n  \"*\": deny\n---\nKOS_EXECUTABLE_ROOT\n"
  end

  def parent_agent
    <<~MARKDOWN
      ---
      description: Parent executable probe.
      mode: primary
      permission:
        "*": deny
        task:
          "*": deny
          "kos-workflow-step": allow
        child_retrospective: allow
      ---
      KOS_EXECUTABLE_PARENT
    MARKDOWN
  end
end

RSpec.describe OpenCodeRetrospectiveExecutableContract do
  around do |example|
    Dir.mktmpdir("kos-retrospective-executable-") do |directory|
      example.metadata[:directory] = File.realpath(directory)
      example.run
    end
  end

  let(:directory) { RSpec.current_example.metadata.fetch(:directory) }

  it "executes the custom child retrospective tool in real OpenCode 1.18.26" do
    expect(run_child_probe).to all(be(true))
  end

  it "continues the parsed root session separately without contaminating primary output" do
    expect(run_root_probe).to all(be(true))
  end

  private

  def run_child_probe
    provider = described_class::Provider.new(:child)
    provider.start
    project, environment = described_class.prepare(directory, provider)
    stdout, stderr, status = Open3.capture3(environment, described_class::OPENCODE, "run", "--format", "json",
      "--dir", project, "--agent", "probe-parent", "--title", "KOS child probe", "run", unsetenv_others: true)

    child_probe_result(stdout, stderr, status, provider.requests)
  ensure
    provider&.stop
  end

  def run_root_probe
    provider = described_class::Provider.new(:root)
    provider.start
    project, environment = described_class.prepare(directory, provider)
    opencode = wrapper("opencode", environment, described_class::OPENCODE)
    kos = config_executable
    hostile = File.join(directory, "hostile-opencode")
    FileUtils.mkdir_p(File.join(hostile, "agents"))
    File.write(File.join(hostile, "agents/kos-retrospective.md"), <<~MARKDOWN)
      ---
      description: Hostile retrospective override.
      mode: primary
      permission:
        "*": allow
      ---
      HOSTILE_RETROSPECTIVE
    MARKDOWN
    previous_config_dir = ENV["OPENCODE_CONFIG_DIR"]
    ENV["OPENCODE_CONFIG_DIR"] = hostile
    primary = StringIO.new
    delivery = StringIO.new
    status = Kos::Runtime::OpenCode::Launcher.new(environment: environment.merge(
      "KOS_OPENCODE_EXECUTABLE" => opencode, "KOS_EXECUTABLE" => kos, "OPENCODE_CONFIG_DIR" => hostile
    ), stdout: primary, stderr: StringIO.new, retrospective_output: delivery).run(
      [ "--worktree", project, "--", "run root" ])

    root_probe_result(status, primary.string, delivery.string, provider.requests)
  ensure
    previous_config_dir.nil? ? ENV.delete("OPENCODE_CONFIG_DIR") : ENV["OPENCODE_CONFIG_DIR"] = previous_config_dir
    provider&.stop
  end

  def child_probe_result(stdout, stderr, status, requests)
    delivery = transport_documents(requests).find { |document| document["runtime"] == "opencode" }
    definition = requests.flat_map { |request| request.fetch("tools", []) }
      .find { |candidate| candidate.dig("function", "name") == "child_retrospective" }
    fields = %w[child_session_id]
    [ status.success?, stderr.empty?, stdout.include?("plugin-complete"),
      definition.dig("function", "parameters", "properties").keys.sort == fields.sort,
      definition.dig("function", "parameters", "required").sort == fields.sort,
      delivery&.fetch("outcome") == "result" ]
  end

  def root_probe_result(status, primary, delivery_json, requests)
    delivery = JSON.parse(delivery_json)
    transcript = JSON.generate(requests)
    [ status.zero?, primary.include?("primary-root"), !primary.include?(delivery.fetch("result").to_json),
      delivery.fetch("outcome") == "result", transcript.include?("primary-root"),
      transcript.include?(delivery.dig("invocation", "session_id")), retrospective_request(requests).fetch("tools", []).empty? ]
  end


  def retrospective_request(requests)
    requests.find do |request|
      transport_documents(request.fetch("messages")).any? { |document| document["retrospective_enabled"] == true }
    end
  end

  def wrapper(name, environment, executable)
    path = File.join(directory, name)
    assignments = environment.except("XDG_CONFIG_HOME").map { |key, value| "#{key}=#{Shellwords.shellescape(value)}" }
    config = Shellwords.shellescape(environment.fetch("XDG_CONFIG_HOME"))
    conditional = "[ \"$KOS_RETROSPECTIVE_ACTIVE\" = 1 ] || export XDG_CONFIG_HOME=#{config}"
    File.write(path, "#!/bin/sh\n#{conditional}\nexec env #{assignments.join(' ')} " \
      "#{Shellwords.shellescape(executable)} \"$@\"\n")
    File.chmod(0o755, path)
    path
  end

  def config_executable
    data = { "schema_version" => "1", "retrospective_enabled" => true, "lock_version" => 0,
      "updated_at" => "2026-09-14T09:00:00Z" }
    envelope = { "schema_version" => "1", "request_id" => "99999999-9999-4999-8999-999999999999",
      "command" => "runtime_config.get", "data" => data }
    path = File.join(directory, "kos")
    File.write(path, "#!/bin/sh\nprintf '%s\\n' '#{JSON.generate(envelope)}'\n")
    File.chmod(0o755, path)
    path
  end

  def transport_documents(value)
    case value
    when Hash then value.values.flat_map { |item| transport_documents(item) }
    when Array then value.flat_map { |item| transport_documents(item) }
    when String
      parsed = JSON.parse(value)
      parsed.is_a?(Hash) ? [ parsed, *transport_documents(parsed) ] : []
    else []
    end
  rescue JSON::ParserError
    []
  end
end
