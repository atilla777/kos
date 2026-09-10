require "pathname"

require_relative "error"

module Kos
  module State
    class Layout
      attr_reader :root_path, :database_path, :backups_path, :locks_path, :service_lock_path

      def self.resolve(environment: ENV)
        root_path = if environment["KOS_STATE_ROOT"]
          absolute_path!(environment["KOS_STATE_ROOT"], "KOS_STATE_ROOT")
        elsif environment["XDG_STATE_HOME"]
          absolute_path!(environment["XDG_STATE_HOME"], "XDG_STATE_HOME").join("kos")
        elsif environment["HOME"]
          absolute_path!(environment["HOME"], "HOME").join(".local/state/kos")
        else
          raise Error, "production state root cannot be resolved"
        end

        database_path = if environment["KOS_DATABASE_PATH"]
          absolute_path!(environment["KOS_DATABASE_PATH"], "KOS_DATABASE_PATH")
        else
          root_path.join("kos.sqlite3")
        end

        new(root_path:, database_path:)
      end

      def self.absolute_path!(value, name)
        path = Pathname.new(value)
        raise Error, "#{name} must be an absolute path" unless path.absolute?

        path.cleanpath
      end
      private_class_method :absolute_path!

      def initialize(root_path:, database_path:, effective_uid: Process.euid)
        @root_path = Pathname.new(root_path)
        @database_path = Pathname.new(database_path)
        @backups_path = @root_path.join("backups")
        @locks_path = @root_path.join("locks")
        @service_lock_path = @locks_path.join("service.lock")
        @effective_uid = effective_uid
      end

      def prepare!
        create_private_directory(root_path)
        create_private_directory(backups_path)
        create_private_directory(locks_path)
        create_private_directory(database_path.dirname) unless database_path.dirname == root_path
        validate_existing_state_files!
        self
      end

      def validate_database!
        validate_private_file!(database_path)
        database_sidecar_paths.each { |path| validate_private_file!(path) if path_present?(path) }
      end

      def create_database!
        flags = File::RDWR | File::CREAT | File::EXCL
        flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
        File.open(database_path, flags, 0o600) do |file|
          validate_open_file!(file, database_path)
          file.fsync
        end
        validate_database!
      rescue Errno::EEXIST
        raise Error, "production database appeared while state was being prepared"
      rescue Errno::ELOOP
        raise Error, "production database must not be a symlink"
      end

      def database_present?
        path_present?(database_path)
      end

      def validate_private_file!(path)
        stat = safe_lstat(path)
        raise Error, "state file is not a regular file: #{path}" unless stat.file?

        validate_private_stat!(stat, path)
        stat
      end

      def validate_open_file!(file, path)
        opened = file.stat
        current = validate_private_file!(path)
        return if opened.dev == current.dev && opened.ino == current.ino

        raise Error, "state file changed while opening: #{path}"
      end

      private

      def validate_existing_state_files!
        database_exists = database_present?
        validate_database! if database_exists
        validate_orphan_sidecars! unless database_exists
        validate_private_file!(service_lock_path) if path_present?(service_lock_path)
        backups_path.children.each { |path| validate_private_file!(path) }
      end

      def validate_orphan_sidecars!
        orphan = database_sidecar_paths.find { |path| path_present?(path) }
        raise Error, "database sidecar exists without its database: #{orphan}" if orphan
      end

      def database_sidecar_paths
        %w[-wal -shm].map { |suffix| Pathname.new("#{database_path}#{suffix}") }
      end

      def path_present?(path)
        path.lstat
        true
      rescue Errno::ENOENT
        false
      end

      def create_private_directory(path)
        verify_no_symlink_components!(path)

        missing_components(path).each do |component|
          Dir.mkdir(component, 0o700)
        rescue Errno::EEXIST
          # A concurrent creator is acceptable only if the resulting object is safe.
        end

        stat = safe_lstat(path)
        raise Error, "state directory is not a directory: #{path}" unless stat.directory?

        validate_private_stat!(stat, path)
      end

      def missing_components(path)
        components = []
        current = path
        until current.exist? || current.root?
          components << current
          current = current.parent
        end
        components.reverse
      end

      def verify_no_symlink_components!(path)
        current = path
        loop do
          validate_path_component!(current) if path_present?(current)
          break if current.root?

          current = current.parent
        end
      end

      def validate_path_component!(path)
        stat = path.lstat
        raise Error, "state path must not contain symlinks: #{path}" if stat.symlink?
        raise Error, "state path component is not a directory: #{path}" unless stat.directory?
        return if (stat.mode & 0o022).zero?
        return if (stat.mode & 0o1000).positive? && [ 0, @effective_uid ].include?(stat.uid)

        raise Error, "state path component is writable by another user: #{path}"
      end

      def safe_lstat(path)
        path.lstat
      rescue Errno::ENOENT
        raise Error, "state object does not exist: #{path}"
      end

      def validate_private_stat!(stat, path)
        raise Error, "state object has a different owner: #{path}" unless stat.uid == @effective_uid
        return if (stat.mode & 0o077).zero?

        raise Error, "state object must not grant group or other permissions: #{path}"
      end
    end
  end
end
