# frozen_string_literal: true

require 'shoko/shared/terminal/mouse_button'
require 'shoko/shared/hash_normalizer'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Owns inline-link hover and click state for reader pointer input.
          class InlineLinkInteraction
            def initialize(inline_link_navigator:, reader_state_reader:, reader_session_mutator:)
              @inline_link_navigator = inline_link_navigator
              @reader_state_reader = reader_state_reader
              @reader_session_mutator = reader_session_mutator
            end

            def consume_click(event, mouse_handler:)
              return false unless @inline_link_navigator
              return false unless click_candidate?(event, mouse_handler)
              return false unless @inline_link_navigator.navigate(event)

              @reader_session_mutator.update_reader(popup_menu: nil, hovered_inline_link: nil)
              @reader_session_mutator.clear_selection
              mouse_handler.reset
              :consumed
            end

            def sync_hover(event)
              return false unless @inline_link_navigator

              next_hover = hover_payload(@inline_link_navigator.link_hit_for_event(event))
              current_hover = normalize_hover(@reader_state_reader&.hovered_inline_link)
              return false if current_hover == next_hover

              @reader_session_mutator.update_reader(hovered_inline_link: next_hover)
              :updated
            end

            private

            def click_candidate?(event, mouse_handler)
              mouse_handler&.selecting &&
                Shoko::Shared::Terminal::MouseButton.left_release?(event) &&
                collapsed_selection?(mouse_handler)
            end

            def hover_payload(hit)
              return nil unless hit.is_a?(Hash)

              start_char = hit[:start_char].to_i
              end_char = hit[:end_char].to_i
              href = hit[:href].to_s.strip
              return nil if end_char <= start_char || href.empty?

              { chapter_index: @reader_state_reader.current_chapter.to_i,
                line_offset: hit[:line_offset].to_i, start_char: start_char,
                end_char: end_char, href: href }
            end

            def normalize_hover(value)
              return nil unless value.is_a?(Hash)

              normalized = Shoko::Shared::HashNormalizer.symbolize_keys(value)
              start_char = normalized[:start_char].to_i
              end_char = normalized[:end_char].to_i
              href = normalized[:href].to_s.strip
              return nil if end_char <= start_char || href.empty?

              { chapter_index: normalized[:chapter_index].to_i,
                line_offset: normalized[:line_offset].to_i, start_char: start_char,
                end_char: end_char, href: href }
            end

            def collapsed_selection?(mouse_handler)
              start_pos = mouse_handler.selection_start
              end_pos = mouse_handler.selection_end
              start_pos && end_pos && start_pos[:x].to_i == end_pos[:x].to_i &&
                start_pos[:y].to_i == end_pos[:y].to_i
            end
          end
        end
      end
    end
  end
end
