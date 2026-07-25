# frozen_string_literal: true

module Shoko
  module Shared
    # Hash normalization helpers for adapter and persistence boundaries.
    module HashNormalizer
      module_function

      def symbolize_keys(value)
        return nil unless value.is_a?(Hash)

        value.transform_keys do |key|
          normalize_key(key)
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

      # Symbolizes the hash, then reads key with an explicit default. Distinct
      # from indifferent_fetch: this normalizes the WHOLE hash first, so a
      # payload whose keys are all Strings resolves under symbol keys. Used by
      # the value objects that build themselves from persisted payloads.
      def fetch_with_default(hash, key, default = nil)
        normalized = symbolize_keys(hash) || {}
        normalized.key?(key) ? normalized[key] : default
      end

      # Reads a key that may have been persisted as either a Symbol or a
      # String. Cache payloads, JSON round-trips, and menu records all reach
      # this boundary with mixed key types.
      #
      # @param hash [Object] any value; non-Hashes yield the default
      # @return [Object] the value under key (symbol first, then string)
      def indifferent_fetch(hash, key, default = nil)
        return default unless hash.is_a?(Hash)

        symbol_key = key.to_sym
        return hash[symbol_key] if hash.key?(symbol_key)

        string_key = key.to_s
        return hash[string_key] if hash.key?(string_key)

        default
      end

      def normalize_key(key)
        key.is_a?(String) ? key.to_sym : key
      end
      private_class_method :normalize_key
    end
  end
end
