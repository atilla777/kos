require "digest"
require "json"

module Kos
  module RebaseEvidence
    module_function

    def digest(repository:, reservation:, effect:, fetch:, original_base_sha:, expected_head_sha:, onto_sha:,
      head_sha:)
      document = { "schema_version" => "1", "repository" => repository, "reservation" => reservation,
        "effect" => effect, "fetch" => fetch, "original_base_sha" => original_base_sha,
        "expected_head_sha" => expected_head_sha, "onto_sha" => onto_sha, "head_sha" => head_sha }
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
