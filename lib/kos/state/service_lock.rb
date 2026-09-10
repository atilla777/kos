require_relative "error"

module Kos
  module State
    class ServiceLock
      def initialize(layout)
        @layout = layout
      end

      def acquire_shared
        acquire(File::LOCK_SH, "service is being prepared")
      end

      def acquire_exclusive
        acquire(File::LOCK_EX, "service is running or state preparation is already active")
      end

      private

      def acquire(operation, conflict_message)
        flags = File::RDWR | File::CREAT
        flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
        file = File.open(@layout.service_lock_path, flags, 0o600)
        @layout.validate_open_file!(file, @layout.service_lock_path)

        return file if file.flock(operation | File::LOCK_NB)

        file.close
        raise Error, conflict_message
      rescue Errno::ELOOP
        file&.close
        raise Error, "service lock must not be a symlink"
      rescue Error
        file&.close
        raise
      rescue SystemCallError => error
        file&.close
        raise Error, "service lock cannot be opened safely: #{error.message}"
      end
    end
  end
end
