# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module MouseableReaderSupport
          # Owns inline-link hover and click behavior for mouseable reader interactions.
          class InlineLinkInteraction
            def initialize(inline_link_navigator:, reader_state_reader:, reader_session_mutator:)
              @inline_link_navigator = inline_link_navigator
              @reader_state_reader = reader_state_reader
              @reader_session_mutator = reader_session_mutator
            end

            def consume_click(event, mouse_handler:)
              return false unless @inline_link_navigator
              return false unless inline_link_click_candidate?(event, mouse_handler)

              navigated = @inline_link_navigator.navigate(event)
              return false unless navigated

              @reader_session_mutator.update_reader(popup_menu: nil, hovered_inline_link: nil)
              @reader_session_mutator.clear_selection
              mouse_handler.reset
              true
            end

            def sync_hover(event)
              return false unless @inline_link_navigator

              next_hover = hovered_inline_link_payload(@inline_link_navigator.link_hit_for_event(event))
              current_hover = normalize_hovered_inline_link(@reader_state_reader&.hovered_inline_link)
              return false if current_hover == next_hover

              @reader_session_mutator.update_reader(hovered_inline_link: next_hover)
              true
            end

            private

            def inline_link_click_candidate?(event, mouse_handler)
              return false unless mouse_handler&.selecting

              button = event[:button].to_i
              return false unless event[:released] && button.nobits?(0b11) && button.nobits?(32)

              start_pos = mouse_handler.selection_start
              end_pos = mouse_handler.selection_end
              return false unless start_pos && end_pos

              start_pos[:x].to_i == end_pos[:x].to_i &&
                start_pos[:y].to_i == end_pos[:y].to_i
            end

            def hovered_inline_link_payload(hit)
              return nil unless hit.is_a?(Hash)

              start_char = hit[:start_char].to_i
              end_char = hit[:end_char].to_i
              return nil if end_char <= start_char

              href = hit[:href].to_s.strip
              return nil if href.empty?

              {
                chapter_index: @reader_state_reader.current_chapter.to_i,
                line_offset: hit[:line_offset].to_i,
                start_char: start_char,
                end_char: end_char,
                href: href,
              }
            end

            def normalize_hovered_inline_link(value)
              return nil unless value.is_a?(Hash)

              start_char = (value[:start_char] || value['start_char']).to_i
              end_char = (value[:end_char] || value['end_char']).to_i
              href = (value[:href] || value['href']).to_s.strip
              return nil if end_char <= start_char || href.empty?

              {
                chapter_index: (value[:chapter_index] || value['chapter_index']).to_i,
                line_offset: (value[:line_offset] || value['line_offset']).to_i,
                start_char: start_char,
                end_char: end_char,
                href: href,
              }
            end
          end
        end
      end
    end
  end
end
