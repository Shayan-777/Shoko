# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'

module Shoko
  module Core
    module Models
      # Typed selected annotation context used by menu annotation workflows.
      AnnotationSelection = Data.define(:book_path, :annotation) do
        class << self
          def from_h(annotation:, book_path:)
            normalized_book_path = book_path.to_s.strip
            raise ArgumentError, 'AnnotationSelection book_path cannot be blank' if normalized_book_path.empty?
            unless annotation.is_a?(Hash)
              raise ArgumentError, "AnnotationSelection annotation must be a Hash, got #{annotation.class}"
            end

            normalized_annotation = Shoko::Shared::HashNormalizer.symbolize_keys(annotation)
            missing = self::REQUIRED_KEYS.select { |key| normalized_annotation[key].nil? }
            unless missing.empty?
              raise ArgumentError, "AnnotationSelection annotation missing keys: #{missing.join(', ')}"
            end

            new(book_path: normalized_book_path, annotation: normalized_annotation.freeze)
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

        def anchor
          annotation[:anchor]
        end

        def to_annotation_h
          annotation
        end
      end

      AnnotationSelection::REQUIRED_KEYS = %i[id chapter_index].freeze
    end
  end
end
