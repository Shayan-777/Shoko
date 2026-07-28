# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'

module Shoko
  module Core
    module Models
      # Typed translator language-pack row used by the menu packs workflow.
      TranslatorPackEntry = Data.define(
        :from, :to, :version, :size, :installed, :installed_version,
        :update_available, :payload
      ) do
        class << self
          def from_h(hash)
            raise ArgumentError, "TranslatorPackEntry payload must be a Hash, got #{hash.class}" unless hash.is_a?(Hash)

            normalized = Shoko::Shared::HashNormalizer.symbolize_keys(hash)
            from, to = validated_pair(normalized)
            new(
              from: from,
              to: to,
              version: normalized[:version].to_s,
              size: normalized[:size].to_i,
              installed: normalized[:installed] == true,
              installed_version: normalized[:installed_version].to_s,
              update_available: normalized[:update_available] == true,
              payload: normalized.freeze
            )
          end

          private

          def validated_pair(normalized)
            from = normalized[:from].to_s.strip
            to = normalized[:to].to_s.strip
            raise ArgumentError, 'TranslatorPackEntry language pair cannot be blank' if from.empty? || to.empty?

            [from, to]
          end
        end

        def with_installation(installed:)
          self.class.from_h(payload.merge(installed: installed == true))
        end

        def pair_key
          "#{from}-#{to}"
        end

        def to_h
          payload.merge(
            from: from, to: to, version: version, size: size,
            installed: installed == true,
            installed_version: installed_version,
            update_available: update_available == true
          )
        end
      end
    end
  end
end
