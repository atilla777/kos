module RuntimeConfiguration
  class Update
    def self.call(retrospective_enabled:, expected_lock_version:)
      RuntimeConfig.transaction do
        config = RuntimeConfig.current
        config.lock!
        raise OperationError.new("stale_lock_version", "Runtime configuration lock version is stale") unless
          config.lock_version == expected_lock_version

        config.update!(retrospective_enabled: retrospective_enabled)
        config
      end
    rescue ActiveRecord::StaleObjectError
      raise OperationError.new("stale_lock_version", "Runtime configuration lock version is stale")
    end
  end
end
