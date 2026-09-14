require "uri"

module Kos
  module GitUrl
    class Invalid < StandardError; end

    SCHEMES = %w[https ssh git file].freeze
    SCP_LIKE = /\A(?:(?<user>[^@\/:]+)@)?(?<host>(?:\[[^\]]+\]|[^\/:]+)):(?<path>.+)\z/
    USERINFO_FORBIDDEN = /[:\/@?#\x00-\x1f\x7f]/

    def self.normalize(value)
      raise Invalid unless value.is_a?(String) && !value.empty? && !value.include?("\0")

      candidate = scp_like(value) || value
      uri = URI.parse(candidate).normalize
      userinfo = uri.userinfo && URI::DEFAULT_PARSER.unescape(uri.userinfo)
      valid_userinfo = userinfo.nil? || (uri.scheme == "ssh" && !userinfo.empty? &&
        !userinfo.match?(USERINFO_FORBIDDEN))
      valid = uri.absolute? && !uri.opaque && SCHEMES.include?(uri.scheme) &&
        uri.query.nil? && uri.fragment.nil? && valid_userinfo
      valid &&= uri.scheme == "file" ? uri.path.to_s.start_with?("/") : !uri.host.to_s.empty?
      raise Invalid unless valid

      uri.to_s
    rescue URI::Error, ArgumentError
      raise Invalid
    end

    def self.scp_like(value)
      return if value.match?(/\A[A-Za-z][A-Za-z0-9+.-]*:\/\//)

      match = SCP_LIKE.match(value)
      return unless match

      path = match[:path].delete_prefix("/")
      raise Invalid if path.empty? || path.match?(/[?#]/)

      authority = [ match[:user], match[:host] ].compact.join("@")
      "ssh://#{authority}/#{path}"
    end
    private_class_method :scp_like
  end
end
