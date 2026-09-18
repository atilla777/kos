class ApplicationController < ActionController::API
  before_action :authenticate_api_token

  private

  def authenticate_api_token
    scheme, token = request.authorization.to_s.split(" ", 2)
    expected_token = Rails.application.config.x.kos.api_token

    return if scheme&.casecmp?("Bearer") && token.present? &&
      ActiveSupport::SecurityUtils.secure_compare(token, expected_token)

    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
