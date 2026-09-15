require "digest"
require "json"

module Kos
  module PushEvidence
    module_function

    def digest(repository:, publication:, candidate_sha:, remote:, base_ref:, observed_remote_tip:,
      candidate_reachable:, observed_at:)
      document = { "schema_version" => "1", "repository" => repository, "publication" => publication,
        "candidate_sha" => candidate_sha, "remote" => remote, "base_ref" => base_ref,
        "observed_remote_tip" => observed_remote_tip, "candidate_reachable" => candidate_reachable,
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
