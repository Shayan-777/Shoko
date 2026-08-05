# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Copies nested value data before freezing it, preventing callers from
      # retaining a mutable back door into immutable core models.
      module ValueNormalizer
        module_function

        def immutable(value)
          case value
          when Hash
            value.to_h { |key, child| [immutable(key), immutable(child)] }.freeze
          when Array
            value.map { |child| immutable(child) }.freeze
          when String
            value.dup.freeze
          else
            value
          end
        end
      end
    end
  end
end
