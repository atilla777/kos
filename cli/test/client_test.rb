require "minitest/autorun"
require_relative "../lib/kos_cli"

class ClientTest < Minitest::Test
  Response = Data.define(:code, :body)

  class FakeHttp
    class << self
      attr_accessor :options, :response, :error, :requests

      def start(_host, _port, **options)
        self.options = options
        yield new
      end
    end

    def request(request)
      self.class.requests = self.class.requests.to_i + 1
      raise self.class.error if self.class.error

      self.class.response
    end
  end

  class RefusedHttp
    def self.start(*)
      raise Errno::ECONNREFUSED
    end
  end

  def setup
    FakeHttp.options = nil
    FakeHttp.response = Response.new("200", '{"data":{}}')
    FakeHttp.error = nil
    FakeHttp.requests = 0
  end

  def test_maps_put_requests_to_net_http_put
    client = KosCli::Client.new("http://127.0.0.1:3000")

    assert_equal Net::HTTP::Put, client.send(:request_class, :put)
  end

  def test_configures_finite_connection_read_and_write_timeouts
    client = KosCli::Client.new("http://127.0.0.1:3000", http_class: FakeHttp)

    client.request(:get, "/projects")

    assert_equal KosCli::Client::OPEN_TIMEOUT, FakeHttp.options[:open_timeout]
    assert_equal KosCli::Client::READ_TIMEOUT, FakeHttp.options[:read_timeout]
    assert_equal KosCli::Client::WRITE_TIMEOUT, FakeHttp.options[:write_timeout]
    assert_equal KosCli::Client::MAX_RETRIES, FakeHttp.options[:max_retries]
    assert_operator FakeHttp.options[:open_timeout], :>, 0
    assert_operator FakeHttp.options[:read_timeout], :>, 0
    assert_operator FakeHttp.options[:write_timeout], :>, 0
  end

  def test_connection_failure_before_send_is_not_ambiguous
    client = KosCli::Client.new("http://127.0.0.1:3000", http_class: RefusedHttp)

    assert_raises(KosCli::ConnectionError) do
      client.request(:post, "/tasks", body: { title: "Task" })
    end
  end

  def test_default_local_refusal_suggests_starting_the_existing_server
    client = KosCli::Client.new("http://127.0.0.1:3137", http_class: RefusedHttp)

    error = assert_raises(KosCli::ConnectionError) do
      client.request(:get, "/projects")
    end

    assert_includes error.message, "http://127.0.0.1:3137"
    assert_includes error.message, "mise run kos"
    refute_includes error.message, "db:prepare"
  end

  def test_custom_url_refusal_does_not_expose_url_or_suggest_default_start_command
    client = KosCli::Client.new("http://user:password@localhost:3137/private", http_class: RefusedHttp)

    error = assert_raises(KosCli::ConnectionError) do
      client.request(:get, "/projects")
    end

    assert_equal "Unable to receive a valid response from KOS API.", error.message
  end

  def test_mutating_request_failure_after_connect_is_ambiguous_and_not_retried
    FakeHttp.error = EOFError.new
    client = KosCli::Client.new("http://127.0.0.1:3000", http_class: FakeHttp)

    error = assert_raises(KosCli::AmbiguousResultError) do
      client.request(:post, "/tasks/42/claim", body: { session_id: "agent" })
    end

    assert_equal "kos task current", error.verification_command
    assert_equal 1, FakeHttp.requests
  end

  def test_refusal_after_a_mutation_may_have_been_sent_stays_ambiguous
    FakeHttp.error = Errno::ECONNREFUSED.new
    client = KosCli::Client.new("http://127.0.0.1:3137", http_class: FakeHttp)

    error = assert_raises(KosCli::AmbiguousResultError) do
      client.request(:post, "/tasks/42/claim", body: { session_id: "agent" })
    end

    assert_equal "kos task current", error.verification_command
    assert_equal 1, FakeHttp.requests
  end

  def test_read_request_failure_is_a_connection_error
    FakeHttp.error = Net::ReadTimeout.new
    client = KosCli::Client.new("http://127.0.0.1:3000", http_class: FakeHttp)

    error = assert_raises(KosCli::ConnectionError) do
      client.request(:get, "/tasks/42")
    end
    refute_includes error.message, "mise run kos"
    assert_equal 1, FakeHttp.requests
  end

  def test_invalid_read_response_does_not_suggest_the_server_is_stopped
    FakeHttp.response = Response.new("200", "not json")
    client = KosCli::Client.new("http://127.0.0.1:3137", http_class: FakeHttp)

    error = assert_raises(KosCli::ConnectionError) do
      client.request(:get, "/projects")
    end

    refute_includes error.message, "mise run kos"
  end

  def test_invalid_mutating_response_is_ambiguous
    FakeHttp.response = Response.new("200", "not json")
    client = KosCli::Client.new("http://127.0.0.1:3000", http_class: FakeHttp)

    error = assert_raises(KosCli::AmbiguousResultError) do
      client.request(:put, "/tasks/42/artifacts/report", body: { content: "result" })
    end

    assert_equal "kos task artifact get TASK_ID KEY", error.verification_command
  end

  def test_lost_brief_plan_response_directs_reader_to_saved_key
    FakeHttp.error = Net::ReadTimeout.new
    client = KosCli::Client.new("http://127.0.0.1:3000", http_class: FakeHttp)

    error = assert_raises(KosCli::AmbiguousResultError) do
      client.request(:post, "/tasks/42/brief-plan", body: { key: "run-1", tasks: [] })
    end

    assert_equal "kos task plan show 42 KEY", error.verification_command
    assert_equal 1, FakeHttp.requests
  end
end
