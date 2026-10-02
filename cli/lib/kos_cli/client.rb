require "json"
require "net/http"
require "openssl"
require "uri"

module KosCli
  class ConnectionError < StandardError; end

  class AmbiguousResultError < StandardError
    attr_reader :verification_command

    def initialize(message, verification_command:)
      @verification_command = verification_command
      super(message)
    end
  end

  class Client
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15
    WRITE_TIMEOUT = 15
    MAX_RETRIES = 0
    LOCAL_API_URL = "http://127.0.0.1:3137"
    MUTATING_METHODS = %i[post put patch delete].freeze

    def initialize(base_url, http_class: Net::HTTP)
      @base_uri = URI(base_url)
      @http_class = http_class
      raise ArgumentError, "KOS API URL must use HTTP or HTTPS." unless %w[http https].include?(@base_uri.scheme) && @base_uri.host
    rescue URI::InvalidURIError
      raise ArgumentError, "KOS API URL is invalid."
    end

    def request(method, path, body: nil, query: nil)
      uri = @base_uri.dup
      uri.path = [ @base_uri.path.sub(%r{/\z}, ""), "/api/v1", path ].join
      uri.query = URI.encode_www_form(query) if query&.any?
      request = request_class(method).new(uri)
      request["Accept"] = "application/json"
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end

      connected = false
      response = @http_class.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT,
        write_timeout: WRITE_TIMEOUT,
        max_retries: MAX_RETRIES
      ) do |http|
        connected = true
        http.request(request)
      end

      [ response.code.to_i, JSON.parse(response.body) ]
    rescue JSON::ParserError
      raise_transport_error(method, path, request_may_have_been_sent: true)
    rescue Errno::ECONNREFUSED
      raise_transport_error(method, path, request_may_have_been_sent: connected, connection_refused: true)
    rescue IOError, SocketError, SystemCallError, Timeout::Error,
      Net::HTTPBadResponse, Net::ProtocolError, OpenSSL::SSL::SSLError
      raise_transport_error(method, path, request_may_have_been_sent: connected)
    end

    private

    def request_class(method)
      {
        get: Net::HTTP::Get,
        post: Net::HTTP::Post,
        put: Net::HTTP::Put,
        patch: Net::HTTP::Patch,
        delete: Net::HTTP::Delete
      }.fetch(method)
    end

    def raise_transport_error(method, path, request_may_have_been_sent:, connection_refused: false)
      if MUTATING_METHODS.include?(method) && request_may_have_been_sent
        raise AmbiguousResultError.new(
          "The request may have completed, but KOS did not receive a valid response. Verify server state before retrying.",
          verification_command: verification_command(path)
        )
      end

      if connection_refused && @base_uri.to_s == LOCAL_API_URL
        raise ConnectionError,
          "Cannot connect to KOS API at #{LOCAL_API_URL}. Check the existing local server; run `mise run kos` in a terminal to start it."
      end

      raise ConnectionError, "Unable to receive a valid response from KOS API."
    end

    def verification_command(path)
      case path
      when %r{\A/tasks/(\d+)/brief-plan\z} then "kos task plan show #{Regexp.last_match(1)} KEY"
      when %r{\A/tasks/\d+/artifacts/} then "kos task artifact get TASK_ID KEY"
      when %r{\A/tasks/(?:claim-next|\d+/claim)\z} then "kos task current"
      when %r{\A/tasks/(\d+)} then "kos task show #{Regexp.last_match(1)}"
      when "/tasks" then "kos task list"
      when %r{\A/task-groups/(\d+)} then "kos group show #{Regexp.last_match(1)}"
      when "/task-groups" then "kos group list"
      when %r{\A/projects/(\d+)} then "kos project show #{Regexp.last_match(1)}"
      else "kos project list"
      end
    end
  end
end
