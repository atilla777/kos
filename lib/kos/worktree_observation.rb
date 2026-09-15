require "digest"
require "json"

module Kos
  module WorktreeObservation
    module_function

    def digest(repository_id:, reservation_id:, fencing_token:, path:, branch:, state:, **fields)
      document = { "schema_version" => "1", "repository_id" => repository_id,
        "reservation_id" => reservation_id, "fencing_token" => fencing_token,
        "path" => path, "branch" => branch, "state" => state }.merge(fields.compact.transform_keys(&:to_s))
      "sha256:#{Digest::SHA256.hexdigest(canonical_json(document))}"
    end

    def canonical_json(value)
      case value
      when Hash
        "{#{value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(',')}}"
      when Array then "[#{value.map { |item| canonical_json(item) }.join(',')}]"
      else JSON.generate(value)
      end
    end
    private_class_method :canonical_json
  end
end
