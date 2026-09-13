require "json"
require "socket"

class OpenCodeFakeProvider
  attr_reader :requests

  EFFECT_REQUEST = {
    "schema_version" => "1",
    "attempt_id" => "22222222-2222-4222-8222-222222222222",
    "input_context_digest" => "sha256:#{'a' * 64}",
    "effect" => {
      "operation" => "fetch",
      "remote" => "origin",
      "ref" => "refs/heads/main"
    }
  }.freeze
  EFFECT_RESULT = {
    "schema_version" => "1",
    "effect_intent_id" => "77777777-7777-4777-8777-777777777777",
    "request_attempt_id" => "22222222-2222-4222-8222-222222222222",
    "owner_attempt_id" => "22222222-2222-4222-8222-222222222222",
    "input_context_digest" => "sha256:#{'a' * 64}",
    "effect_request_digest" => "sha256:2f8604d52a5cf855e4b2fe5aedcfce28fcceb51d1e01c98a8af84b00de858659",
    "result" => {
      "outcome" => "succeeded",
      "operation" => "fetch",
      "remote" => "origin",
      "ref" => "refs/heads/main",
      "observed_oid" => "1" * 40,
      "evidence_digest" => "sha256:#{'c' * 64}"
    }
  }.freeze
  RESULT_MANIFEST = {
    "schema_version" => "1",
    "attempt_id" => "22222222-2222-4222-8222-222222222222",
    "input_context_digest" => "sha256:#{'a' * 64}",
    "outcome" => "succeeded",
    "artifacts" => [],
    "summary" => "OpenCode contract round trip completed"
  }.freeze

  def initialize(invalid_continuation: nil)
    @server = TCPServer.new("127.0.0.1", 0)
    @requests = []
    @calls = Hash.new(0)
    @mutex = Mutex.new
    @invalid_continuation = invalid_continuation
  end

  def base_url
    "http://127.0.0.1:#{@server.local_address.ip_port}/v1"
  end

  def start
    @thread = Thread.new do
      loop do
        socket = @server.accept
        handle(socket)
      rescue IOError, Errno::EBADF
        break
      end
    end
  end

  def stop
    @server.close
    @thread&.join(2)
  end

  private

  def handle(socket)
    request_line = socket.gets
    return socket.close unless request_line

    headers = read_headers(socket)
    body = socket.read(headers.fetch("content-length", "0").to_i)
    request = JSON.parse(body)
    @mutex.synchronize { @requests << request }
    response = next_response(request)
    write_response(socket, response)
  rescue JSON::ParserError => error
    write_error(socket, error.message)
  ensure
    socket.close
  end

  def read_headers(socket)
    {}.tap do |headers|
      while (line = socket.gets)
        break if line == "\r\n"

        name, value = line.split(":", 2)
        headers[name.downcase] = value.strip
      end
    end
  end

  def next_response(request)
    transcript = string_values(request.fetch("messages")).join("\n")
    role = transcript.include?("KOS_CONTRACT_CHILD") ? :child : :parent
    call = @mutex.synchronize { @calls[role] += 1 }

    case [ role, call ]
    when [ :parent, 1 ] then tool_call("bash", { "command" => "pwd" })
    when [ :parent, 2 ] then tool_call("task", initial_task_arguments)
    when [ :parent, 3 ] then tool_call("task", continuation_arguments(transcript))
    when [ :parent, 4 ] then text("contract-complete")
    when [ :child, 1 ] then tool_call("skill", { "name" => "kos-contract-probe" })
    when [ :child, 2 ] then tool_call("bash", { "command" => "pwd" })
    when [ :child, 3 ] then text(JSON.generate(EFFECT_REQUEST))
    when [ :child, 4 ]
      raise "effect result was not delivered to the child" unless transcript.include?(JSON.generate(EFFECT_RESULT))

      text(JSON.generate(RESULT_MANIFEST))
    else
      text("unexpected-#{role}-call-#{call}")
    end
  end

  def initial_task_arguments
    {
      "description" => "Verify KOS transport",
      "prompt" => "Load kos-contract-probe, run pwd, and return the requested effect JSON. Wait for its result before returning the final manifest.",
      "subagent_type" => "kos-contract-step"
    }
  end

  def continuation_arguments(transcript)
    match = transcript.match(%r{<task id="([^"]+)" state="completed">\n<task_result>\n(.*)\n</task_result>\n</task>}m)
    raise "completed task output did not contain a valid wrapper" unless match
    raise "child returned an unexpected effect request" unless JSON.parse(match[2]) == EFFECT_REQUEST

    session_id = match[1]
    raise "completed task output did not contain a child session identifier" unless session_id

    arguments = {
      "description" => "Continue KOS transport",
      "prompt" => "Effect result:\n#{JSON.generate(EFFECT_RESULT)}\nReturn the final manifest JSON now.",
      "subagent_type" => "kos-contract-step",
      "task_id" => @invalid_continuation == :wrong ? "ses_unretained_contract_child" : session_id
    }
    arguments.delete("task_id") if @invalid_continuation == :omit
    arguments
  end

  def tool_call(name, arguments)
    {
      "tool_calls" => [ {
        "index" => 0,
        "id" => "call_#{name}_#{rand(1_000_000)}",
        "type" => "function",
        "function" => { "name" => name, "arguments" => JSON.generate(arguments) }
      } ],
      "finish_reason" => "tool_calls"
    }
  end

  def text(value)
    { "content" => value, "finish_reason" => "stop" }
  end

  def write_response(socket, response)
    chunks = response_chunks(response)
    body = chunks.map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }.join + "data: [DONE]\n\n"
    socket.write("HTTP/1.1 200 OK\r\n")
    socket.write("Content-Type: text/event-stream\r\n")
    socket.write("Content-Length: #{body.bytesize}\r\n")
    socket.write("Connection: close\r\n\r\n")
    socket.write(body)
  end

  def response_chunks(response)
    delta = { "role" => "assistant" }
    delta["content"] = response["content"] if response.key?("content")
    delta["tool_calls"] = response["tool_calls"] if response.key?("tool_calls")
    [
      completion_chunk(delta, nil),
      completion_chunk({}, response.fetch("finish_reason"), usage: true)
    ]
  end

  def completion_chunk(delta, finish_reason, usage: false)
    chunk = {
      "id" => "chatcmpl-kos-contract",
      "object" => "chat.completion.chunk",
      "created" => 1_789_257_600,
      "model" => "kos-contract",
      "choices" => [ { "index" => 0, "delta" => delta, "finish_reason" => finish_reason } ]
    }
    chunk["usage"] = { "prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2 } if usage
    chunk
  end

  def write_error(socket, message)
    body = JSON.generate("error" => { "message" => message })
    socket.write("HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\n")
    socket.write("Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
  rescue IOError
    nil
  end

  def string_values(value)
    case value
    when Hash then value.flat_map { |key, item| [ key.to_s, *string_values(item) ] }
    when Array then value.flat_map { |item| string_values(item) }
    when String then [ value ]
    else []
    end
  end
end
