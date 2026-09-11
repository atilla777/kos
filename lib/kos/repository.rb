require "digest"
require "json"
require "json_schemer"
require "open3"
require "pathname"
require "tempfile"
require "timeout"

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
        "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false" ].freeze

      def call(*arguments, timeout: TIMEOUT_SECONDS)
        stdout = Tempfile.new("kos-repository-out")
        stderr = Tempfile.new("kos-repository-err")
        pid = Process.spawn(ENVIRONMENT, *BASE_ARGUMENTS, *arguments, out: stdout, err: stderr,
          unsetenv_others: true, pgroup: true, rlimit_fsize: OUTPUT_LIMIT)
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

    class Worktree
      MARKER_NAME = "kos-reservation.json"
      OPERATION_PATHS = %w[MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD REBASE_HEAD rebase-apply rebase-merge sequencer
        BISECT_LOG].freeze

      def initialize(request, git: Git.new)
        @request = request
        @repository = request.fetch("repository")
        @reservation = request.fetch("reservation")
        @expected_head = request.fetch("expected_head_sha")
        @git = git
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
        common = repository.fetch("git_common_dir")
        validation!("repository_invalid", "Git common directory is not canonical") unless
          canonical_existing(common) == common && File.directory?(common)
        observed_common = git_common("rev-parse", "--path-format=absolute", "--git-common-dir")
        validation!("repository_invalid", "Git common directory identity does not match") unless
          observed_common.success && canonical_existing(observed_common.stdout.strip) == common &&
          observed_common.stdout.strip == common
        parent = File.dirname(reservation.fetch("path"))
        validation!("worktree_path_invalid", "Worktree path is not canonical") unless
          Pathname.new(reservation.fetch("path")).cleanpath.to_s == reservation.fetch("path")
        validation!("worktree_path_invalid", "Worktree parent is not canonical") unless
          canonical_existing(parent) == parent && File.directory?(parent)
        validation!("repository_ref_invalid", "Repository refs are invalid") unless
          valid_ref?(repository.fetch("base_ref")) && valid_ref?("refs/heads/#{reservation.fetch('branch')}")
        validation!("repository_format_unsupported", "Repository does not use SHA-1 object IDs") unless
          git_common("rev-parse", "--show-object-format").then { |result| result.success && result.stdout.strip == "sha1" }
      end

      def valid_ref?(ref)
        @git.call("check-ref-format", ref).success
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

      def git_worktree(path, *arguments)
        @git.call("-C", path, *arguments)
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

      def common_dir_digest
        "sha256:#{Digest::SHA256.hexdigest(repository.fetch('git_common_dir'))}"
      end

      def evidence(state, fields = {})
        document = { "schema_version" => "1", "repository_id" => repository.fetch("id"),
          "reservation_id" => reservation.fetch("id"), "fencing_token" => reservation.fetch("fencing_token"),
          "path" => reservation.fetch("path"), "branch" => reservation.fetch("branch"), "state" => state }.merge(fields)
        fields.merge("state" => state, "evidence_digest" => "sha256:#{Digest::SHA256.hexdigest(canonical_json(document))}")
      end

      def canonical_json(value)
        case value
        when Hash
          "{#{value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(',')}}"
        when Array then "[#{value.map { |item| canonical_json(item) }.join(',')}]"
        else JSON.generate(value)
        end
      end

      def git_failure!(code, result)
        category = result.success ? "internal" : "conflict"
        raise Error.new(category, code, "Git rejected the worktree operation")
      end

      def validation!(code, message)
        raise Error.new("validation", code, message)
      end

      def conflict!(code, message)
        raise Error.new("conflict", code, message)
      end

      def internal!(code, message)
        raise Error.new("internal", code, message)
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
        observation = Worktree.new(request).call
        write({ "schema_version" => "1", "operation" => request.fetch("operation"), "outcome" => "succeeded",
          "repository_id" => request.dig("repository", "id"), "reservation_id" => request.dig("reservation", "id"),
          "fencing_token" => request.dig("reservation", "fencing_token"), "observation" => observation })
      rescue Error => error
        write_error(error)
      rescue StandardError
        write_error(Error.new("internal", "internal_error", "Repository adapter failed safely"))
      end

      private

      def write_error(error)
        @stderr.puts(error.message)
        write({ "schema_version" => "1", "operation" => known_operation, "outcome" => "failed",
          "error" => { "category" => error.category, "code" => error.code, "message" => error.message,
            "retryable" => error.retryable } })
      end

      def parse
        operation, input_flag, path, json_flag = @arguments
        unless %w[materialize observe remove].include?(operation) && input_flag == "--input" && path &&
            json_flag == "--json" && @arguments.length == 4
          raise Error.new("validation", "malformed_input",
            "Usage: kos-repository <materialize|observe|remove> --input <path|-> --json")
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
        %w[materialize observe remove].include?(@arguments.first) ? @arguments.first : "unknown"
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
