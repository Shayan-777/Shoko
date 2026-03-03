# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Typed selected annotation context used by menu annotation workflows.
      class AnnotationSelection < Data.define(:book_path, :annotation)
        REQUIRED_KEYS = %i[id chapter_index range].freeze

        class << self
          def from_h(annotation:, book_path:)
            normalized_book_path = book_path.to_s.strip
            raise ArgumentError, 'AnnotationSelection book_path cannot be blank' if normalized_book_path.empty?
            unless annotation.is_a?(Hash)
              raise ArgumentError, "AnnotationSelection annotation must be a Hash, got #{annotation.class}"
            end

            normalized_annotation = annotation.each_with_object({}) do |(key, value), acc|
              acc[key.is_a?(String) ? key.to_sym : key] = value
            end
            missing = REQUIRED_KEYS.select { |key| normalized_annotation[key].nil? }
            unless missing.empty?
              raise ArgumentError, "AnnotationSelection annotation missing keys: #{missing.join(', ')}"
            end

            new(
              book_path: normalized_book_path,
              annotation: normalized_annotation.freeze
            )
          end
        end

        def id
          annotation[:id]
        end

        def text
          annotation[:text]
        end

        def note
          annotation[:note]
        end

        def chapter_index
          annotation[:chapter_index]
        end

        def range
          annotation[:range]
        end

        def to_annotation_h
          annotation
        end
      end
    end
  end
end
