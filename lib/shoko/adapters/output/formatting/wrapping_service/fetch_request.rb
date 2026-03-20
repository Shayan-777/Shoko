# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Formatting
        class WrappingService
          # Immutable description of a visible-window fetch + prefetch request.
          FetchRequest = Data.define(
            :document,
            :chapter_index,
            :col_width,
            :offset,
            :display_height,
            :prefetch_pages
          ) do
            def self.build(*args)
              doc, chapter_index, col_width, offset, display_height, pre_pages = args
              new(
                document: doc,
                chapter_index: chapter_index,
                col_width: col_width.to_i,
                offset: [offset.to_i, 0].max,
                display_height: display_height.to_i,
                prefetch_pages: pre_pages
              )
            end

            def valid?
              document && display_height.positive?
            end

            def window_length
              display_height
            end

            def resolved_prefetch_pages(config_reader)
              pages = prefetch_pages.nil? ? config_reader&.prefetch_pages : prefetch_pages
              pages = pages.nil? ? 20 : pages.to_i
              pages.clamp(0, 200)
            end
          end
        end
      end
    end
  end
end
