module Kos
  class JsonParser
    def self.parse(source)
      value = source.dup.force_encoding(Encoding::UTF_8)
      raise JSON::ParserError, "source is not valid UTF-8" unless value.valid_encoding?

      JSON.parse(value, allow_duplicate_key: false)
    end
  end
end
