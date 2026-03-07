# frozen_string_literal: true

module Shoko
  module Shared
    # Lightweight value coercion helpers for boundary normalization.
    module TypeCoercion
      module_function

      INTEGER_PATTERN = /\A[+-]?\d+\z/.freeze
      FLOAT_PATTERN = /\A[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][+-]?\d+)?\z/.freeze

      def optional_integer(value)
        return value if value.is_a?(Integer)

        text = normalized_text(value)
        return nil unless text&.match?(INTEGER_PATTERN)

        Integer(text, 10)
      end

      def optional_float(value)
        case value
        when Float
          return value if value.finite?
          return nil
        when Integer
          return value.to_f
        end

        text = normalized_text(value)
        return nil unless text&.match?(FLOAT_PATTERN)

        Float(text)
      end

      def normalized_text(value)
        return nil if value.nil?

        text = value.to_s.strip
        text.empty? ? nil : text
      end

      private_class_method :normalized_text
    end
  end
end
