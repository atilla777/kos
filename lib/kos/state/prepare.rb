require_relative "backup"
require_relative "layout"
require_relative "schema_status"
require_relative "service_lock"

module Kos
  module State
    class Prepare
      def self.call
        new.call
      end

      def initialize(layout: Layout.resolve, connection_pool: ActiveRecord::Base.connection_pool)
        @layout = layout
        @connection_pool = connection_pool
      end

      def call
        @layout.prepare!
        lock = ServiceLock.new(@layout).acquire_exclusive
        database_existed = @layout.database_present?
        @layout.create_database! unless database_existed
        @layout.validate_database!
        connection = @connection_pool.lease_connection
        connection.raw_connection

        context = @connection_pool.migration_context
        status = SchemaStatus.new(context)
        status.validate_no_unknown!
        create_backup!(status, connection) if database_existed && status.pending_versions.any?
        migrate!(context)
        SchemaStatus.new(@connection_pool.migration_context).validate_compatible!
      rescue ActiveRecord::MigrationError, ActiveRecord::StatementInvalid, SQLite3::Exception => error
        current_version = current_schema_version
        raise Error, "state preparation failed at schema version #{current_version}: #{error.message}"
      ensure
        @connection_pool.release_connection if connection
        lock&.close
      end

      private

      def create_backup!(status, connection)
        Backup.new(@layout, source_connection: connection).create!(schema_version: status.current_version)
      end

      def migrate!(context)
        context.migrate
      rescue StandardError => error
        raise Error, "state preparation failed at schema version #{current_schema_version}: #{error.message}"
      end

      def current_schema_version
        SchemaStatus.new(@connection_pool.migration_context).current_version
      rescue ActiveRecord::ActiveRecordError, SQLite3::Exception
        0
      end
    end
  end
end
