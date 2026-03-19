# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Dynamic layout restore and cached-layout helpers for PageCalculatorService.
        module PageCalculatorLayoutRestoreSupport
          private

          def sidebar_visible?(value)
            value == true
          end

          def current_dynamic_position(reader_state_reader)
            current_page = @dynamic_layout_cache.raw_page(reader_state_reader.current_page_index.to_i)
            {
              chapter_index: current_page ? current_page[:chapter_index] : reader_state_reader.current_chapter,
              line_offset: current_page ? current_page[:start_line].to_i : 0,
            }
          end

          def build_switched_layout_payload(width:, height:, doc:, visibility:, position:)
            page_index = find_page_index(position[:chapter_index].to_i, position[:line_offset])
            precompute_sidebar_variant(width, height, doc, visibility)
            {
              status: :switched,
              current_page_index: page_index,
              total_pages: total_pages,
              last_width: width,
              last_height: height,
            }
          end

          def perform_dynamic_layout_switch(width:, height:, doc:, sidebar_visible:, reader_state_reader:)
            visibility = sidebar_visible?(sidebar_visible)
            position = current_dynamic_position(reader_state_reader)
            pages = dynamic_layout_pages_for(width, height, doc, sidebar_visible: visibility)
            activate_dynamic_layout_pages(pages, width, height, sidebar_visible: visibility)
            build_switched_layout_payload(
              width: width,
              height: height,
              doc: doc,
              visibility: visibility,
              position: position
            )
          end

          def load_cached_layout_pages(pages, width:, height:, sidebar_visible:)
            @dynamic_layout_cache.load_pages(
              pages: pages,
              key: cached_layout_key(width, height, sidebar_visible),
              width: width,
              height: height,
              sidebar_visible: sidebar_visible
            )
          end

          def cached_layout_key(width, height, sidebar_visible)
            return nil unless width && height

            dynamic_layout_key(width, height, sidebar_visible: sidebar_visible)
          end
        end
      end
    end
  end
end
