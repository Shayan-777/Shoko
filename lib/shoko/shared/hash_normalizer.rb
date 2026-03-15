# frozen_string_literal: true

module Shoko
  module Shared
    # Hash normalization helpers for adapter and persistence boundaries.
    module HashNormalizer
      module_function

      def symbolize_keys(value)
        return nil unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, inner_value), acc|
          acc[normalize_key(key)] = inner_value
        end
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, inner_value), acc|
            acc[normalize_key(key)] = deep_symbolize(inner_value)
          end
        when Array
          value.map { |item| deep_symbolize(item) }
        else
          value
        end
      end

      def normalize_key(key)
        key.is_a?(String) ? key.to_sym : key
      end
      private_class_method :normalize_key
    end
  end
end
