require "uri"

module Kos
  class RepositoryIdentity
    class Invalid < StandardError; end

    SCP_STYLE = %r{\A(?<user>[^@/:\s]+)@(?<host>[^/:\s]+):(?<path>[^\s]+)\z}
    HOST = /\A(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/i
    COMPONENT = /\A[a-z0-9_][a-z0-9._-]*\z/i

    def self.normalize(value)
      raw = value.to_s
      if raw.empty? || raw != raw.strip || raw.match?(/[\x00-\x1f\x7f]/)
        raise Invalid, "repository URL must be a non-empty supported Git URL"
      end

      if (match = SCP_STYLE.match(raw))
        raise Invalid, "SSH repository URL must use the git user" unless match[:user] == "git"
        raise Invalid, "scp-style repository path must be relative" if match[:path].start_with?("/")

        return from_host_and_path(match[:host], match[:path])
      end

      uri = URI.parse(raw)
      unless %w[https ssh].include?(uri.scheme) && uri.host &&
          !raw.match?(%r{\A(?:https|ssh)://[^/]*:\d*(?:/|\z)}i) &&
          uri.query.nil? && uri.fragment.nil? && uri.path&.match?(%r{\A/[^/]}) && !uri.path.include?("//")
        raise Invalid, "repository URL must be an unambiguous HTTPS or SSH URL"
      end
      if uri.scheme == "https"
        raise Invalid, "repository URL credentials are not allowed" if uri.userinfo
      elsif uri.user != "git" || uri.password
        raise Invalid, "SSH repository URL must use the git user without credentials"
      end

      from_host_and_path(uri.host, uri.path.delete_prefix("/"))
    rescue URI::InvalidURIError
      raise Invalid, "repository URL must be a valid supported Git URL"
    end

    def self.from_host_and_path(host, path)
      repository_path = path.sub(/\.git\z/i, "")
      parts = repository_path.split("/", -1)
      unless host.match?(HOST) && parts.length >= 2 && parts.all? { |part| part.match?(COMPONENT) }
        raise Invalid, "repository URL must contain a safe namespace and repository"
      end

      "#{host.downcase}/#{parts.join("/")}"
    end
    private_class_method :from_host_and_path
  end
end
