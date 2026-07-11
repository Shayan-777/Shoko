# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'

module Shoko
  module Core
    module Models
      # Typed pending jump payload transferred from menu to reader startup.
      PendingJumpPayload = Data.define(:chapter_index, :annotation, :edit) do
        class << self
          def from_h(hash)
            raise ArgumentError, "PendingJumpPayload must be a Hash, got #{hash.class}" unless hash.is_a?(Hash)

            normalized = Shoko::Shared::HashNormalizer.symbolize_keys(hash)

            new(
              chapter_index: normalized[:chapter_index],
              annotation: normalize_annotation(normalized[:annotation]),
              edit: normalize_edit(normalized[:edit])
            )
          end

          private

          def normalize_annotation(annotation)
            return nil if annotation.nil?
            return annotation if annotation.is_a?(Shoko::Core::Models::AnnotationSelection)
            return annotation unless annotation.is_a?(Hash)

            Shoko::Shared::HashNormalizer.symbolize_keys(annotation).freeze
          end

          def normalize_edit(value)
            return value if [true, false].include?(value)
            return false if value.nil?
            return !%w[false 0 no].include?(value.downcase) if value.is_a?(String)

            !!value
          end
        end

        def to_h
          {
            chapter_index: chapter_index,
            annotation: annotation,
            edit: edit == true,
          }
        end
      end
    end
  end
end
