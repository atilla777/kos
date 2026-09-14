require "json"
require "socket"

module Kos
  module Runtime
    module OpenCode
      class DeterministicProvider
        attr_reader :delayed_responses, :requests

        EFFECT_REQUEST = {
          "schema_version" => "1", "attempt_id" => "22222222-2222-4222-8222-222222222222",
          "input_context_digest" => "sha256:#{'a' * 64}",
          "effect" => { "operation" => "fetch", "remote" => "origin", "ref" => "refs/heads/main" }
        }.freeze
        EFFECT_RESULT = {
          "schema_version" => "1", "effect_intent_id" => "77777777-7777-4777-8777-777777777777",
          "request_attempt_id" => "22222222-2222-4222-8222-222222222222",
          "owner_attempt_id" => "22222222-2222-4222-8222-222222222222",
          "input_context_digest" => "sha256:#{'a' * 64}",
          "effect_request_digest" => "sha256:2f8604d52a5cf855e4b2fe5aedcfce28fcceb51d1e01c98a8af84b00de858659",
          "result" => { "outcome" => "succeeded", "operation" => "fetch", "remote" => "origin",
            "ref" => "refs/heads/main", "observed_oid" => "1" * 40,
            "evidence_digest" => "sha256:#{'c' * 64}" }
        }.freeze
        RESULT_MANIFEST = {
          "schema_version" => "1", "attempt_id" => "22222222-2222-4222-8222-222222222222",
          "input_context_digest" => "sha256:#{'a' * 64}", "outcome" => "succeeded", "artifacts" => [],
          "summary" => "OpenCode contract round trip completed"
        }.freeze

        def initialize(invalid_continuation: false, retrospective_result: :valid, retrospective_delay: 31,
          root_only: false)
          @server = TCPServer.new("127.0.0.1", 0)
          @requests = []
          @calls = Hash.new(0)
          @mutex = Mutex.new
          @condition = ConditionVariable.new
          @stopping = false
          @invalid_continuation = invalid_continuation
          @retrospective_result = retrospective_result
          @retrospective_delay = retrospective_delay
          @root_only = root_only
          @delayed_responses = 0
          @tool_call = 0
        end

        def base_url
          "http://127.0.0.1:#{@server.local_address.ip_port}/v1"
        end

        def start
          @thread = Thread.new do
            loop { handle(@server.accept) }
          rescue IOError, Errno::EBADF
            nil
          end
        end

        def stop
          @mutex.synchronize do
            @stopping = true
            @condition.broadcast
          end
          @server.close unless @server.closed?
          @thread&.join(2) || @thread&.kill&.join
        rescue IOError
          nil
        end

        private

        def handle(socket)
          return unless socket.gets

          headers = read_headers(socket)
          request = JSON.parse(socket.read(headers.fetch("content-length", "0").to_i))
          @mutex.synchronize { @requests << request }
          write_response(socket, next_response(request))
        rescue Errno::EPIPE, Errno::ECONNRESET
          nil
        ensure
          socket&.close
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
          invocation = retrospective_invocation(request)
          return retrospective_response(invocation) if invocation
          return text("launcher-primary") if @root_only

          tools = request.fetch("tools", []).filter_map { |definition| definition.dig("function", "name") }
          role = tools.include?("task") ? :parent : :child
          call = @mutex.synchronize { @calls[role] += 1 }
          case [ role, call ]
          when [ :parent, 1 ] then tool("bash", { "command" => "pwd" })
          when [ :parent, 2 ] then tool("task", initial_task)
          when [ :parent, 3 ] then tool("task", continuation(transcript))
          when [ :parent, 4 ] then tool("child_retrospective", retrospective_arguments(transcript))
          when [ :parent, 5 ] then text("contract-complete")
          when [ :child, 1 ] then tool("skill", { "name" => "kos-workflow-step" })
          when [ :child, 2 ] then tool("bash", { "command" => "pwd" })
          when [ :child, 3 ] then text(JSON.generate(EFFECT_REQUEST))
          when [ :child, 4 ]
            raise "effect result was not delivered" unless transcript.include?(JSON.generate(EFFECT_RESULT))

            text(JSON.generate(RESULT_MANIFEST))
          else text("unexpected-#{role}-call-#{call}")
          end
        end

        def retrospective_arguments(_transcript)
          raise "child session was not retained" unless @child_session_id

          { "child_session_id" => @child_session_id }
        end

        def retrospective_invocation(request)
          string_values(request.fetch("messages")).reverse_each do |value|
            document = JSON.parse(value)
            return document if document.is_a?(Hash) && document["schema_version"] == "1" &&
              %w[orchestrator workflow_step].include?(document["source"]) && document["timeout_seconds"] == 30
          rescue JSON::ParserError
            next
          end
          nil
        end

        def retrospective_response(invocation)
          return text("malformed retrospective result") if @retrospective_result == :malformed
          return :provider_failure if @retrospective_result == :failure
          if @retrospective_result == :delayed
            completed = @mutex.synchronize do
              @condition.wait(@mutex, @retrospective_delay) unless @stopping
              next false if @stopping

              @delayed_responses += 1
              true
            end
            raise IOError, "provider stopped before delayed response" unless completed
          end

          text(JSON.generate("schema_version" => "1", "session_id" => invocation.fetch("session_id"),
            "source" => invocation.fetch("source"), "primary_result_acknowledged" => true,
            "outcome" => "no_action", "proposals" => []))
        end

        def initial_task
          { "description" => "Verify KOS transport",
            "prompt" => "Load kos-workflow-step, run pwd, return the effect JSON, then await its result.",
            "subagent_type" => "kos-workflow-step" }
        end

        def continuation(transcript)
          match = transcript.match(%r{<task id="([^"]+)" state="completed">\n<task_result>\n(.*)\n</task_result>\n</task>}m)
          raise "invalid completed task wrapper" unless match && JSON.parse(match[2]) == EFFECT_REQUEST
          @child_session_id = match[1]

          { "description" => "Continue KOS transport",
            "prompt" => "Effect result:\n#{JSON.generate(EFFECT_RESULT)}\nReturn the final manifest JSON now.",
            "subagent_type" => "kos-workflow-step",
            "task_id" => @invalid_continuation ? "ses_unretained_contract_child" : match[1] }
        end

        def tool(name, arguments)
          @tool_call += 1
          { "tool_calls" => [ { "index" => 0, "id" => "call_#{@tool_call}", "type" => "function",
            "function" => { "name" => name, "arguments" => JSON.generate(arguments) } } ],
            "finish_reason" => "tool_calls" }
        end

        def text(value)
          { "content" => value, "finish_reason" => "stop" }
        end

        def write_response(socket, response)
          if response == :provider_failure
            body = JSON.generate("error" => { "message" => "deterministic provider failure",
              "type" => "invalid_request_error" })
            socket.write("HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\n")
            socket.write("Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
            return
          end

          body = chunks(response).map { |chunk| "data: #{JSON.generate(chunk)}\n\n" }.join + "data: [DONE]\n\n"
          socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n")
          socket.write("Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        end

        def chunks(response)
          delta = { "role" => "assistant" }
          delta["content"] = response["content"] if response.key?("content")
          delta["tool_calls"] = response["tool_calls"] if response.key?("tool_calls")
          [ chunk(delta, nil), chunk({}, response.fetch("finish_reason"), usage: true) ]
        end

        def chunk(delta, finish_reason, usage: false)
          value = { "id" => "chatcmpl-kos-contract", "object" => "chat.completion.chunk", "created" => 1_789_257_600,
            "model" => "kos-contract", "choices" => [ { "index" => 0, "delta" => delta,
              "finish_reason" => finish_reason } ] }
          value["usage"] = { "prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2 } if usage
          value
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
    end
  end
end
