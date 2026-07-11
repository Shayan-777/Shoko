# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Normalized view of annotation data for screen rendering.
          class AnnotationView
            def initialize(annotation)
              @annotation = if annotation.is_a?(Hash)
                              Shoko::Shared::HashNormalizer.deep_symbolize(annotation) || {}
                            else
                              {}
                            end
            end

            def text
              fetch(:text).to_s
            end

            def note
              fetch(:note).to_s
            end

            def chapter_index
              fetch(:chapter_index)
            end

            def id
              fetch(:id)
            end

            def formatted_date
              created = fetch(:created_at)
              created.to_s.tr('T', ' ').sub('Z', '')
            end

            private

            def fetch(key)
              @annotation[key]
            end
          end
        end
      end
    end
  end
end
