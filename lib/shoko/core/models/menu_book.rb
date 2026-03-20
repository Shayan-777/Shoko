# frozen_string_literal: true

require_relative '../../shared/hash_normalizer'

module Shoko
  module Core
    module Models
      # Typed menu book payload used by menu->reader workflows.
      MenuBook = Data.define(:path, :payload) do
        class << self
          def from_h(hash)
            raise ArgumentError, "MenuBook payload must be a Hash, got #{hash.class}" unless hash.is_a?(Hash)

            normalized = Shoko::Shared::HashNormalizer.deep_symbolize(hash)
            raw_path = normalized[:path]
            path = raw_path.to_s.strip
            raise ArgumentError, 'MenuBook path cannot be blank' if path.empty?

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
