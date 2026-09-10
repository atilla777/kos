require_relative "layout"
require_relative "schema_status"
require_relative "service_lock"

module Kos
  module State
    class ServerStartup
      class << self
        def call(layout: Layout.resolve, connection_pool: ActiveRecord::Base.connection_pool)
          layout.prepare!
          lease = ServiceLock.new(layout).acquire_shared
          raise Error, "production database does not exist; run kos:state:prepare" unless layout.database_present?

          layout.validate_database!
          SchemaStatus.new(connection_pool.migration_context).validate_compatible!
          @lease = lease
        rescue StandardError
          lease&.close
          raise
        end
      end
    end
  end
end
