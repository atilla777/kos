require_relative "error"

module Kos
  module State
    class SchemaStatus
      attr_reader :known_versions, :applied_versions

      def initialize(migration_context)
        @migration_context = migration_context
        @known_versions = migration_context.migrations.map(&:version)
        @applied_versions = migration_context.get_all_versions
      end

      def current_version
        applied_versions.max || 0
      end

      def pending_versions
        known_versions - applied_versions
      end

      def unknown_versions
        applied_versions - known_versions
      end

      def compatible?
        pending_versions.empty? && unknown_versions.empty?
      end

      def validate_no_unknown!
        return if unknown_versions.empty?

        raise Error, "database contains migration versions unknown to this release: #{unknown_versions.sort.join(", ")}"
      end

      def validate_compatible!
        validate_no_unknown!
        return if pending_versions.empty?

        raise Error, "database has pending migrations: #{pending_versions.sort.join(", ")}"
      end
    end
  end
end
