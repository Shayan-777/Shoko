# frozen_string_literal: true

require_relative '../../../../shared/text_sanitizer'
require_relative '../../../../shared/type_coercion'
require_relative 'result_navigator/landing_highlight_support'
require_relative 'result_navigator/wrapped_result_locator'

module Shoko
  module Adapters
    module Input
      module Controllers
        class InBookSearchController
          # Resolves search-result destinations and landing highlights for in-book search.
          class ResultNavigator
            include LandingHighlightSupport
            include WrappedResultLocator

            LANDING_HIGHLIGHT_DURATION = 2.0
            SEARCH_CONTEXT_WINDOW = 64

            ResultOpen = Data.define(:label)

            def initialize(reader_state:, reader_session_mutator:, reader_controller:, state_controller:, page_calculator:, clock:)
              @reader_state = reader_state
              @reader_session_mutator = reader_session_mutator
              @reader_controller = reader_controller
              @state_controller = state_controller
              @page_calculator = page_calculator
              @clock = clock
            end

            def clear_landing_highlight
              @reader_session_mutator&.update_reader(search_landing_highlight: nil)
            end

            def open(result_entry)
              chapter_index = integer_result_value(result_entry, :chapter_index) || 0
              line_offset = resolve_result_line_offset(result_entry, chapter_index: chapter_index)
              return nil unless jump_destination(chapter_index, line_offset)

              set_search_landing_highlight(result_entry, chapter_index: chapter_index, line_offset: line_offset)
              @reader_controller&.draw_screen
              ResultOpen.new(label: chapter_label(result_entry, chapter_index))
            end

            private

            def jump_destination(chapter_index, line_offset)
              controller = resolve_state_controller
              return false unless controller

              controller.jump_to_chapter_offset(chapter_index, line_offset)
              true
            end

            def resolve_state_controller
              return @state_controller if @state_controller
              return nil unless @reader_controller

              @reader_controller.state_controller
            end

            def integer_result_value(entry, key)
              Shoko::Shared::TypeCoercion.optional_integer(result_value(entry, key))
            end

            def extract_search_line_text(line)
              if line.is_a?(Shoko::Core::Models::DisplayLine)
                line.text.to_s
              else
                line.to_s
              end
            end

            def normalize_search_text(text)
              Shoko::Shared::TextSanitizer.sanitize(
                text.to_s,
                preserve_newlines: false,
                preserve_tabs: false
              ).gsub(/\s+/, '').downcase
            end

            def result_value(entry, key)
              value = entry[key]
              value = entry[key.to_s] if value.nil?
              value.to_s
            end
          end
        end
      end
    end
  end
end
