require "base64"
require "openssl"

module Api
  module V1
    class Cursor
      class Invalid < StandardError; end

      def initialize(command:, scope:, secret: Rails.application.secret_key_base)
        @command = command
        @scope = scope
        @secret = secret
      end

      def decode(value)
        return unless value

        encoded_payload, encoded_signature = value.split(".", 2)
        payload_json = Base64.urlsafe_decode64(encoded_payload)
        signature = Base64.urlsafe_decode64(encoded_signature)
        raise Invalid unless valid_signature?(payload_json, signature)

        payload = JSON.parse(payload_json)
        raise Invalid unless payload.is_a?(Array)

        payload
      rescue ArgumentError, JSON::ParserError, KeyError, TypeError
        raise Invalid
      end

      def encode(position)
        payload = JSON.generate(position)
        [ encode64(payload), encode64(signature(payload)) ].join(".")
      end

      private

      def signature(payload)
        OpenSSL::HMAC.digest("SHA256", @secret, [ @command, @scope, payload ].join("\0")).first(16)
      end

      def valid_signature?(payload, supplied)
        expected = signature(payload)
        supplied.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(supplied, expected)
      end

      def encode64(value)
        Base64.urlsafe_encode64(value, padding: false)
      end
    end
  end
end
