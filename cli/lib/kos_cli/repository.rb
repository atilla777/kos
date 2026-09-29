require "open3"
require "uri"

module KosCli
  class RepositoryError < StandardError; end

  class Repository
    CANONICAL_PATTERN = %r{\A(?<host>[a-zA-Z0-9.-]+(?::[0-9]+)?)/(?<path>[^\s]+)\z}
    SCP_PATTERN = %r{\A(?:[^@/\s]+@)?(?<host>[^:/\s]+):(?<path>[^\s]+)\z}
    SUPPORTED_SCHEMES = %w[git http https ssh].freeze

    def self.current
      remote, _stderr, status = Open3.capture3("git", "config", "--get", "remote.origin.url")
      raise RepositoryError, "No Git origin found; pass --project explicitly." unless status.success? && !remote.strip.empty?

      normalize(remote.strip)
    rescue Errno::ENOENT
      raise RepositoryError, "Git is unavailable; pass --project explicitly."
    end

    def self.normalize(value)
      host, path = split(value)
      path = path.sub(%r{\A/+}, "").sub(%r{/+\z}, "").sub(/\.git\z/i, "")
      raise RepositoryError, "Unsupported Git remote; pass a canonical --project value." if host.empty? || !path.include?("/")

      host = host.downcase
      path = path.downcase if host == "github.com"
      "#{host}/#{path}"
    rescue URI::InvalidURIError
      raise RepositoryError, "Unsupported Git remote; pass a canonical --project value."
    end

    def self.split(value)
      if (match = CANONICAL_PATTERN.match(value)) && !value.include?("://")
        return [ match[:host], match[:path] ]
      end

      if (match = SCP_PATTERN.match(value)) && !value.include?("://")
        return [ match[:host], match[:path] ]
      end

      uri = URI.parse(value)
      raise RepositoryError, "Unsupported Git remote; pass a canonical --project value." unless SUPPORTED_SCHEMES.include?(uri.scheme) && uri.host

      host = uri.host
      default_port = (uri.scheme == "http" && uri.port == 80) || (uri.scheme == "https" && uri.port == 443) || (uri.scheme == "ssh" && uri.port == 22)
      host = "#{host}:#{uri.port}" if uri.port && !default_port
      [ host, uri.path ]
    end
    private_class_method :split
  end
end
