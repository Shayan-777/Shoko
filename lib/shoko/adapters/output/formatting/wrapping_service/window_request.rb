# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Formatting
        class WrappingService
          # Immutable description of a wrapped-line window request.
          WindowRequest = Data.define(:lines, :chapter_index, :width, :start, :length, :document) do
            def self.build(*args, document: nil)
              lines, chapter_index, width, start, length = args
              new(
                lines: lines,
                chapter_index: chapter_index,
                width: width.to_i,
                start: [start.to_i, 0].max,
                length: length.to_i,
                document: document
              )
            end

            def valid?
              !lines.nil? && width.positive? && length.positive?
            end

            def cache_key
              [lines.object_id, chapter_index, width]
            end

            def cache_subkey
              [start, length]
            end

            def target_end
              start + length - 1
            end
          end
        end
      end
    end
  end
end
