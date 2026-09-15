module Api
  module V2
    class BaseController < Api::V1::BaseController
      COMMANDS = {
        "publication_preflights#show" => "publication_preflight.get",
        "publication_preflights#prepare" => "publication_preflight.prepare",
        "publication_preflights#reconcile" => "publication_preflight.reconcile",
        "publications#prepare_observed" => "publication.prepare_observed",
        "publications#recover_base_moved" => "publication.recover_base_moved",
        "repository_effects#reconcile_rebase" => "effect.reconcile_rebase"
      }.freeze

      private

      def set_request_context
        @request_id = SecureRandom.uuid
        @command = COMMANDS.fetch("#{controller_name}##{action_name}")
      end

      def validate_request!(body)
        logical_request = { "schema_version" => "2", "command" => @command, "body" => body,
          "repository_id" => @repository.id }
        return true if schema_registry.valid?("commands.json", "request", logical_request)

        render_malformed_input
        false
      end

      def mutation_body
        document = Kos::JsonParser.parse(request.raw_post)
        return render_malformed_input unless document.is_a?(Hash)

        if document["schema_version"] && document["schema_version"] != "2"
          render_failure(:bad_request, "validation", "unsupported_schema_version", "Schema version is unsupported")
          return
        end
        return render_malformed_input unless request.query_parameters.empty? &&
          schema_registry.valid?("commands.json", "request", document) && document["command"] == @command &&
          document["repository_id"] == @repository.id

        document.fetch("body")
      rescue JSON::ParserError
        render_malformed_input
      end

      def envelope
        { "schema_version" => "2", "request_id" => @request_id, "command" => @command }
      end

      def schema_registry
        @schema_registry ||= Kos::Cli::SchemaRegistry.new(version: "2")
      end
    end
  end
end
