require "digest"
require "json"
require "json_schemer"
require "uri"
require_relative "../../json_parser"

module Kos
  module Runtime
    module OpenCode
      class Transport
        class InvalidExchange < StandardError; end

        TASK_OUTPUT = %r{\A<task id="([^"]+)" state="completed">\n<task_result>\n(.*)\n</task_result>\n</task>\z}m
        SCHEMA_ROOT = File.expand_path("../../../../schemas", __dir__)

        attr_reader :child_session_id, :retrospective_results, :state

        def initialize(attempt_id:, input_context_digest:, allowed_operations:)
          @attempt_id = attempt_id
          @input_context_digest = input_context_digest
          @allowed_operations = allowed_operations
          @retrospective_results = []
          @retrospective_acknowledged = false
          @state = :awaiting_turn
        end

        def accept_task_completion(event)
          fail_exchange("exchange is already complete") if state == :completed
          completion = parse_completion(event)
          validate_document("workflow_step_completion", completion)
          retain_child(completion.fetch("child_session_id"))

          turn = completion.fetch("turn")
          effect_request?(turn) ? accept_effect_request(turn) : accept_manifest(turn)
          completion
        end

        def deliver_effect(delivery, expected_effect_intent_id:)
          fail_exchange("no effect result is expected") unless state == :awaiting_effect
          validate_document("effect_delivery", delivery)
          fail_exchange("effect result targets another child session") unless delivery.fetch("child_session_id") == child_session_id

          result = delivery.fetch("effect_result")
          validate_effect_result(result, expected_effect_intent_id)
          @state = :awaiting_turn
          delivery
        end

        def acknowledge_primary(invocation)
          fail_exchange("retrospective was already acknowledged") if @retrospective_acknowledged
          fail_exchange("primary result is not complete") unless state == :completed
          validate_document("invocation", invocation, schema: self.class.retrospective_schema)
          fail_exchange("retrospective source is not a workflow step") unless invocation.fetch("source") == "workflow_step"

          @retrospective_invocation = invocation
          @retrospective_acknowledged = true
          @state = :awaiting_retrospective
          invocation
        end

        def accept_retrospective_delivery(delivery)
          fail_exchange("retrospective is not expected") unless state == :awaiting_retrospective
          validate_document("retrospective_delivery", delivery)
          validate_retrospective_binding(delivery)
          @retrospective_results << delivery.fetch("result") if delivery.fetch("outcome") == "result"
          @retrospective_results.shift while @retrospective_results.length > 5
          @state = :completed
          delivery
        end

        private

        def parse_completion(event)
          part = event.fetch("part")
          state = part.fetch("state")
          fail_exchange("event is not a completed Task tool call") unless event["type"] == "tool_use" &&
            part["tool"] == "task" && state["status"] == "completed"

          match = TASK_OUTPUT.match(state.fetch("output"))
          fail_exchange("invalid OpenCode task completion wrapper") unless match
          session_id = state.fetch("metadata").fetch("sessionId")
          fail_exchange("task wrapper and metadata identify different child sessions") unless match[1] == session_id

          { "schema_version" => "1", "runtime" => "opencode", "child_session_id" => session_id,
            "turn" => Kos::JsonParser.parse(match[2]) }
        rescue KeyError, JSON::ParserError => error
          fail_exchange("invalid OpenCode task completion: #{error.message}")
        end

        def retain_child(session_id)
          @child_session_id ||= session_id
          fail_exchange("task completion came from another child session") unless child_session_id == session_id
        end

        def accept_effect_request(request)
          fail_exchange("an effect result is already pending") unless state == :awaiting_turn
          validate_attempt(request)
          operation = request.dig("effect", "operation")
          fail_exchange("effect operation is not allowed") unless @allowed_operations.include?(operation)

          @effect_request = request
          @state = :awaiting_effect
        end

        def accept_manifest(manifest)
          fail_exchange("final manifest arrived before the pending effect result") unless state == :awaiting_turn
          validate_attempt(manifest)
          @state = :completed
        end

        def validate_attempt(document)
          fail_exchange("turn belongs to another attempt") unless document.fetch("attempt_id") == @attempt_id
          return if document.fetch("input_context_digest") == @input_context_digest

          fail_exchange("turn has a different input context digest")
        end

        def validate_effect_result(result, expected_effect_intent_id)
          fail_exchange("effect result belongs to another intent") unless result.fetch("effect_intent_id") == expected_effect_intent_id
          fail_exchange("effect result belongs to another request attempt") unless result.fetch("request_attempt_id") == @attempt_id
          fail_exchange("effect result belongs to another owner attempt") unless result.fetch("owner_attempt_id") == @attempt_id
          fail_exchange("effect result has a different input context digest") unless result.fetch("input_context_digest") == @input_context_digest
          fail_exchange("effect result has a different request digest") unless result.fetch("effect_request_digest") == effect_request_digest

          requested_operation = @effect_request.dig("effect", "operation")
          fail_exchange("effect result operation does not match its request") unless result.dig("result", "operation") == requested_operation
          result_body = result.fetch("result")
          validate_operation_identity(requested_operation, result_body) if result_body["outcome"] == "succeeded"
        end

        def validate_operation_identity(operation, result)
          request = @effect_request.fetch("effect")
          fields = case operation
          when "worktree_remove" then %w[reservation_id]
          when "fetch" then %w[remote ref]
          when "push" then %w[publication_id candidate_sha]
          else []
          end
          return if fields.all? { |field| result[field] == request[field] }

          fail_exchange("effect result targets different operation parameters")
        end

        def effect_request_digest
          "sha256:#{Digest::SHA256.hexdigest(canonical_json(@effect_request))}"
        end

        def canonical_json(value)
          case value
          when Hash
            "{#{value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(',')}}"
          when Array then "[#{value.map { |item| canonical_json(item) }.join(',')}]"
          else JSON.generate(value)
          end
        end

        def effect_request?(turn)
          turn.key?("effect")
        end

        def validate_retrospective_binding(delivery)
          fail_exchange("retrospective targets another child session") unless
            delivery.fetch("runtime_session_id") == child_session_id
          fail_exchange("retrospective invocation changed") unless delivery.fetch("invocation") == @retrospective_invocation
          return unless delivery.fetch("outcome") == "result"

          result = delivery.fetch("result")
          expected = @retrospective_invocation.values_at("session_id", "source", "primary_result_acknowledged")
          fail_exchange("retrospective result identity changed") unless
            result.values_at("session_id", "source", "primary_result_acknowledged") == expected
        end

        def validate_document(name, document, schema: self.class.schema)
          return if schema.ref("#/$defs/#{name}").valid?(document)

          fail_exchange("document does not satisfy #{name}")
        end

        def fail_exchange(message)
          raise InvalidExchange, message
        end

        class << self
          def schema
            @schema ||= begin
              path = File.join(SCHEMA_ROOT, "runtime/v1/opencode.json")
              registry = Dir[File.join(SCHEMA_ROOT, "{cli,runtime}/v1/*.json")].to_h do |schema_path|
                document = JSON.parse(File.read(schema_path))
                [ URI(document.fetch("$id")), document ]
              end
              JSONSchemer.schema(JSON.parse(File.read(path)), ref_resolver: registry.to_proc)
            end
          end

          def retrospective_schema
            @retrospective_schema ||= begin
              path = File.join(SCHEMA_ROOT, "runtime/v1/retrospective.json")
              JSONSchemer.schema(JSON.parse(File.read(path)))
            end
          end

          def valid_retrospective_result?(document)
            retrospective_schema.ref("#/$defs/result").valid?(document)
          end

          def valid_retrospective_delivery?(document)
            schema.ref("#/$defs/retrospective_delivery").valid?(document)
          end
        end
      end
    end
  end
end
