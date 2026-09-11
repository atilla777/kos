module WorkflowCatalog
  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message, details: nil)
      @code = code
      @details = details
      super(message)
    end
  end
end
