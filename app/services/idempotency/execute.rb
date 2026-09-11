require "digest"

module Idempotency
  class Execute
    Result = Data.define(:data, :status, :replayed)

    def self.call(command:, key:, body:, status:, serialize:)
      attempts = 0
      begin
        execute(command: command, key: key, body: body, status: status, serialize: serialize) { yield }
      rescue ActiveRecord::StatementInvalid => error
        raise unless sqlite_busy?(error)

        attempts += 1
        retry if attempts < 3

        raise WorkflowCatalog::Error.new("request_timeout", "Catalog mutation timed out waiting for state")
      end
    end

    def self.execute(command:, key:, body:, status:, serialize:)
      fingerprint = fingerprint(command, body)
      existing = IdempotencyRecord.find_by(repository_id: nil, command: command, idempotency_key: key)
      return replay(existing, fingerprint) if existing

      result = nil
      ActiveRecord::Base.transaction do
        existing = IdempotencyRecord.lock.find_by(repository_id: nil, command: command, idempotency_key: key)
        return replay(existing, fingerprint) if existing

        data = serialize.call(yield)
        IdempotencyRecord.create!(command: command, idempotency_key: key, request_fingerprint: fingerprint,
          state: "completed", response_status: status, response_data: data, completed_at: Time.current)
        result = Result.new(data, status, false)
      end
      result
    rescue ActiveRecord::RecordNotUnique
      replay(IdempotencyRecord.find_by!(repository_id: nil, command: command, idempotency_key: key), fingerprint)
    end
    private_class_method :execute

    def self.fingerprint(command, body)
      value = [ command, "global", WorkflowCatalog::CanonicalDefinition.canonical_json(body) ].join("\n")
      "sha256:#{Digest::SHA256.hexdigest(value)}"
    end
    private_class_method :fingerprint

    def self.replay(record, fingerprint)
      raise WorkflowCatalog::Error.new("idempotency_conflict", "Idempotency key was reused") unless
        record.request_fingerprint == fingerprint
      raise WorkflowCatalog::Error.new("idempotency_in_progress", "Idempotent operation is in progress") unless
        record.state == "completed"

      Result.new(record.response_data, record.response_status, true)
    end
    private_class_method :replay

    def self.sqlite_busy?(error)
      error.cause.is_a?(SQLite3::BusyException)
    end
    private_class_method :sqlite_busy?
  end
end
