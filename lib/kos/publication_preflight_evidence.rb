require "digest"
require "json"

module Kos
  module PublicationPreflightEvidence
    module_function

    def digest(repository:, publication_preflight:, observed_remote_oid:, observed_at:)
      document = { "schema_version" => "2", "repository" => repository,
        "publication_preflight" => publication_preflight, "observed_remote_oid" => observed_remote_oid,
        "observed_at" => observed_at }
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
