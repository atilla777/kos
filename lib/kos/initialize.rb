require "digest"
require "fileutils"
require "json"
require "json_schemer"
require "open3"
require "pathname"
require "securerandom"

require_relative "git_url"
require_relative "json_parser"
require_relative "runtime/open_code/capability_verifier"
require_relative "version"

module Kos
  module Initialize
    class Error < StandardError
      attr_reader :code

      def initialize(code, message)
        @code = code
        super(message)
      end
    end

    module CanonicalJson
      module_function

      def generate(value)
        JSON.generate(sort(value))
      end

      def digest(value)
        "sha256:#{Digest::SHA256.hexdigest(generate(value))}"
      end

      def sort(value)
        case value
        when Hash then value.keys.sort.to_h { |key| [ key, sort(value.fetch(key)) ] }
        when Array then value.map { |item| sort(item) }
        else value
        end
      end
    end

    class Schema
      PATH = File.expand_path("../../schemas/installation/v1/installer.json", __dir__)

      def initialize
        @schema = JSONSchemer.schema(JSON.parse(File.read(PATH)))
      end

      def validate!(definition, value, code: "malformed_input")
        return value if @schema.ref("#/$defs/#{definition}").valid?(value)

        raise Error.new(code, "Document does not satisfy installation schema #{definition}")
      end
    end

    class CommandRunner
      Result = Data.define(:stdout, :stderr, :status, :timed_out)

      def initialize(timeout: 30)
        @timeout = timeout
      end

      def capture(*command, chdir:, stdin_data: "", environment: {}, unset_environment: false)
        Open3.popen3(environment, *command, chdir: chdir, unsetenv_others: unset_environment, pgroup: true) do
          |stdin, stdout, stderr, wait|
          writer = Thread.new do
            stdin.write(stdin_data)
          rescue Errno::EPIPE, IOError
            nil
          ensure
            stdin.close
          end
          out_reader = Thread.new { stdout.read }
          err_reader = Thread.new { stderr.read }
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
          complete = join_before(wait, deadline) && join_before(writer, deadline) &&
            join_before(out_reader, deadline) && join_before(err_reader, deadline)
          terminate_group(wait.pid, wait, writer, out_reader, err_reader) unless complete
          Result.new(stdout: out_reader.value, stderr: err_reader.value, status: wait.value, timed_out: !complete)
        end
      end

      private

      def join_before(thread, deadline)
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        remaining.positive? && thread.join(remaining)
      end

      def terminate_group(pid, wait, *readers)
        Process.kill("TERM", -pid)
        sleep(0.05)
        Process.kill("KILL", -pid)
      rescue Errno::ESRCH
        nil
      ensure
        wait.join
        readers.each(&:join)
      end
    end

    class SafeTree
      class MissingAncestor < StandardError; end

      LINUX_O_DIRECTORY = 0o200000
      Backup = Data.define(:bytes, :mode)
      Parent = Data.define(:files, :path) do
        def descriptor
          files.last
        end

        def proc_path
          "/proc/self/fd/#{descriptor.fileno}"
        end

        def close
          files.reverse_each { |file| file.close unless file.closed? }
        end
      end
      Stage = Data.define(:parent, :name, :descriptor, :path) do
        def proc_path
          "/proc/self/fd/#{descriptor.fileno}"
        end
      end

      def initialize(root, root_descriptor: nil, fsync_observer: nil)
        raise Error.new("safe_traversal_unavailable", "Linux descriptor traversal is unavailable") unless
          RUBY_PLATFORM.include?("linux") && File.directory?("/proc/self/fd") && defined?(File::NOFOLLOW)

        @root_source = root
        @root = File.realpath(root)
        @root_descriptor = root_descriptor
        @fsync_observer = fsync_observer
      end

      def open_parent(relative, create:)
        completed = false
        components = Pathname.new(relative).each_filename.to_a
        raise Error.new("path_escape", "Managed path is not canonical") if components.empty? || components.include?("..")

        files = [ open_root ]
        components[0...-1].each_with_index do |component, index|
          child = "#{proc_path(files.last)}/#{component}"
          raise MissingAncestor unless create || entry_exists?(child)
          unless entry_exists?(child)
            raise MissingAncestor unless create

            Dir.mkdir(child, 0o755)
            fsync_directory(files.last, File.join(@root, *components[0...index]))
          end
          files << open_directory(child, File.join(@root, *components[0..index]))
        end
        parent = Parent.new(files:, path: File.join(@root, *components[0...-1]))
        revalidate_parent!(parent)
        completed = true
        [ parent, components.last ]
      ensure
        files&.reverse_each { |file| file.close unless file.closed? } unless completed
      end

      def create_stage
        parent, = open_parent(".opencode/.stage", create: true)
        yield if block_given?
        revalidate_parent!(parent)
        name = ".kos-stage-#{SecureRandom.hex(12)}"
        path = entry(parent, name)
        Dir.mkdir(path, 0o700)
        created_stat = File.lstat(path)
        descriptor = open_directory(path, File.join(parent.path, name))
        descriptor.chmod(0o700)
        descriptor.fsync
        fsync_directory(parent.descriptor, parent.path)
        Stage.new(parent:, name:, descriptor:, path: File.join(parent.path, name))
      rescue StandardError => error
        cleanup_error = begin
          if parent && name && created_stat && entry_exists?(entry(parent, name))
            current_stat = File.lstat(entry(parent, name))
            unless current_stat.directory? && !current_stat.symlink? &&
                [ current_stat.dev, current_stat.ino ] == [ created_stat.dev, created_stat.ino ]
              raise Error.new("staging_cleanup_failed", "Staging directory identity changed")
            end
            descriptor&.close
            Dir.rmdir(entry(parent, name))
            fsync_directory(parent.descriptor, parent.path)
          end
          nil
        rescue StandardError => cleanup_failure
          cleanup_failure
        ensure
          descriptor&.close unless descriptor&.closed?
          parent&.close
        end
        raise Error.new("staging_cleanup_failed", "Staging directory cleanup failed") if cleanup_error

        raise error
      end

      def cleanup_stage(stage)
        remove_directory_contents(stage.descriptor)
        path_stat = File.lstat(entry(stage.parent, stage.name))
        descriptor_stat = stage.descriptor.stat
        unless path_stat.directory? && !path_stat.symlink? &&
            [ path_stat.dev, path_stat.ino ] == [ descriptor_stat.dev, descriptor_stat.ino ]
          raise Error.new("staging_cleanup_failed", "Staging directory identity changed")
        end
        stage.descriptor.close
        Dir.rmdir(entry(stage.parent, stage.name))
        fsync_directory(stage.parent.descriptor, stage.parent.path)
      rescue Error
        raise
      rescue SystemCallError
        raise Error.new("staging_cleanup_failed", "Staging directory cleanup failed")
      ensure
        stage.descriptor.close unless stage.descriptor.closed?
        stage.parent.close
      end

      def write_file(relative, content, mode: 0o644)
        parent, name = open_parent(relative, create: true)
        path = entry(parent, name)
        flags = File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW
        File.open(path, flags, 0o600) do |file|
          file.write(content)
          file.flush
          file.chmod(mode)
          file.fsync
        end
        fsync_directory(parent.descriptor, parent.path)
      ensure
        parent&.close
      end

      def observe_relative(relative)
        parent, name = open_parent(relative, create: false)
        observe(parent, name)
      rescue MissingAncestor
        [ "absent", nil ]
      ensure
        parent&.close
      end

      def backup(parent, name)
        file = open_regular(parent, name)
        Backup.new(bytes: file.read, mode: file.stat.mode & 0o777)
      ensure
        file&.close
      end

      def observe(parent, name)
        stat = File.lstat(entry(parent, name))
        return [ "symlink", nil ] if stat.symlink?
        return [ "wrong_type", nil ] unless stat.file?

        file = open_regular(parent, name)
        [ "regular", "sha256:#{Digest::SHA256.hexdigest(file.read)}" ]
      rescue Errno::ENOENT
        [ "absent", nil ]
      ensure
        file&.close
      end

      def rename(source, parent, name, expected_digest:)
        revalidate_parent!(parent)
        File.rename(source, entry(parent, name))
        yield if block_given?
        verify_regular(parent, name, expected_digest)
        revalidate_parent!(parent)
        fsync_directory(parent.descriptor, parent.path)
      end

      def verify_regular(parent, name, expected_digest)
        file = open_regular(parent, name)
        digest = "sha256:#{Digest::SHA256.hexdigest(file.read)}"
        raise Error.new("destination_changed", "Published destination changed") unless digest == expected_digest
      ensure
        file&.close
      end

      def restore(parent, name, backup)
        revalidate_parent!(parent)
        temporary = ".kos-rollback-#{Process.pid}-#{SecureRandom.hex(6)}"
        path = entry(parent, temporary)
        flags = File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW
        File.open(path, flags, backup.mode) do |file|
          file.write(backup.bytes)
          file.flush
          file.chmod(backup.mode)
          file.fsync
        end
        File.rename(path, entry(parent, name))
        revalidate_parent!(parent)
        fsync_directory(parent.descriptor, parent.path)
      ensure
        File.unlink(path) if path && File.exist?(path)
      end

      def unlink(parent, name)
        revalidate_parent!(parent)
        File.unlink(entry(parent, name))
        revalidate_parent!(parent)
        fsync_directory(parent.descriptor, parent.path)
      end

      private

      def open_root
        return open_directory(@root_source, @root) unless @root_descriptor

        file = @root_descriptor.dup
        actual = File.realpath(proc_path(file))
        return file if actual == @root

        file.close
        raise Error.new("destination_changed", "Installation ancestry changed")
      end

      def open_directory(path, expected)
        file = File.open(path, File::RDONLY | LINUX_O_DIRECTORY | File::NOFOLLOW)
        actual = File.realpath(proc_path(file))
        unless actual == expected
          file.close
          raise Error.new("unsafe_destination", "Directory descriptor escaped its expected path")
        end

        file
      rescue Errno::ELOOP, Errno::ENOTDIR, Errno::ENOENT, Errno::EACCES
        raise Error.new("unsafe_destination", "Installation ancestry is unavailable")
      end

      def open_regular(parent, name)
        revalidate_parent!(parent)
        path_stat = File.lstat(entry(parent, name))
        raise Error.new("unsafe_destination", "Managed destination is not a regular file") unless
          path_stat.file? && !path_stat.symlink?

        file = File.open(entry(parent, name), File::RDONLY | File::NOFOLLOW)
        descriptor_stat = file.stat
        unless [ path_stat.dev, path_stat.ino ] == [ descriptor_stat.dev, descriptor_stat.ino ]
          file.close
          raise Error.new("destination_changed", "Managed destination identity changed")
        end
        file
      rescue Errno::ELOOP, Errno::EISDIR, Errno::EACCES
        raise Error.new("unsafe_destination", "Managed destination is unavailable")
      end

      def revalidate_parent!(parent)
        actual = File.realpath(parent.proc_path)
        raise Error.new("destination_changed", "Installation ancestry changed") unless actual == parent.path
      rescue Errno::ENOENT
        raise Error.new("destination_changed", "Installation ancestry changed")
      end

      def entry(parent, name)
        "#{parent.proc_path}/#{name}"
      end

      def proc_path(file)
        "/proc/self/fd/#{file.fileno}"
      end

      def entry_exists?(path)
        File.lstat(path)
        true
      rescue Errno::ENOENT
        false
      end

      def remove_directory_contents(descriptor)
        path = proc_path(descriptor)
        Dir.children(path).each do |name|
          child = "#{path}/#{name}"
          stat = File.lstat(child)
          if stat.directory? && !stat.symlink?
            directory = open_directory_unbound(child)
            remove_directory_contents(directory)
            directory.close
            Dir.rmdir(child)
          else
            File.unlink(child)
          end
          fsync_directory(descriptor, path)
        ensure
          directory&.close unless directory&.closed?
        end
      end

      def open_directory_unbound(path)
        File.open(path, File::RDONLY | LINUX_O_DIRECTORY | File::NOFOLLOW)
      rescue Errno::ELOOP, Errno::ENOTDIR, Errno::ENOENT, Errno::EACCES
        raise Error.new("staging_cleanup_failed", "Staging contents changed during cleanup")
      end

      def fsync_directory(descriptor, path)
        @fsync_observer&.call(path)
        descriptor.fsync
      end
    end

    class Installer
      ROOT = File.expand_path("../..", __dir__)
      MANIFEST_PATH = ".opencode/kos-runtime-manifest.json"
      OPEN_CODE_VERSION = "1.18.26"
      INVENTORY = {
        ".opencode/skills/kos-cli/SKILL.md" => "skills/kos-cli/SKILL.md",
        ".opencode/skills/kos-initialize/SKILL.md" => "skills/kos-initialize/SKILL.md",
        ".opencode/skills/kos-orchestrate/SKILL.md" => "skills/kos-orchestrate/SKILL.md",
        ".opencode/skills/kos-repository/SKILL.md" => "skills/kos-repository/SKILL.md",
        ".opencode/skills/kos-retrospective/SKILL.md" => "skills/kos-retrospective/SKILL.md",
        ".opencode/skills/kos-workflow-step/SKILL.md" => "skills/kos-workflow-step/SKILL.md",
        ".opencode/plugins/kos-session-guard.js" => "runtime/opencode/plugins/kos-session-guard.js",
        ".opencode/agents/kos-orchestrate.md" => "runtime/opencode/agents/kos-orchestrate.md",
        ".opencode/agents/kos-retrospective.md" => "runtime/opencode/agents/kos-retrospective.md",
        ".opencode/agents/kos-workflow-step.md" => "runtime/opencode/agents/kos-workflow-step.md"
      }.freeze
      PREVIOUS_INVENTORY = INVENTORY.except(".opencode/agents/kos-retrospective.md").freeze
      PREVIOUS_CAPABILITY_REPORT_DIGEST =
        "sha256:7affe716c66b446a0ae94eae35a115fcf9657165adc9af6d773180e007086701".freeze

      def initialize(cwd: Dir.pwd, environment: ENV, runner: CommandRunner.new, source_root: ROOT, schema: Schema.new,
        failure_injector: nil, capability_verifier_factory: nil)
        @cwd = File.realpath(cwd)
        @environment = environment
        @runner = runner
        @source_root = File.realpath(source_root)
        @schema = schema
        @failure_injector = failure_injector
        @capability_verifier_factory = capability_verifier_factory || lambda do |**arguments|
          Kos::Runtime::OpenCode::CapabilityVerifier.new(**arguments)
        end
      rescue SystemCallError
        raise Error.new("repository_invalid", "Current directory is unavailable")
      end

      def plan(request)
        @schema.validate!("request", request)
        repository = inspect_repository(request)
        readiness = inspect_readiness
        sources = source_files
        manifest, manifest_observation = read_manifest(repository.fetch("worktree_root"), repository)
        files = observe_files(repository.fetch("worktree_root"), sources, manifest)
        document = {
          "schema_version" => "1", "operation" => "plan", "kos_version" => Kos::VERSION,
          "cli_protocol_version" => "1",
          "registration_idempotency_key" => request.fetch("registration_idempotency_key"),
          "repository" => repository,
          "runtime" => request.fetch("runtime"), "source_bundle_digest" => bundle_digest(sources),
          "readiness" => readiness, "manifest_observation" => manifest_observation, "managed_files" => files
        }
        document["plan_digest"] = CanonicalJson.digest(document)
        @schema.validate!("plan", document, code: "internal_error")
      end

      def apply(request, approved_plan:, force:)
        @schema.validate!("request", request)
        initial = plan(request)
        root = initial.dig("repository", "worktree_root")
        with_lock(initial.dig("repository", "git_common_dir")) do
          approved = plan(request)
          unless approved.fetch("plan_digest") == approved_plan
            raise Error.new("plan_changed", "Approved plan digest does not match the current plan")
          end
          enforce_actions!(approved.fetch("managed_files"), force)
          registration = register_repository(request, approved.fetch("repository"))
          validate_manifest_registration!(approved.fetch("manifest_observation"), registration.fetch("id"))
          publish(root, approved, registration.fetch("id"))
        end
      end

      private

      def inspect_repository(request)
        bare = git("rev-parse", "--is-bare-repository").strip
        raise Error.new("repository_invalid", "A non-bare Git worktree is required") unless bare == "false"

        root = canonical_git_path(git("rev-parse", "--show-toplevel").strip)
        common = git("rev-parse", "--path-format=absolute", "--git-common-dir", chdir: root).strip
        common = canonical_git_path(common)
        verify_worktree_common!(root, common)
        remote = request.fetch("trusted_remote")
        urls = git("remote", "get-url", "--all", remote, chdir: root).lines.map(&:strip).reject(&:empty?)
        raise Error.new("repository_invalid", "Trusted remote must have exactly one URL") unless urls.one?

        git("show-ref", "--verify", request.fetch("base_ref"), chdir: root)
        {
          "worktree_root" => root, "git_common_dir" => common, "task_prefix" => request.fetch("task_prefix"),
          "trusted_remote" => remote, "trusted_remote_url" => normalize_remote(urls.first),
          "base_ref" => request.fetch("base_ref")
        }
      end

      def verify_worktree_common!(root, common)
        listed = git("worktree", "list", "--porcelain", chdir: root).lines.filter_map do |line|
          canonical_git_path(line.delete_prefix("worktree ").strip) if line.start_with?("worktree ")
        rescue Error
          nil
        end
        raise Error.new("repository_invalid", "Current worktree does not belong to its Git common directory") unless listed.include?(root)

        actual = canonical_git_path(git("-C", root, "rev-parse", "--path-format=absolute", "--git-common-dir").strip)
        raise Error.new("repository_invalid", "Git common directory identity changed") unless actual == common
      end

      def canonical_git_path(path)
        File.realpath(path)
      rescue SystemCallError
        raise Error.new("repository_invalid", "Git returned an unavailable path")
      end

      def normalize_remote(value)
        Kos::GitUrl.normalize(value)
      rescue Kos::GitUrl::Invalid
        raise Error.new("repository_invalid", "Trusted remote URL is invalid")
      end

      def inspect_readiness
        kos = executable("kos")
        repository = executable("kos-repository")
        launcher = executable("kos-opencode")
        opencode = executable("opencode")
        version = command!(opencode, "--version", chdir: @cwd).strip
        raise Error.new("runtime_incompatible", "OpenCode #{OPEN_CODE_VERSION} is required") unless version == OPEN_CODE_VERSION

        types = cli!(kos, "task-type", "list", "--limit", "100", "--json", expected_command: "task_type.list")
        quick_fix = types.fetch("task_types").find { |entry| entry["name"] == "quick-fix" }
        workflow_id = quick_fix&.fetch("current_workflow_version_id", nil)
        raise Error.new("workflow_unavailable", "quick-fix has no active published workflow") unless workflow_id

        workflow = cli!(kos, "workflow", "get", "--workflow-version", workflow_id, "--json",
          expected_command: "workflow.get")
        unless workflow["id"] == workflow_id && workflow["task_type"] == "quick-fix" && workflow["definition"].is_a?(Hash)
          raise Error.new("workflow_unavailable", "Active quick-fix workflow is not readable")
        end
        {
          "kos_executable" => kos, "repository_executable" => repository,
          "launcher_executable" => launcher, "opencode_executable" => opencode,
          "capability_report_digest" => Kos::Runtime::OpenCode::CapabilityVerifier.report_digest,
          "quick_fix_workflow_version_id" => workflow_id,
          "quick_fix_workflow_version" => workflow.fetch("version"),
          "quick_fix_content_digest" => workflow.fetch("content_digest")
        }
      rescue KeyError, JSON::ParserError
        raise Error.new("workflow_unavailable", "KOS returned malformed workflow readiness data")
      end

      def executable(name)
        @environment.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
          path = File.join(directory, name)
          return File.realpath(path) if File.file?(path) && File.executable?(path)
        end
        raise Error.new("executable_unavailable", "#{name} is not an executable on PATH")
      end

      def source_files
        INVENTORY.map do |destination, source|
          path = contained_source(source)
          raise Error.new("source_invalid", "Managed source is not a regular file") unless File.file?(path) && !File.symlink?(path)

          [ destination, { "source" => source, "content" => File.binread(path), "digest" => file_digest(path) } ]
        end.to_h
      end

      def contained_source(relative)
        path = File.realpath(File.join(@source_root, relative))
        prefix = "#{@source_root}/"
        raise Error.new("source_invalid", "Managed source escapes the source bundle") unless path.start_with?(prefix)

        path
      rescue SystemCallError
        raise Error.new("source_invalid", "Managed source is unavailable")
      end

      def bundle_digest(sources)
        CanonicalJson.digest(sources.map { |path, source| { "path" => path, "source" => source.fetch("source"),
          "digest" => source.fetch("digest") } })
      end

      def read_manifest(root, repository)
        validate_ancestry!(root, MANIFEST_PATH)
        path = destination(root, MANIFEST_PATH)
        return [ nil, { "observed" => "absent" } ] unless File.exist?(path) || File.symlink?(path)
        raise Error.new("manifest_invalid", "Runtime manifest must be a regular file") unless regular_without_symlink?(path)

        bytes = File.binread(path)
        manifest = Kos::JsonParser.parse(bytes)
        @schema.validate!("manifest", manifest, code: "manifest_invalid")
        inventory = manifest.fetch("managed_files")
        expected_inventory = INVENTORY.map { |destination_path, source| [ destination_path, source ] }
        actual_inventory = inventory.map { |entry| [ entry.fetch("path"), entry.fetch("source") ] }
        recomputed_bundle = CanonicalJson.digest(inventory.map { |entry| entry.slice("path", "source", "digest") })
        capability = Kos::Runtime::OpenCode::CapabilityVerifier.report_digest
        previous_inventory = PREVIOUS_INVENTORY.map { |destination_path, source| [ destination_path, source ] }
        supported_contract = (actual_inventory == expected_inventory &&
          manifest.fetch("capability_report_digest") == capability) ||
          (actual_inventory == previous_inventory &&
            manifest.fetch("capability_report_digest") == PREVIOUS_CAPABILITY_REPORT_DIGEST)
        unless supported_contract && manifest.fetch("repository") == repository &&
            manifest.fetch("source_bundle_digest") == recomputed_bundle
          raise Error.new("manifest_invalid", "Runtime manifest does not own this exact installation")
        end
        observation = { "observed" => "expected", "digest" => "sha256:#{Digest::SHA256.hexdigest(bytes)}",
          "repository_id" => manifest.fetch("repository_id") }
        [ manifest, observation ]
      rescue JSON::ParserError, KeyError
        raise Error.new("manifest_invalid", "Runtime manifest is malformed or unsupported")
      end

      def validate_manifest_registration!(observation, repository_id)
        return if observation.fetch("observed") == "absent" || observation.fetch("repository_id") == repository_id

        raise Error.new("manifest_invalid", "Runtime manifest belongs to another registered repository")
      end

      def observe_files(root, sources, manifest)
        owned = manifest&.fetch("managed_files", [])&.to_h { |entry| [ entry.fetch("path"), entry ] } || {}
        sources.map do |relative, source|
          validate_ancestry!(root, relative)
          path = destination(root, relative)
          observation = observe(path, source.fetch("digest"), owned[relative])
          { "path" => relative, "source" => source.fetch("source"), "digest" => source.fetch("digest"),
            "action" => action_for(observation), **observation }
        end
      end

      def observe(path, expected_digest, owner)
        stat = File.lstat(path)
        return { "observed" => "symlink" } if stat.symlink?
        return { "observed" => "wrong_type" } unless stat.file?

        actual = file_digest(path)
        return { "observed" => "unmanaged", "observed_digest" => actual } unless owner
        return { "observed" => "drifted", "observed_digest" => actual } unless actual == owner.fetch("digest")
        return { "observed" => "expected", "observed_digest" => actual } if actual == expected_digest

        { "observed" => "managed_previous", "observed_digest" => actual }
      rescue Errno::ENOENT
        { "observed" => owner ? "missing" : "absent" }
      end

      def action_for(observation)
        case observation.fetch("observed")
        when "absent" then "create"
        when "missing" then "update"
        when "expected" then "unchanged"
        when "managed_previous", "drifted" then "update"
        else "conflict"
        end
      end

      def enforce_actions!(files, force)
        unsafe = files.select { |file| %w[symlink wrong_type].include?(file.fetch("observed")) }
        raise Error.new("unsafe_destination", "Managed destination is a symlink or wrong object type") unless unsafe.empty?
        replacements = files.select { |file| %w[update conflict].include?(file.fetch("action")) }
        if replacements.any? && !force
          raise Error.new("force_required", "The approved plan contains existing files that require --force")
        end
      end

      def register_repository(request, repository)
        kos = executable("kos")
        body = repository.except("worktree_root")
        result = cli!(kos, "repository", "register", "--input", "-", "--idempotency-key",
          request.fetch("registration_idempotency_key"), "--json", expected_command: "repository.register",
          stdin_data: JSON.generate(body))
        unless result.slice("git_common_dir", "task_prefix", "trusted_remote", "trusted_remote_url", "base_ref") == body
          raise Error.new("registration_failed", "Repository registration does not match the approved plan")
        end
        result
      end

      def publish(root, plan, repository_id)
        sources = source_files
        fsync_observer = ->(path) { @failure_injector&.call("fsync:#{path}") }
        tree = SafeTree.new(root, fsync_observer:)
        stage = tree.create_stage { @failure_injector&.call("during_stage_creation") }
        stage_tree = SafeTree.new(stage.proc_path, root_descriptor: stage.descriptor, fsync_observer:)
        publications = []
        begin
          stage_bundle(stage_tree, sources)
          verify_staged_digests!(stage_tree, plan)
          verify_staged_bundle(stage, plan.fetch("readiness"))
          verify_staged_digests!(stage_tree, plan)
          @failure_injector&.call("before_destination_revalidation")
          verify_destination_observations!(tree, plan)
          if plan.fetch("managed_files").all? { |file| file.fetch("action") == "unchanged" }
            result = { "schema_version" => "1", "operation" => "apply", "plan_digest" => plan.fetch("plan_digest"),
              "manifest_path" => destination(root, MANIFEST_PATH), "repository_id" => repository_id,
              "published_files" => [] }
            return @schema.validate!("apply_result", result, code: "internal_error")
          end
          plan.fetch("managed_files").each do |file|
            next if file.fetch("action") == "unchanged"

            publish_file(tree, stage, file, publications)
          end
          manifest = build_manifest(plan, repository_id)
          write_staged_manifest(stage_tree, manifest)
          publish_manifest(tree, stage, plan.fetch("manifest_observation"), publications)
          result = { "schema_version" => "1", "operation" => "apply", "plan_digest" => plan.fetch("plan_digest"),
            "manifest_path" => destination(root, MANIFEST_PATH), "repository_id" => repository_id,
            "published_files" => publications.filter_map do |publication|
              publication.fetch(:relative) unless publication.fetch(:relative) == MANIFEST_PATH
            end }
          @schema.validate!("apply_result", result, code: "internal_error")
        rescue StandardError => error
          failures = rollback(tree, publications)
          unless failures.empty?
            raise Error.new("rollback_incomplete", "Publication failed and rollback could not restore every destination")
          end
          raise error
        ensure
          publications.each { |publication| publication.fetch(:parent).close }
          tree.cleanup_stage(stage) if stage
        end
      end

      def stage_bundle(stage_tree, sources)
        sources.each do |relative, source|
          stage_tree.write_file(relative, source.fetch("content"))
          type, digest = stage_tree.observe_relative(relative)
          raise Error.new("staging_failed", "Staged file digest changed") unless
            type == "regular" && digest == source.fetch("digest")
        end
      end

      def verify_staged_bundle(stage, readiness)
        verifier = @capability_verifier_factory.call(executable: readiness.fetch("opencode_executable"),
          launcher_executable: readiness.fetch("launcher_executable"),
          staged_opencode: destination(stage.proc_path, ".opencode"), path: @environment.fetch("PATH", ""))
        report = verifier.call
        digest = Kos::Runtime::OpenCode::CapabilityVerifier.report_digest(report)
        return if digest == readiness.fetch("capability_report_digest")

        raise Error.new("capability_failed", "OpenCode capability report differs from the approved contract")
      rescue Kos::Runtime::OpenCode::CapabilityVerifier::Incompatible, KeyError => error
        raise Error.new("capability_failed", error.message)
      end

      def verify_staged_digests!(stage_tree, plan)
        files = plan.fetch("managed_files")
        valid = files.all? do |file|
          stage_tree.observe_relative(file.fetch("path")) == [ "regular", file.fetch("digest") ]
        end
        source_digest = CanonicalJson.digest(files.map { |file| file.slice("path", "source", "digest") })
        valid &&= source_digest == plan.fetch("source_bundle_digest")
        raise Error.new("staging_failed", "Staged bundle differs from the approved source bundle") unless valid
      end

      def build_manifest(plan, repository_id)
        manifest = {
          "schema_version" => "1", "kos_version" => Kos::VERSION, "cli_protocol_version" => "1",
          "runtime" => plan.fetch("runtime"), "repository" => plan.fetch("repository"),
          "repository_id" => repository_id, "source_bundle_digest" => plan.fetch("source_bundle_digest"),
          "capability_report_digest" => plan.dig("readiness", "capability_report_digest"),
          "managed_files" => plan.fetch("managed_files").map { |file| file.slice("path", "source", "digest") }
        }
        @schema.validate!("manifest", manifest, code: "internal_error")
      end

      def write_staged_manifest(stage_tree, manifest)
        stage_tree.write_file(MANIFEST_PATH, "#{JSON.pretty_generate(CanonicalJson.sort(manifest))}\n")
      end

      def rollback(tree, publications)
        publications.reverse_each.filter_map do |publication|
          @failure_injector&.call("rollback:#{publication.fetch(:relative)}")
          tree.verify_regular(publication.fetch(:parent), publication.fetch(:name),
            publication.fetch(:published_digest))
          if publication.fetch(:backup)
            tree.restore(publication.fetch(:parent), publication.fetch(:name), publication.fetch(:backup))
          else
            tree.unlink(publication.fetch(:parent), publication.fetch(:name))
          end
          nil
        rescue StandardError => error
          error
        end
      end

      def publish_file(tree, stage, file, publications)
        relative = file.fetch("path")
        @failure_injector&.call(relative)
        parent, name = tree.open_parent(relative, create: true)
        verify_file_observation!(tree, parent, name, file)
        backup = tree.backup(parent, name) unless %w[absent missing].include?(file.fetch("observed"))
        publication = { relative:, parent:, name:, backup:, published_digest: file.fetch("digest") }
        tree.rename(destination(stage.proc_path, relative), parent, name, expected_digest: file.fetch("digest")) do
          publications << publication
        end
      rescue StandardError
        parent&.close unless publication && publications.include?(publication)
        raise
      end

      def publish_manifest(tree, stage, observation, publications)
        @failure_injector&.call(MANIFEST_PATH)
        parent, name = tree.open_parent(MANIFEST_PATH, create: true)
        verify_manifest_observation!(tree, parent, name, observation)
        backup = tree.backup(parent, name) if observation.fetch("observed") == "expected"
        staged = destination(stage.proc_path, MANIFEST_PATH)
        published_digest = file_digest(staged)
        publication = { relative: MANIFEST_PATH, parent:, name:, backup:, published_digest: }
        tree.rename(staged, parent, name, expected_digest: published_digest) { publications << publication }
      rescue StandardError
        parent&.close unless publication && publications.include?(publication)
        raise
      end

      def verify_destination_observations!(tree, plan)
        plan.fetch("managed_files").each do |file|
          type, digest = tree.observe_relative(file.fetch("path"))
          expected_type = %w[absent missing].include?(file.fetch("observed")) ? "absent" : "regular"
          verify_observation_values!(type, digest, expected_type, file["observed_digest"])
        end
        type, digest = tree.observe_relative(MANIFEST_PATH)
        observation = plan.fetch("manifest_observation")
        expected_type = observation.fetch("observed") == "absent" ? "absent" : "regular"
        verify_observation_values!(type, digest, expected_type, observation["digest"])
      end

      def verify_file_observation!(tree, parent, name, planned)
        type, digest = tree.observe(parent, name)
        expected_type = %w[absent missing].include?(planned.fetch("observed")) ? "absent" : "regular"
        verify_observation_values!(type, digest, expected_type, planned["observed_digest"])
      end

      def verify_manifest_observation!(tree, parent, name, observation)
        type, digest = tree.observe(parent, name)
        expected_type = observation.fetch("observed") == "absent" ? "absent" : "regular"
        verify_observation_values!(type, digest, expected_type, observation["digest"])
      end

      def verify_observation_values!(type, digest, expected_type, expected_digest)
        return if type == expected_type && digest == expected_digest

        raise Error.new("destination_changed", "Managed destination changed after approval")
      end

      def with_lock(common_dir)
        lock = File.join(common_dir, "kos-initialize.lock")
        if File.exist?(lock) || File.symlink?(lock)
          stat = File.lstat(lock)
          raise Error.new("unsafe_destination", "Installation lock must be a regular file") unless
            stat.file? && !stat.symlink?
        end

        flags = File::RDWR | File::CREAT
        flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
        File.open(lock, flags, 0o600) do |file|
          path_stat = File.lstat(lock)
          descriptor_stat = file.stat
          unless path_stat.file? && !path_stat.symlink? &&
              [ path_stat.dev, path_stat.ino ] == [ descriptor_stat.dev, descriptor_stat.ino ]
            raise Error.new("unsafe_destination", "Installation lock identity changed")
          end
          file.flock(File::LOCK_EX)
          yield
        end
      rescue Errno::ELOOP, Errno::EISDIR, Errno::EACCES
        raise Error.new("unsafe_destination", "Installation lock is unavailable")
      end

      def validate_ancestry!(root, relative)
        current = root
        File.dirname(relative).split("/").each do |component|
          current = File.join(current, component)
          stat = File.lstat(current)
          unless stat.directory? && !stat.symlink?
            raise Error.new("unsafe_destination", "Installation ancestry is not a real directory")
          end
        rescue Errno::ENOENT
          break
        end
      end

      def destination(root, relative)
        raise Error.new("path_escape", "Managed path is not canonical") if Pathname.new(relative).absolute?

        clean = Pathname.new(relative).cleanpath.to_s
        raise Error.new("path_escape", "Managed path escapes the installation root") if clean == ".." || clean.start_with?("../")

        path = File.expand_path(clean, root)
        raise Error.new("path_escape", "Managed path escapes the installation root") unless path.start_with?("#{root}/")

        path
      end

      def regular_without_symlink?(path)
        stat = File.lstat(path)
        stat.file? && !stat.symlink?
      rescue Errno::ENOENT
        false
      end

      def file_digest(path)
        "sha256:#{Digest::SHA256.file(path).hexdigest}"
      end

      def cli!(*command, expected_command:, stdin_data: "")
        stdout = command!(*command, chdir: @cwd, stdin_data: stdin_data)
        document = Kos::JsonParser.parse(stdout)
        unless document.is_a?(Hash) && document["schema_version"] == "1" &&
            document["command"] == expected_command &&
            document.key?("data") && !document.key?("error")
          raise Error.new("cli_failed", "KOS CLI returned an invalid result")
        end
        document.fetch("data")
      rescue JSON::ParserError
        raise Error.new("cli_failed", "KOS CLI returned malformed JSON")
      end

      def git(*arguments, chdir: @cwd)
        command!("git", *arguments, chdir: chdir)
      rescue Error => error
        raise error if error.code != "command_failed"

        raise Error.new("repository_invalid", "Git repository inspection failed")
      end

      def command!(*command, chdir:, stdin_data: "", environment: {}, unset_environment: false)
        result = @runner.capture(*command, chdir: chdir, stdin_data: stdin_data,
          environment: environment.merge("PATH" => @environment.fetch("PATH", "")),
          unset_environment: unset_environment)
        raise Error.new("command_timeout", "Required command exceeded its timeout") if result.timed_out
        unless result.status.success?
          label = ([ File.basename(command.first), *command.drop(1) ]).join(" ")
          raise Error.new("command_failed", "Required command failed: #{label}")
        end

        result.stdout
      end
    end

    class Application
      def initialize(arguments, stdin: $stdin, stdout: $stdout, stderr: $stderr, installer: nil)
        @arguments = arguments
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr
        @installer = installer || Installer.new
      end

      def run
        operation, options = parse_arguments
        request = read_request(options.fetch("--input"))
        result = if operation == "plan"
          @installer.plan(request)
        else
          @installer.apply(request, approved_plan: options.fetch("--approved-plan"), force: options.fetch("--force", false))
        end
        @stdout.puts(JSON.generate(result))
        0
      rescue Error, JSON::ParserError, KeyError, SystemCallError => error
        operation = %w[plan apply].include?(@arguments.first) ? @arguments.first : "unknown"
        code = error.respond_to?(:code) ? error.code : "malformed_input"
        @stderr.puts(error.message)
        @stdout.puts(JSON.generate("schema_version" => "1", "operation" => operation,
          "error" => { "code" => code, "message" => error.message, "retryable" => false }))
        2
      end

      private

      def parse_arguments
        arguments = @arguments.dup
        operation = arguments.shift
        raise Error.new("malformed_input", "Operation must be plan or apply") unless %w[plan apply].include?(operation)

        options = {}
        until arguments.empty?
          option = arguments.shift
          if %w[--json --force].include?(option)
            raise Error.new("malformed_input", "Duplicate or invalid option") if options.key?(option)
            options[option] = true
          elsif %w[--input --approved-plan].include?(option) && arguments.first && !arguments.first.start_with?("--")
            raise Error.new("malformed_input", "Duplicate option") if options.key?(option)
            options[option] = arguments.shift
          else
            raise Error.new("malformed_input", "Arguments are malformed")
          end
        end
        raise Error.new("malformed_input", "--json and --input are required") unless options["--json"] && options["--input"]
        if operation == "apply" && !options["--approved-plan"]
          raise Error.new("malformed_input", "apply requires --approved-plan")
        end
        if operation == "plan" && (options["--approved-plan"] || options["--force"])
          raise Error.new("malformed_input", "plan does not accept apply options")
        end
        [ operation, options ]
      end

      def read_request(path)
        content = path == "-" ? @stdin.read : File.binread(path)
        value = Kos::JsonParser.parse(content)
        raise JSON::ParserError unless value.is_a?(Hash)

        value
      end
    end
  end
end
