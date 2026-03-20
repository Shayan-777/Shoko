# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Typed pending jump payload transferred from menu to reader startup.
      PendingJumpPayload = Data.define(:chapter_index, :selection_range, :annotation, :edit) do
        class << self
          def from_h(hash)
            raise ArgumentError, "PendingJumpPayload must be a Hash, got #{hash.class}" unless hash.is_a?(Hash)

            normalized = hash.transform_keys do |key|
              key.is_a?(String) ? key.to_sym : key
            end

            new(
              chapter_index: normalized[:chapter_index],
              selection_range: normalized[:selection_range],
              annotation: normalize_annotation(normalized[:annotation]),
              edit: normalize_edit(normalized[:edit])
            )
          end

          private

          def normalize_annotation(annotation)
            return nil if annotation.nil?
            return annotation if annotation.is_a?(Shoko::Core::Models::AnnotationSelection)
            return annotation unless annotation.is_a?(Hash)

            annotation.transform_keys do |key|
              key.is_a?(String) ? key.to_sym : key
            end.freeze
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
            selection_range: selection_range,
            annotation: annotation,
            edit: edit == true,
          }
        end
      end
    end
  end
end
