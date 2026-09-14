module RepositoryRegistration
  class Inspect
    def self.call(attributes, adapter: Kos::Repository::Registration.new(attributes))
      adapter.call
    rescue Kos::Repository::Error => error
      if error.category == "transient"
        raise OperationError.new("request_timeout", "Repository inspection timed out")
      end

      raise OperationError.new("repository_registration_invalid", "Repository registration is invalid")
    end
  end
end
