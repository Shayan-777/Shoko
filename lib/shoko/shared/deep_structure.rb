# frozen_string_literal: true

module Shoko
  module Shared
    # Recursive duplication and freezing for plain data trees (Hash, Array,
    # String). Everything else is treated as an opaque leaf and passed
    # through untouched: value objects manage their own immutability, and
    # freezing arbitrary domain objects from here would be an overreach.
    #
    # This is the state system's immutability primitive: the state store
    # deep-freezes its tree so reads can hand out internals safely, and
    # schema fragments freeze their defaults so containers can share them.
    module DeepStructure
      module_function

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, inner), copy| copy[key] = deep_dup(inner) }
        when Array
          value.map { |item| deep_dup(item) }
        when String
          value.frozen? ? value : value.dup
        else
          value
        end
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each_value { |inner| deep_freeze(inner) }
          value.freeze
        when Array
          value.each { |item| deep_freeze(item) }
          value.freeze
        when String
          value.freeze
        else
          value
        end
      end

      def deep_dup_frozen(value)
        deep_freeze(deep_dup(value))
      end
    end
  end
end
