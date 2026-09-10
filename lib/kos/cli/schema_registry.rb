require "json"
require "json_schemer"
require "uri"

module Kos
  module Cli
    class SchemaRegistry
      SCHEMA_DIRECTORY = File.expand_path("../../../schemas/cli/v1", __dir__)

      def initialize
        schemas = Dir[File.join(SCHEMA_DIRECTORY, "*.json")].sort.map do |path|
          JSON.parse(File.read(path))
        end
        registry = schemas.to_h { |schema| [ URI(schema.fetch("$id")), schema ] }
        @schemas = schemas.to_h { |schema| [ File.basename(URI(schema.fetch("$id")).path), schema ] }
        @resolver = registry.to_proc
      end

      def valid?(schema_name, definition_name, value)
        schema(schema_name).ref("#/$defs/#{definition_name}").valid?(value)
      end

      def success_status(command)
        catalog.fetch("x-command-catalog").find { |entry| entry.fetch("identifier") == command }
          .fetch("success_status")
      end

      def error_status(code)
        catalog.fetch("x-error-catalog").find { |entry| entry.fetch("code") == code }.fetch("http_status")
      end

      private

      def schema(name)
        JSONSchemer.schema(@schemas.fetch(name), ref_resolver: @resolver)
      end

      def catalog
        @schemas.fetch("catalog.json")
      end
    end
  end
end
