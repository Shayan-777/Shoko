# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Canonical block type helpers used across parsing and rendering.
      module BlockType
        module_function

        ALIASES = {
          blockquote: :quote
        }.freeze

        def canonical(type)
          key = normalize(type)
          return nil if key.nil?

          ALIASES.fetch(key, key)
        end

        def quote?(type)
          canonical(type) == :quote
        end

        def code?(type)
          canonical(type) == :code
        end

        def image?(type)
          canonical(type) == :image
        end

        def normalize(type)
          case type
          when Symbol
            type
          when String
            value = type.strip
            return nil if value.empty?

            value.to_sym
          else
            nil
          end
        rescue Shoko::Error
          raise
        end
      end
    end
  end
end
