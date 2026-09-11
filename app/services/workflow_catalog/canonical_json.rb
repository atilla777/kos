require "json"

module WorkflowCatalog
  class CanonicalJson
    class << self
      def generate(value)
        case value
        when Hash
          members = value.keys.sort_by { |key| utf16_sort_key(key) }.map do |key|
            "#{string(key)}:#{generate(value.fetch(key))}"
          end
          "{#{members.join(',')}}"
        when Array
          "[#{value.map { |item| generate(item) }.join(',')}]"
        when String then string(value)
        when Integer then integer(value)
        when Float then float(value)
        when true then "true"
        when false then "false"
        when nil then "null"
        else raise TypeError, "Value is not JSON-compatible"
        end
      end

      private

      def utf16_sort_key(value)
        raise TypeError, "JSON object keys must be strings" unless value.is_a?(String)

        value.encode(Encoding::UTF_16BE).bytes
      end

      def string(value)
        raise EncodingError, "JSON strings must be valid UTF-8" unless
          value.encoding == Encoding::UTF_8 && value.valid_encoding?

        JSON.generate(value)
      end

      def float(value)
        raise RangeError, "JSON numbers must be finite" unless value.finite?
        return "0" if value.zero?

        sign = value.negative? ? "-" : ""
        magnitude = value.abs
        representation = magnitude.to_s
        return sign + representation.delete_suffix(".0") unless representation.include?("e")

        digits, decimal_position = scientific_parts(representation)
        formatted = if magnitude >= 1e-6 && magnitude < 1e21
          decimal_notation(digits, decimal_position)
        else
          exponential_notation(digits, decimal_position - 1)
        end
        sign + formatted
      end

      def integer(value)
        return value.to_s if value.abs <= 9_007_199_254_740_991

        float(value.to_f)
      end

      def scientific_parts(representation)
        mantissa, exponent = representation.split("e", 2)
        digits = mantissa.delete(".").sub(/0+\z/, "")
        [ digits, exponent.to_i + 1 ]
      end

      def decimal_notation(digits, position)
        if position <= 0
          "0.#{'0' * -position}#{digits}"
        elsif position >= digits.length
          digits + ("0" * (position - digits.length))
        else
          "#{digits[0, position]}.#{digits[position..]}"
        end
      end

      def exponential_notation(digits, exponent)
        mantissa = digits.length == 1 ? digits : "#{digits[0]}.#{digits[1..]}"
        "#{mantissa}e#{exponent.positive? ? '+' : ''}#{exponent}"
      end
    end
  end
end
