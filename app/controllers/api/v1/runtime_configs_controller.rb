module Api
  module V1
    class RuntimeConfigsController < BaseController
      def show
        return render_malformed_input if request.query_parameters.any?

        body = {}
        return unless validate_request!(body)

        render_success(Serializer.runtime_config(RuntimeConfig.current))
      end

      def update
        body = mutation_body
        return if performed?

        execute_mutation(body, status: :ok, serialize: Serializer.method(:runtime_config)) do
          RuntimeConfiguration::Update.call(retrospective_enabled: body.fetch("retrospective_enabled"),
            expected_lock_version: body.fetch("expected_lock_version"))
        end
      end
    end
  end
end
