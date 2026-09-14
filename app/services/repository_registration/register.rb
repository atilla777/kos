module RepositoryRegistration
  class Register
    IMMUTABLE_FIELDS = %w[git_common_dir task_prefix trusted_remote trusted_remote_url base_ref].freeze

    def self.call(attributes)
      existing = Repository.find_by(git_common_dir: attributes.fetch("git_common_dir"))
      return matching_or_conflict(existing, attributes) if existing
      conflict! if Repository.exists?(task_prefix: attributes.fetch("task_prefix"))

      Repository.create!(attributes.slice(*IMMUTABLE_FIELDS))
    rescue ActiveRecord::RecordNotUnique
      existing = Repository.find_by(git_common_dir: attributes.fetch("git_common_dir"))
      return matching_or_conflict(existing, attributes) if existing

      conflict!
    end

    def self.matching_or_conflict(repository, attributes)
      return repository if IMMUTABLE_FIELDS.all? { |field| repository.public_send(field) == attributes.fetch(field) }

      conflict!
    end
    private_class_method :matching_or_conflict

    def self.conflict!
      raise OperationError.new("repository_registration_conflict", "Repository registration conflicts with existing state")
    end
    private_class_method :conflict!
  end
end
