module Api
  module V1
    class ErrorsController < BaseController
      def not_found
        render_error("not_found", "API endpoint not found.", status: :not_found)
      end
    end
  end
end
