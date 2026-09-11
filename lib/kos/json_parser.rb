module Kos
  class JsonParser
    def self.parse(source)
      JSON.parse(source, allow_duplicate_key: false)
    end
  end
end
