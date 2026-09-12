require "digest"

module Idempotency
  class Execute
    Result = Data.define(:data, :status, :replayed, :error)

    def self.call(command:, key:, body:, status:, serialize:, repository: nil, error_status: ->(_error) { 409 },
      prepare: nil)
      attempts = 0
      begin
        result = execute(command: command, key: key, body: body, status: status, serialize: serialize,
          repository: repository, error_status: error_status, prepare: prepare) { |prepared| yield(prepared) }
        raise result.error if result.error

        result
      rescue ActiveRecord::StatementInvalid => error
        raise unless sqlite_busy?(error)

        attempts += 1
        retry if attempts < 3

        raise OperationError.new("request_timeout", "Mutation timed out waiting for state")
      end
    end

    def self.execute(command:, key:, body:, status:, serialize:, repository:, error_status:, prepare:)
      fingerprint = fingerprint(command, body, repository)
      identity = { repository: repository, command: command, idempotency_key: key }
      existing = IdempotencyRecord.find_by(identity)
      return replay(existing, fingerprint) if existing

      prepared = nil
      preparation_error = nil
      begin
        prepared = prepare&.call
      rescue OperationError => error
        preparation_error = error
      end
      execute_transaction(identity:, fingerprint:, status:, serialize:, error_status:,
        preparation_error:, prepared:) { |value| yield(value) }
    end
    private_class_method :execute

    def self.execute_transaction(identity:, fingerprint:, status:, serialize:, error_status:, preparation_error:,
      prepared:)
      result = nil
      ActiveRecord::Base.transaction do
        existing = IdempotencyRecord.lock.find_by(identity)
        return replay(existing, fingerprint) if existing

        operation_result = capture(status, serialize, error_status, preparation_error) { yield(prepared) }
        IdempotencyRecord.create!(identity.merge(request_fingerprint: fingerprint,
          state: "completed", response_status: operation_result.status,
          response_data: stored_data(operation_result), completed_at: Time.current))
        result = operation_result
      end
      result
    rescue ActiveRecord::RecordNotUnique
      replay(IdempotencyRecord.find_by!(identity), fingerprint)
    end
    private_class_method :execute_transaction

    def self.capture(status, serialize, error_status, preparation_error)
      ActiveRecord::Base.transaction(requires_new: true) do
        begin
          raise preparation_error if preparation_error

          Result.new(serialize.call(yield), status, false, nil)
        rescue CommittedOperationError => error
          Result.new(nil, error_status.call(error), false, error)
        end
      end
    rescue OperationError => error
      Result.new(nil, error_status.call(error), false, error)
    end
    private_class_method :capture

    def self.stored_data(result)
      return result.data unless result.error

      { "_operation_error" => { "code" => result.error.code, "message" => result.error.message,
        "details" => result.error.details }.compact }
    end
    private_class_method :stored_data

    def self.fingerprint(command, body, repository)
      scope = repository&.id || "global"
      value = [ command, scope, WorkflowCatalog::CanonicalDefinition.canonical_json(body) ].join("\n")
      "sha256:#{Digest::SHA256.hexdigest(value)}"
    end
    private_class_method :fingerprint

    def self.replay(record, fingerprint)
      raise OperationError.new("idempotency_conflict", "Idempotency key was reused") unless
        record.request_fingerprint == fingerprint
      raise OperationError.new("idempotency_in_progress", "Idempotent operation is in progress") unless
        record.state == "completed"

      error = record.response_data["_operation_error"]
      return Result.new(record.response_data, record.response_status, true, nil) unless error

      Result.new(nil, record.response_status, true,
        OperationError.new(error.fetch("code"), error.fetch("message"), details: error["details"]))
    end
    private_class_method :replay

    def self.sqlite_busy?(error)
      error.cause.is_a?(SQLite3::BusyException)
    end
    private_class_method :sqlite_busy?
  end
end
