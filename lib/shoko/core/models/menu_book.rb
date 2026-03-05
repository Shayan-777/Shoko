# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Typed menu book payload used by menu->reader workflows.
      class MenuBook < Data.define(:path, :payload)
        class << self
          def from_h(hash)
            raise ArgumentError, "MenuBook payload must be a Hash, got #{hash.class}" unless hash.is_a?(Hash)

            raw_path = hash[:path] || hash['path']
            path = raw_path.to_s.strip
            raise ArgumentError, 'MenuBook path cannot be blank' if path.empty?

            normalized = hash.each_with_object({}) do |(key, value), acc|
              acc[key.is_a?(String) ? key.to_sym : key] = value
            end

            new(path: path, payload: normalized.freeze)
          end
        end

        def title
          payload[:title]
        end

        def to_h
          payload.merge(path: path)
        end
      end
    end
  end
end
