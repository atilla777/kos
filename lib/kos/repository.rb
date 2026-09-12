require "digest"
require "json"
require "json_schemer"
require "open3"
require "pathname"
require "tempfile"
require "timeout"
require "tmpdir"
require "uri"

require_relative "json_parser"

module Kos
  module Repository
    class Error < StandardError
      attr_reader :category, :code, :retryable

      def initialize(category, code, message, retryable: false)
        @category = category
        @code = code
        @retryable = retryable
        super(message)
      end
    end

    class Schema
      PATH = File.expand_path("../../schemas/repository/v1/adapter.json", __dir__)

      def initialize
        document = JSON.parse(File.read(PATH))
        @schema = JSONSchemer.schema(document)
      end

      def valid?(definition, value)
        @schema.ref("#/$defs/#{definition}").valid?(value)
      end
    end

    class Git
      Result = Data.define(:stdout, :success)
      TIMEOUT_SECONDS = 30
      OUTPUT_LIMIT = 4 * 1024 * 1024
      ENVIRONMENT = {
        "PATH" => ENV.fetch("PATH", "/usr/bin:/bin"),
        "LC_ALL" => "C",
        "GIT_CONFIG_NOSYSTEM" => "1",
        "GIT_CONFIG_GLOBAL" => "/dev/null",
        "GIT_TERMINAL_PROMPT" => "0",
        "GIT_PAGER" => "cat",
        "GIT_NO_LAZY_FETCH" => "1"
      }.freeze
      BASE_ARGUMENTS = [ "git", "--no-replace-objects", "-c", "color.ui=false", "-c",
        "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", "-c", "core.splitIndex=false", "-c",
        "commit.gpgSign=false" ].freeze

      def call(*arguments, timeout: TIMEOUT_SECONDS, environment: {}, stdin: File::NULL)
        stdout = Tempfile.new("kos-repository-out")
        stderr = Tempfile.new("kos-repository-err")
        pid = Process.spawn(ENVIRONMENT.merge(environment), *BASE_ARGUMENTS, *arguments, out: stdout, err: stderr,
          in: stdin, unsetenv_others: true, pgroup: true, rlimit_fsize: OUTPUT_LIMIT)
        status = wait(pid, timeout)
        stdout.rewind
        output = stdout.read(OUTPUT_LIMIT) || +""
        Result.new(output.force_encoding(Encoding::UTF_8), status.success?)
      ensure
        stdout&.close!
        stderr&.close!
      end

      private

      def wait(pid, timeout)
        Timeout.timeout(timeout) { Process.wait2(pid).last }
      rescue Timeout::Error
        terminate(pid)
        raise Error.new("transient", "git_timeout", "Git operation timed out", retryable: true)
      end

      def terminate(pid)
        Process.kill("TERM", -pid)
        Timeout.timeout(1) { Process.wait(pid) }
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      rescue Timeout::Error
        Process.kill("KILL", -pid)
        Process.wait(pid)
      end
    end

    class Operation
      def initialize(request, git: Git.new)
        @request = request
        @repository = request.fetch("repository")
        @git = git
      end

      private

      attr_reader :repository, :request

      def validate_repository!
        common = repository.fetch("git_common_dir")
        validation!("repository_invalid", "Git common directory is not canonical") unless
          canonical_existing(common) == common && File.directory?(common)
        observed_common = git_common("rev-parse", "--path-format=absolute", "--git-common-dir")
        validation!("repository_invalid", "Git common directory identity does not match") unless
          observed_common.success && canonical_existing(observed_common.stdout.strip) == common &&
          observed_common.stdout.strip == common
        validation!("repository_ref_invalid", "Repository refs are invalid") unless valid_ref?(repository.fetch("base_ref"))
        validation!("repository_format_unsupported", "Repository does not use SHA-1 object IDs") unless
          git_common("rev-parse", "--show-object-format").then { |result| result.success && result.stdout.strip == "sha1" }
      end

      def valid_ref?(ref)
        @git.call("check-ref-format", ref).success
      end

      def with_lock
        path = File.join(repository.fetch("git_common_dir"), "kos-repository.lock")
        validation!("repository_lock_invalid", "Repository adapter lock is not a regular file") if
          path_exists?(path) && (File.symlink?(path) || !File.file?(path))
        flags = File::RDWR | File::CREAT
        flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
        File.open(path, flags, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        end
      rescue Errno::ELOOP, Errno::EACCES
        validation!("repository_lock_invalid", "Repository adapter lock is unavailable")
      end

      def git_common(*arguments)
        @git.call("--git-dir=#{repository.fetch('git_common_dir')}", *arguments)
      end

      def canonical_existing(path)
        pathname = Pathname.new(path)
        return unless pathname.absolute? && pathname.cleanpath.to_s == path && !path.include?("\0")

        pathname.realpath.to_s
      rescue Errno::EACCES, Errno::ENOENT, Errno::ENOTDIR, Errno::ELOOP
        nil
      end

      def path_exists?(path)
        File.lstat(path)
        true
      rescue Errno::ENOENT, Errno::ENOTDIR
        false
      end

      def canonical_json(value)
        case value
        when Hash
          "{#{value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(',')}}"
        when Array then "[#{value.map { |item| canonical_json(item) }.join(',')}]"
        else JSON.generate(value)
        end
      end

      def validation!(code, message)
        raise Error.new("validation", code, message)
      end

      def conflict!(code, message)
        raise Error.new("conflict", code, message)
      end

      def transient!(code, message)
        raise Error.new("transient", code, message, retryable: true)
      end

      def internal!(code, message)
        raise Error.new("internal", code, message)
      end
    end

    class Worktree < Operation
      MARKER_NAME = "kos-reservation.json"
      OPERATION_PATHS = %w[MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD REBASE_HEAD rebase-apply rebase-merge sequencer
        BISECT_LOG].freeze

      def initialize(request, git: Git.new)
        super
        @reservation = request.fetch("reservation")
        @expected_head = request.fetch("expected_head_sha")
      end

      def call
        validate_identity!
        return observe if operation == "observe"

        with_lock { operation == "materialize" ? materialize : remove }
      end

      private

      attr_reader :repository, :reservation

      def operation
        @request.fetch("operation")
      end

      def materialize
        current = observe
        return current if current.fetch("state") == "clean"
        conflict!("worktree_mismatched", "Reserved worktree path is already occupied") unless current.fetch("state") == "absent"

        verify_base!
        conflict!("branch_exists", "Reserved branch already exists") if branch_exists?
        result = git_common("worktree", "add", "--lock", "--reason", "kos:#{reservation.fetch('id')}",
          "-b", reservation.fetch("branch"), reservation.fetch("path"), @expected_head)
        git_failure!("worktree_materialization_failed", result) unless result.success
        write_marker!
        observed = observe
        internal!("worktree_verification_failed", "Materialized worktree failed verification") unless
          observed.fetch("state") == "clean"

        observed
      end

      def remove
        current = observe
        return current unless current.fetch("state") == "clean"

        unlock_if_needed!
        result = git_common("worktree", "remove", reservation.fetch("path"))
        git_failure!("worktree_removal_failed", result) unless result.success
        observed = observe
        internal!("worktree_removal_unverified", "Removed worktree is still present") unless
          observed.fetch("state") == "absent"

        observed
      end

      def observe
        path = reservation.fetch("path")
        return evidence("absent") unless File.exist?(path) || File.symlink?(path)
        return evidence("mismatched") if File.symlink?(path) || !File.directory?(path)

        head = inspect_identity
        return evidence("mismatched") unless head

        state = dirty? ? "dirty" : "clean"
        evidence(state, "head_sha" => head, "git_common_dir_digest" => common_dir_digest)
      rescue Errno::EACCES, Errno::ENOENT, Errno::ENOTDIR
        evidence("mismatched")
      end

      def inspect_identity
        path = reservation.fetch("path")
        return unless canonical_existing(path) == path

        common = git_worktree(path, "rev-parse", "--path-format=absolute", "--git-common-dir")
        branch = git_worktree(path, "symbolic-ref", "-q", "HEAD")
        head = git_worktree(path, "rev-parse", "--verify", "HEAD^{commit}")
        return unless common.success && branch.success && head.success
        return unless canonical_existing(common.stdout.strip) == repository.fetch("git_common_dir")
        return unless branch.stdout.strip == "refs/heads/#{reservation.fetch('branch')}"
        return unless head.stdout.strip == @expected_head
        return unless marker_matches?(path)

        head.stdout.strip
      end

      def dirty?
        status = git_worktree(reservation.fetch("path"), "status", "--porcelain=v2", "--untracked-files=all",
          "--ignored=matching")
        return true unless status.success && status.stdout.empty?

        OPERATION_PATHS.any? do |name|
          result = git_worktree(reservation.fetch("path"), "rev-parse", "--git-path", name)
          !result.success || File.exist?(result.stdout.strip)
        end
      end

      def marker_matches?(path)
        marker = marker_path(path)
        return false unless marker && File.file?(marker) && !File.symlink?(marker)

        actual = Kos::JsonParser.parse(File.binread(marker))
        actual == marker_document
      rescue JSON::ParserError, SystemCallError
        false
      end

      def write_marker!
        metadata = metadata_path(reservation.fetch("path"))
        internal!("worktree_metadata_invalid", "Worktree metadata is outside the registered repository") unless metadata

        marker = File.join(metadata, MARKER_NAME)
        internal!("worktree_marker_conflict", "Worktree reservation marker already exists") if path_exists?(marker)
        temporary = Tempfile.new([ ".kos-reservation", ".tmp" ], metadata)
        temporary.chmod(0o600)
        temporary.write(JSON.generate(marker_document))
        temporary.flush
        temporary.fsync
        temporary.close
        File.rename(temporary.path, marker)
      ensure
        temporary&.close!
      end

      def marker_document
        { "schema_version" => "1", "repository_id" => repository.fetch("id"),
          "reservation_id" => reservation.fetch("id"), "path" => reservation.fetch("path"),
          "branch" => reservation.fetch("branch") }
      end

      def marker_path(path)
        metadata = metadata_path(path)
        File.join(metadata, MARKER_NAME) if metadata
      end

      def metadata_path(path)
        git_file = File.join(path, ".git")
        return unless File.file?(git_file) && !File.symlink?(git_file) && canonical_existing(git_file) == git_file

        content = File.binread(git_file, 4096)
        match = content.match(/\Agitdir: ([^\0\n]+)\n?\z/)
        return unless match

        supplied = match[1]
        metadata = canonical_existing(supplied)
        return unless metadata == supplied
        return unless metadata_pointer_matches?(metadata, "commondir", repository.fetch("git_common_dir"))
        return unless metadata_pointer_matches?(metadata, "gitdir", git_file)

        root = File.join(repository.fetch("git_common_dir"), "worktrees") + File::SEPARATOR
        metadata if metadata&.start_with?(root)
      rescue Errno::EACCES, Errno::ENOENT, Errno::ENOTDIR
        nil
      end

      def metadata_pointer_matches?(metadata, name, expected)
        pointer = File.join(metadata, name)
        return false unless File.file?(pointer) && !File.symlink?(pointer) && canonical_existing(pointer) == pointer

        value = File.binread(pointer, 4096)
        return false if value.include?("\0") || value.lines.length != 1

        target = File.expand_path(value.strip, metadata)
        canonical_existing(target) == expected && target == expected
      rescue Errno::EACCES, Errno::ENOENT, Errno::ENOTDIR
        false
      end

      def validate_identity!
        validation!("repository_mismatch", "Reservation does not belong to the repository") unless
          reservation.fetch("repository_id") == repository.fetch("id")
        validate_repository!
        parent = File.dirname(reservation.fetch("path"))
        validation!("worktree_path_invalid", "Worktree path is not canonical") unless
          Pathname.new(reservation.fetch("path")).cleanpath.to_s == reservation.fetch("path")
        validation!("worktree_path_invalid", "Worktree parent is not canonical") unless
          canonical_existing(parent) == parent && File.directory?(parent)
        validation!("repository_ref_invalid", "Repository refs are invalid") unless
          valid_ref?("refs/heads/#{reservation.fetch('branch')}")
      end

      def unlock_if_needed!
        metadata = metadata_path(reservation.fetch("path"))
        internal!("worktree_metadata_invalid", "Worktree metadata is outside the registered repository") unless metadata

        lock = File.join(metadata, "locked")
        return unless path_exists?(lock)
        internal!("worktree_lock_invalid", "Worktree lock metadata is invalid") if File.symlink?(lock) || !File.file?(lock)

        result = git_common("worktree", "unlock", reservation.fetch("path"))
        git_failure!("worktree_unlock_failed", result) unless result.success
      end

      def verify_base!
        result = git_common("rev-parse", "--verify", "#{repository.fetch('base_ref')}^{commit}")
        conflict!("base_ref_moved", "Registered base ref does not match expected HEAD") unless
          result.success && result.stdout.strip == @expected_head
      end

      def branch_exists?
        git_common("show-ref", "--verify", "--quiet", "refs/heads/#{reservation.fetch('branch')}").success
      end

      def git_worktree(path, *arguments)
        @git.call("-C", path, *arguments)
      end

      def common_dir_digest
        "sha256:#{Digest::SHA256.hexdigest(repository.fetch('git_common_dir'))}"
      end

      def evidence(state, fields = {})
        document = { "schema_version" => "1", "repository_id" => repository.fetch("id"),
          "reservation_id" => reservation.fetch("id"), "fencing_token" => reservation.fetch("fencing_token"),
          "path" => reservation.fetch("path"), "branch" => reservation.fetch("branch"), "state" => state }.merge(fields)
        fields.merge("state" => state, "evidence_digest" => "sha256:#{Digest::SHA256.hexdigest(canonical_json(document))}")
      end

      def git_failure!(code, result)
        category = result.success ? "internal" : "conflict"
        raise Error.new(category, code, "Git rejected the worktree operation")
      end
    end

    class Commit < Worktree
      DIRECTORY_FLAG = 0o200000

      def call
        with_lock do
          validate_identity!
          validate_commit_identity!
          verify_worktree!
          validate_paths!
          validate_message!
          verify_index_clean!
          verify_no_unfinished_operation!
          verify_no_filters!
          verify_diff!
          create_commit
        end
      end

      private

      def validate_commit_identity!
        validation!("task_mismatch", "Task number does not match the reserved branch") unless
          reservation.fetch("branch") == "kos/task-#{request.fetch('task_number')}"
      end

      def validate_paths!
        validation!("commit_path_invalid", "Commit paths must be unique canonical files") unless
          paths.uniq.length == paths.length

        paths.each do |path|
          valid = !path.start_with?(":") && !Pathname.new(path).absolute? && Pathname.new(path).cleanpath.to_s == path &&
            path != "." && !path.include?("\0") && exact_file?(path)
          validation!("commit_path_invalid", "Commit paths must be unique canonical files") unless valid
        end
        paths.combination(2).each do |first, second|
          overlap = first.start_with?("#{second}/") || second.start_with?("#{first}/")
          validation!("commit_path_invalid", "Commit paths cannot overlap") if overlap
        end
      end

      def exact_file?(path)
        absolute = File.join(reservation.fetch("path"), path)
        if path_exists?(absolute)
          return false unless File.file?(absolute) && !File.symlink?(absolute)

          canonical_existing(absolute) == absolute && [ nil, "100644", "100755" ].include?(expected_tree_mode(path))
        else
          canonical_existing_prefix?(absolute) && tree_file?(path)
        end
      rescue Errno::EACCES, Errno::ENOENT, Errno::ENOTDIR
        false
      end

      def tree_file?(path)
        [ "100644", "100755" ].include?(expected_tree_mode(path))
      end

      def expected_tree_mode(path)
        result = git_worktree_literal("ls-tree", "-z", @expected_head, "--", path)
        return false unless result.success
        return if result.stdout.empty?

        entry, terminator = result.stdout.split("\0", -1)
        match = entry&.match(/\A([0-7]{6}) \S+ [0-9a-f]{40}\t#{Regexp.escape(path)}\z/)
        terminator == "" && match ? match[1] : false
      end

      def canonical_existing_prefix?(absolute)
        current = File.dirname(absolute)
        current = File.dirname(current) until path_exists?(current) || current == reservation.fetch("path")
        contained = current == reservation.fetch("path") || current.start_with?("#{reservation.fetch('path')}/")
        contained && File.directory?(current) &&
          !File.symlink?(current) && canonical_existing(current) == current
      end

      def validate_message!
        file = Tempfile.new("kos-commit-message")
        file.binmode
        file.write(request.fetch("message"))
        file.flush
        result = git_worktree(reservation.fetch("path"), "interpret-trailers", "--parse", "--no-divider", file.path)
        internal!("commit_message_parse_failed", "Commit message validation failed") unless result.success
        validation!("commit_message_invalid", "Commit message already contains a KOS-Task trailer") if
          result.stdout.lines.any? { |line| line.split(":", 2).first&.casecmp?("KOS-Task") }
      ensure
        file&.close!
      end

      def verify_worktree!
        conflict!("worktree_mismatched", "Confirmed worktree identity does not match") unless inspect_identity
      end

      def verify_index_clean!
        result = git_worktree(reservation.fetch("path"), "diff", "--cached", "--quiet", "--no-ext-diff",
          "--no-textconv", @expected_head, "--")
        conflict!("index_not_clean", "Worktree index does not match expected HEAD") unless result.success
      end

      def verify_no_unfinished_operation!
        unfinished = OPERATION_PATHS.any? do |name|
          result = git_worktree(reservation.fetch("path"), "rev-parse", "--git-path", name)
          !result.success || path_exists?(result.stdout.strip)
        end
        conflict!("unfinished_operation", "Worktree has an unfinished Git operation") if unfinished
      end

      def verify_diff!
        verify_no_filters!
        result = git_worktree_literal("diff", "--binary", "--full-index", "--no-ext-diff", "--no-textconv",
          @expected_head, "--", *sorted_paths)
        conflict!("diff_unavailable", "Expected worktree diff could not be read") unless result.success
        conflict!("diff_mismatch", "Worktree diff does not match the request") unless
          digest(result.stdout) == request.fetch("expected_diff_digest")
      end

      def create_commit
        with_temporary_index do |environment|
          seed_temporary_index!(environment)
          stage_requested_paths!(environment)
          verify_no_filters!
          verify_temporary_index!(environment)
          tree_sha = write_tree!(environment)
          verify_exact_tree!(tree_sha)
          commit_sha = create_commit_object!(tree_sha)
          verify_commit_object!(commit_sha, tree_sha)
          advance_branch!(commit_sha)
          reconcile_real_index(commit_sha)
          commit_evidence(commit_sha, tree_sha)
        end
      end

      def with_temporary_index
        directory = Dir.mktmpdir("kos-index")
        path = File.join(directory, "index")
        yield("GIT_INDEX_FILE" => path)
      ensure
        remove_temporary_index(directory, path)
      end

      def remove_temporary_index(directory, path)
        candidates = path ? [ path, "#{path}.lock" ] : []
        candidates.each { |candidate| File.unlink(candidate) if path_exists?(candidate) }
        Dir.rmdir(directory) if directory && File.directory?(directory)
      rescue SystemCallError
        nil
      end

      def seed_temporary_index!(environment)
        result = git_worktree("read-tree", @expected_head, environment: environment)
        internal!("index_invalid", "Temporary index could not be initialized") unless result.success
      end

      def stage_requested_paths!(environment)
        sorted_paths.each do |path|
          absolute = File.join(reservation.fetch("path"), path)
          path_exists?(absolute) ? stage_file!(path, environment) : stage_deletion!(path, environment)
        end
      end

      def stage_file!(path, environment)
        with_staging_file(path) do |file, stat|
          object = git_worktree("hash-object", "--no-filters", "-w", "--stdin", stdin: file)
          conflict!("staging_failed", "Requested file could not be stored") unless
            object.success && object.stdout.strip.match?(/\A[0-9a-f]{40}\z/)
          update_temporary_index!(path, staged_mode(path, stat), object.stdout.strip, environment)
        end
      rescue SystemCallError
        conflict!("staging_failed", "Requested file changed during staging")
      end

      def with_staging_file(path)
        conflict!("staging_failed", "Safe descriptor traversal is unavailable") unless
          defined?(File::NOFOLLOW) && File.directory?("/proc/self/fd")

        descriptors = []
        root = File.open(reservation.fetch("path"), File::RDONLY | File::NOFOLLOW | DIRECTORY_FLAG)
        descriptors << root
        conflict!("staging_failed", "Reserved worktree descriptor identity changed") unless
          File.realpath(descriptor_path(root)) == reservation.fetch("path")

        components = path.split("/")
        components[0...-1].each do |component|
          parent = descriptors.last
          descriptors << open_relative_component(parent, component, directory: true)
        end
        file = open_relative_component(descriptors.last, components.last, directory: false)
        descriptors << file
        stat = file.stat
        conflict!("staging_failed", "Requested path is not a regular file") unless stat.file?

        yield(file, stat)
      ensure
        descriptors&.reverse_each { |descriptor| descriptor.close unless descriptor.closed? }
      end

      def open_relative_component(parent, component, directory:)
        flags = File::RDONLY | File::NOFOLLOW
        flags |= DIRECTORY_FLAG if directory
        File.open(File.join(descriptor_path(parent), component), flags)
      end

      def descriptor_path(file)
        "/proc/self/fd/#{file.fileno}"
      end

      def stage_deletion!(path, environment)
        conflict!("staging_failed", "Requested deletion is not a tracked regular file") unless tree_file?(path)

        result = git_worktree_literal("update-index", "--force-remove", "--", path, environment: environment)
        conflict!("staging_failed", "Requested deletion could not be staged") unless result.success
      end

      def update_temporary_index!(path, mode, object, environment)
        result = git_worktree_literal("update-index", "--add", "--cacheinfo", mode, object, path,
          environment: environment)
        conflict!("staging_failed", "Requested file could not be staged") unless result.success
      end

      def staged_mode(path, stat)
        expected_mode = expected_tree_mode(path)
        unless core_filemode?
          return expected_mode if %w[100644 100755].include?(expected_mode)

          return "100644"
        end

        (stat.mode & 0o100).positive? ? "100755" : "100644"
      end

      def core_filemode?
        return @core_filemode unless @core_filemode.nil?

        result = git_worktree("config", "--type=bool", "--get", "core.filemode")
        @core_filemode = !result.success || result.stdout.strip == "true"
      end

      def verify_no_filters!
        result = git_worktree_literal("check-attr", "-z", "filter", "--", *sorted_paths)
        conflict!("filter_check_failed", "Git attributes could not be verified") unless result.success

        attributes = result.stdout.split("\0", -1)
        conflict!("filter_check_failed", "Git returned invalid filter attributes") unless
          attributes.pop == "" && attributes.length == sorted_paths.length * 3
        attributes.each_slice(3) do |path, attribute, value|
          valid = sorted_paths.include?(path) && attribute == "filter" && %w[unspecified unset].include?(value)
          conflict!("commit_filter_unsupported", "Requested paths use unsupported Git filters") unless valid
        end
      end

      def verify_temporary_index!(environment)
        entries = staged_entries(environment)
        conflict!("index_mismatch", "Staged index does not match the request") unless
          digest(entries) == request.fetch("expected_index_digest")
      end

      def staged_entries(environment)
        result = git_worktree_literal("ls-files", "--stage", "-z", "--", *sorted_paths,
          environment: environment)
        conflict!("index_unavailable", "Staged index could not be read") unless result.success

        result.stdout.split("\0", -1).reject(&:empty?).map do |entry|
          match = entry.match(/\A([0-7]{6}) ([0-9a-f]{40}) 0\t(.+)\z/m)
          internal!("index_invalid", "Staged index contained an invalid entry") unless match
          "#{match[1]} #{match[2]}\t#{match[3]}"
        end.sort_by(&:b).join("\0").then { |entries| entries.empty? ? entries : "#{entries}\0" }
      end

      def write_tree!(environment)
        result = git_worktree("write-tree", environment: environment)
        conflict!("index_unavailable", "Staged tree could not be created") unless result.success

        result.stdout.strip
      end

      def verify_exact_tree!(tree_sha)
        result = git_worktree_literal("diff-tree", "--no-commit-id", "--name-only", "--no-ext-diff",
          "--no-textconv", "-r", "-z", @expected_head, tree_sha, "--")
        conflict!("index_unavailable", "Staged tree could not be verified") unless result.success
        changed = result.stdout.split("\0", -1).reject(&:empty?).sort_by(&:b)
        conflict!("empty_commit", "Requested files contain no staged changes") if changed.empty?
        conflict!("commit_paths_mismatch", "Staged tree does not exactly match the request") unless changed == sorted_paths
      end

      def create_commit_object!(tree_sha)
        message = Tempfile.new("kos-authoritative-message")
        message.binmode
        message.write("#{request.fetch('message').sub(/\n*\z/, '')}\n\nKOS-Task: #{request.fetch('task_number')}\n")
        message.flush
        result = git_worktree("commit-tree", tree_sha, "-p", @expected_head, "-F", message.path)
        conflict!("commit_failed", "Git rejected the commit operation") unless result.success
        result.stdout.strip
      ensure
        message&.close!
      end

      def verify_commit_object!(commit_sha, tree_sha)
        parent = git_worktree("rev-parse", "#{commit_sha}^")
        tree = git_worktree("rev-parse", "#{commit_sha}^{tree}")
        trailers = git_worktree("show", "-s", "--format=%(trailers:key=KOS-Task,valueonly)", commit_sha)
        parsed_trailers = trailers.stdout.lines.map(&:strip).reject(&:empty?)
        valid = parent.success && parent.stdout.strip == @expected_head && tree.success && tree.stdout.strip == tree_sha &&
          trailers.success && parsed_trailers == [ request.fetch("task_number") ]
        internal!("commit_verification_failed", "Created commit failed verification") unless valid
      end

      def advance_branch!(commit_sha)
        result = update_reserved_ref(commit_sha)
        return if result&.success

        recover_ref_update(commit_sha)
      end

      def update_reserved_ref(commit_sha)
        git_common("update-ref", "--no-deref", reserved_ref, commit_sha, @expected_head)
      rescue Error
        nil
      end

      def recover_ref_update(commit_sha)
        observed = observe_ref_safely
        return if observed == commit_sha
        transient!("ref_update_uncertain", "Reserved branch update could not be observed") unless observed
        conflict!("ref_moved", "Reserved branch moved before commit") unless observed == @expected_head
        conflict!("ref_update_failed", "Git rejected the branch update")
      end

      def observe_ref_safely
        observed_ref
      rescue Error
        nil
      end

      def observed_ref
        result = git_common("rev-parse", "--verify", "#{reserved_ref}^{commit}")
        result.stdout.strip if result.success
      end

      def reserved_ref
        "refs/heads/#{reservation.fetch('branch')}"
      end

      def reconcile_real_index(commit_sha)
        index = git_worktree("rev-parse", "--git-path", "index")
        return unless index.success

        index_path = index.stdout.strip
        return unless File.file?(index_path) && !File.symlink?(index_path) && canonical_existing(index_path) == index_path

        update_real_index(index_path, commit_sha)
      rescue Error, SystemCallError
        nil
      end

      def update_real_index(index_path, commit_sha)
        lock_path = "#{index_path}.lock"
        owned_lock = false
        flags = File::WRONLY | File::CREAT | File::EXCL
        flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
        File.open(lock_path, flags, 0o600) do |lock|
          owned_lock = true
          File.open(index_path, "rb") { |index| IO.copy_stream(index, lock) }
          lock.flush
          lock.fsync
        end
        result = git_worktree_literal("reset", commit_sha, "--", *sorted_paths,
          environment: { "GIT_INDEX_FILE" => lock_path })
        return File.unlink(lock_path) unless result.success

        File.rename(lock_path, index_path)
      rescue Error, SystemCallError
        nil
      ensure
        File.unlink(lock_path) if owned_lock && path_exists?(lock_path)
      end

      def commit_evidence(commit_sha, tree_sha)
        document = { "schema_version" => "1", "repository_id" => repository.fetch("id"),
          "reservation_id" => reservation.fetch("id"), "fencing_token" => reservation.fetch("fencing_token"),
          "path" => reservation.fetch("path"), "branch" => reservation.fetch("branch"),
          "parent_sha" => @expected_head, "tree_sha" => tree_sha, "commit_sha" => commit_sha,
          "paths" => sorted_paths, "expected_diff_digest" => request.fetch("expected_diff_digest"),
          "expected_index_digest" => request.fetch("expected_index_digest"),
          "task_number" => request.fetch("task_number") }
        { "commit_sha" => commit_sha, "evidence_digest" => digest(canonical_json(document)) }
      end

      def paths
        request.fetch("paths")
      end

      def sorted_paths
        @sorted_paths ||= paths.sort_by(&:b)
      end

      def digest(bytes)
        "sha256:#{Digest::SHA256.hexdigest(bytes)}"
      end

      def git_worktree(*arguments, environment: {}, stdin: File::NULL)
        arguments.shift if arguments.first == reservation.fetch("path")
        @git.call("-C", reservation.fetch("path"), *arguments, environment: environment, stdin: stdin)
      end

      def git_worktree_literal(*arguments, environment: {}, stdin: File::NULL)
        @git.call("--literal-pathspecs", "-C", reservation.fetch("path"), *arguments,
          environment: environment, stdin: stdin)
      end
    end

    class Fetch < Operation
      FETCH_HEAD_LIMIT = 16 * 1024
      FORBIDDEN_CONFIG = [ /\Aurl\..*\.(?:insteadof|pushinsteadof)\z/i,
        /\Aremote\..*\.(?:vcs|uploadpack|proxy|promisor|partialclonefilter)\z/i,
        /\Acore\.(?:gitproxy|sshcommand|alternaterefscommand|askpass)\z/i,
        /\A(?:fetch|transfer)\.bundleuri\z/i, /\Abundle\..*\.uri\z/i,
        /\Ahttp(?:\..+)?\.(?:proxy|curloptresolve|followredirects)\z/i,
        /\Apromisor\.acceptfromserver\z/i, /\Aextensions\.partialclone\z/i ].freeze
      TRUSTED_SCHEMES = %w[https ssh git file].freeze

      def call
        validate_repository!
        with_lock do
          validate_repository!
          validate_request_digest!
          validate_trusted_url!
          validate_authority!
          validate_remote_configuration!
          validate_fetch_head!
          fetch
        end
      end

      private

      def validate_request_digest!
        observed = "sha256:#{Digest::SHA256.hexdigest(canonical_json(effect_request))}"
        validation!("effect_request_mismatch", "Effect request digest does not match") unless
          observed == request.dig("effect", "request_digest")
      end

      def validate_trusted_url!
        uri = URI.parse(repository.fetch("trusted_remote_url"))
        userinfo = uri.userinfo && URI::DEFAULT_PARSER.unescape(uri.userinfo)
        valid_userinfo = userinfo.nil? || (uri.scheme == "ssh" && !userinfo.empty? &&
          !userinfo.match?(/[:\/@?#\x00-\x1f\x7f]/))
        valid = uri.absolute? && !uri.opaque && TRUSTED_SCHEMES.include?(uri.scheme) &&
          uri.query.nil? && uri.fragment.nil? && valid_userinfo
        if uri.scheme == "file"
          valid &&= !uri.path.to_s.empty? && uri.path.start_with?("/")
        else
          valid &&= !uri.host.to_s.empty?
        end
        validation!("fetch_configuration_invalid", "Trusted remote URL is invalid") unless valid
      rescue URI::Error
        validation!("fetch_configuration_invalid", "Trusted remote URL is invalid")
      end

      def validate_authority!
        validation!("repository_mismatch", "Repository effect does not belong to the repository") unless
          request.dig("effect", "repository_id") == repository.fetch("id")
        validation!("fetch_remote_mismatch", "Fetch remote does not match registered trust") unless
          remote == repository.fetch("trusted_remote")
        validation!("fetch_ref_mismatch", "Fetch ref does not match the registered base ref") unless
          ref == repository.fetch("base_ref")
      end

      def validate_remote_configuration!
        configured = git_common("config", "--null", "--get-all", "remote.#{remote}.url")
        urls = nul_values(configured)
        validation!("fetch_configuration_invalid", "Trusted remote configuration does not match") unless
          configured.success && urls == [ repository.fetch("trusted_remote_url") ]

        names = git_common("config", "--name-only", "--null", "--list")
        validation!("fetch_configuration_invalid", "Repository configuration could not be verified") unless names.success
        validation!("fetch_configuration_invalid", "Repository configuration contains a fetch override") if
          nul_values(names).any? { |name| FORBIDDEN_CONFIG.any? { |pattern| pattern.match?(name) } }
      end

      def fetch
        result = git_common("-c", "credential.helper=", "-c", "http.followRedirects=false",
          "-c", "promisor.acceptFromServer=none",
          "fetch", "--no-append", "--no-tags", "--no-prune",
          "--no-prune-tags", "--no-recurse-submodules", "--no-auto-maintenance", "--no-write-commit-graph",
          "--no-update-shallow", "--refmap=", "--upload-pack=git-upload-pack",
          repository.fetch("trusted_remote_url"), ref)
        transient!("fetch_failed", "Trusted fetch failed") unless result.success

        observed_oid = observed_fetch_oid
        document = { "schema_version" => "1", "repository" => repository, "effect" => request.fetch("effect"),
          "remote" => remote, "ref" => ref, "observed_oid" => observed_oid }
        { "remote" => remote, "ref" => ref, "observed_oid" => observed_oid,
          "evidence_digest" => "sha256:#{Digest::SHA256.hexdigest(canonical_json(document))}" }
      end

      def observed_fetch_oid
        validate_fetch_head!
        content = File.binread(fetch_head_path, FETCH_HEAD_LIMIT + 1)
        internal!("fetch_result_invalid", "Fetch result could not be verified") if content.bytesize > FETCH_HEAD_LIMIT
        match = content.match(/\A([0-9a-f]{40})\t\t([^\0\r\n]+)(?:\n)?\z/)
        internal!("fetch_result_invalid", "Fetch result could not be verified") unless match
        expected_description = "branch '#{ref.delete_prefix('refs/heads/')}' of "
        internal!("fetch_result_invalid", "Fetch result does not match the requested ref") unless
          match[2].start_with?(expected_description)

        oid = match[1]
        object = git_common("cat-file", "-t", oid)
        internal!("fetch_result_invalid", "Fetched commit could not be verified") unless
          object.success && object.stdout == "commit\n"

        oid
      rescue SystemCallError
        internal!("fetch_result_invalid", "Fetch result could not be verified")
      end

      def validate_fetch_head!
        return unless path_exists?(fetch_head_path)

        valid = File.file?(fetch_head_path) && !File.symlink?(fetch_head_path) &&
          canonical_existing(fetch_head_path) == fetch_head_path
        validation!("fetch_configuration_invalid", "Fetch observation path is invalid") unless valid
      end

      def fetch_head_path
        File.join(repository.fetch("git_common_dir"), "FETCH_HEAD")
      end

      def effect_request
        request.dig("effect", "request")
      end

      def requested_effect
        effect_request.fetch("effect")
      end

      def remote
        requested_effect.fetch("remote")
      end

      def ref
        requested_effect.fetch("ref")
      end

      def nul_values(result)
        values = result.stdout.split("\0", -1)
        values.pop if values.last == ""
        values
      end
    end

    class Application
      EXIT_BY_CATEGORY = { "internal" => 1, "validation" => 2, "conflict" => 6, "transient" => 8 }.freeze

      def initialize(arguments, input: $stdin, stdout: $stdout, stderr: $stderr, schema: Schema.new)
        @arguments = arguments
        @input = input
        @stdout = stdout
        @stderr = stderr
        @schema = schema
      end

      def run
        request = parse
        result = operation(request).call
        write(success_document(request, result))
      rescue Error => error
        write_error(error)
      rescue StandardError
        write_error(Error.new("internal", "internal_error", "Repository adapter failed safely"))
      end

      private

      def operation(request)
        case request.fetch("operation")
        when "commit" then Commit.new(request)
        when "fetch" then Fetch.new(request)
        else Worktree.new(request)
        end
      end

      def success_document(request, result)
        document = { "schema_version" => "1", "operation" => request.fetch("operation"), "outcome" => "succeeded",
          "repository_id" => request.dig("repository", "id") }
        if request.fetch("operation") == "fetch"
          effect = request.fetch("effect")
          document.merge(result).merge("effect_id" => effect.fetch("id"),
            "current_owner_attempt_id" => effect.fetch("current_owner_attempt_id"),
            "fencing_token" => effect.fetch("fencing_token"),
            "effect_request_digest" => effect.fetch("request_digest"))
        else
          reservation = request.fetch("reservation")
          document.merge("reservation_id" => reservation.fetch("id"),
            "fencing_token" => reservation.fetch("fencing_token")).merge(
              request.fetch("operation") == "commit" ? result : { "observation" => result }
            )
        end
      end

      def write_error(error)
        @stderr.puts(error.message)
        write({ "schema_version" => "1", "operation" => known_operation, "outcome" => "failed",
          "error" => { "category" => error.category, "code" => error.code, "message" => error.message,
            "retryable" => error.retryable } })
      end

      def parse
        operation, input_flag, path, json_flag = @arguments
        unless %w[materialize observe remove commit fetch].include?(operation) && input_flag == "--input" && path &&
            json_flag == "--json" && @arguments.length == 4
          raise Error.new("validation", "malformed_input",
            "Usage: kos-repository <materialize|observe|remove|commit|fetch> --input <path|-> --json")
        end
        content = path == "-" ? @input.read : File.binread(path)
        request = Kos::JsonParser.parse(content)
        unless request.is_a?(Hash) && request["operation"] == operation && @schema.valid?("request", request)
          raise Error.new("validation", "malformed_input", "Input does not match the repository adapter contract")
        end

        request
      rescue JSON::ParserError, SystemCallError
        raise Error.new("validation", "malformed_input", "Input must be a readable JSON object")
      end

      def known_operation
        %w[materialize observe remove commit fetch].include?(@arguments.first) ? @arguments.first : "unknown"
      end

      def write(document)
        definition = document.fetch("outcome") == "succeeded" ? "success" : "failure"
        raise "Repository adapter produced an invalid result" unless @schema.valid?(definition, document)

        @stdout.puts(JSON.generate(document))
        document.fetch("outcome") == "succeeded" ? 0 : EXIT_BY_CATEGORY.fetch(document.dig("error", "category"))
      end
    end
  end
end
