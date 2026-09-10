require "digest"
require "json"
require "securerandom"
require "sqlite3"
require "time"

require_relative "error"

module Kos
  module State
    class Backup
      def initialize(layout, source_connection:, clock: Time)
        @layout = layout
        @source_connection = source_connection
        @clock = clock
      end

      def create!(schema_version:)
        basename = "kos-#{timestamp}-schema-#{schema_version}.sqlite3"
        backup_path = @layout.backups_path.join(basename)
        temporary_path = @layout.backups_path.join(".#{basename}.#{SecureRandom.hex(8)}.tmp")

        write_backup(temporary_path)
        metadata = verify_backup(temporary_path)
        File.link(temporary_path, backup_path)
        File.unlink(temporary_path)
        sync_directory
        write_manifest(backup_path, schema_version:, **metadata)
        verify_published!(backup_path)
        backup_path
      rescue Error
        raise
      rescue SystemCallError, SQLite3::Exception, JSON::ParserError, KeyError => error
        raise Error, "state backup failed: #{error.message}"
      ensure
        File.unlink(temporary_path) if temporary_path && File.exist?(temporary_path)
      end

      private

      def timestamp
        @clock.now.utc.strftime("%Y%m%dT%H%M%S%6NZ")
      end

      def write_backup(path)
        flags = File::WRONLY | File::CREAT | File::EXCL
        flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
        File.open(path, flags, 0o600) { |file| file.fsync }

        destination = SQLite3::Database.new(path.to_s)
        backup = SQLite3::Backup.new(destination, "main", @source_connection.raw_connection, "main")
        status = backup.step(-1)
        raise Error, "SQLite backup failed with status #{status}" unless status == SQLite3::Constants::ErrorCode::DONE

        backup.finish
        backup = nil
        destination.close
        destination = nil
        File.open(path, File::RDONLY) { |file| file.fsync }
      ensure
        backup&.finish
        destination&.close unless destination&.closed?
      end

      def verify_backup(path)
        database = SQLite3::Database.new(path.to_s, readonly: true)
        result = database.get_first_value("PRAGMA integrity_check")
        raise Error, "SQLite backup failed integrity check" unless result == "ok"

        { byte_size: File.size(path), sha256: Digest::SHA256.file(path).hexdigest }
      ensure
        database&.close
      end

      def write_manifest(backup_path, schema_version:, byte_size:, sha256:)
        manifest_path = Pathname.new("#{backup_path}.json")
        temporary_path = Pathname.new("#{manifest_path}.#{SecureRandom.hex(8)}.tmp")
        manifest = {
          "backup" => backup_path.basename.to_s,
          "source_schema_version" => schema_version,
          "created_at" => @clock.now.utc.iso8601(6),
          "byte_size" => byte_size,
          "sha256" => sha256
        }

        flags = File::WRONLY | File::CREAT | File::EXCL
        flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
        File.open(temporary_path, flags, 0o600) do |file|
          file.write(JSON.generate(manifest) << "\n")
          file.flush
          file.fsync
        end
        File.rename(temporary_path, manifest_path)
        sync_directory
      ensure
        File.unlink(temporary_path) if temporary_path && File.exist?(temporary_path)
      end

      def verify_published!(backup_path)
        manifest = JSON.parse(File.read("#{backup_path}.json"))
        actual_size = File.size(backup_path)
        actual_digest = Digest::SHA256.file(backup_path).hexdigest
        raise Error, "published backup size does not match its manifest" unless manifest.fetch("byte_size") == actual_size
        raise Error, "published backup digest does not match its manifest" unless manifest.fetch("sha256") == actual_digest

        verify_backup(backup_path)
      end

      def sync_directory
        File.open(@layout.backups_path, File::RDONLY) { |directory| directory.fsync }
      end
    end
  end
end
