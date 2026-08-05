# frozen_string_literal: true

require 'shoko/core/models/reading_progress'
require 'shoko/shared/hash_normalizer'

module Shoko
  module Adapters
    module Storage
      module Codecs
        # Owns the progress-file record shape and its legacy chapter key.
        module ReadingProgressCodec
          module_function

          def load(payload)
            return nil unless payload

            fields = Shared::HashNormalizer.symbolize_keys(payload) || {}
            Core::Models::ReadingProgress.new(
              chapter_index: fields.fetch(:chapter),
              line_offset: fields.fetch(:line_offset),
              timestamp: fields.fetch(:timestamp),
              anchor: fields[:anchor]
            )
          end

          def dump(progress)
            {
              chapter: progress.chapter_index,
              line_offset: progress.line_offset,
              timestamp: progress.timestamp,
              anchor: progress.anchor,
            }
          end
        end
      end
    end
  end
end
