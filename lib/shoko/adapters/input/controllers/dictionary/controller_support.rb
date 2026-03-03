# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dictionary
          # Shared controller helpers for UI integration and state access.
          module ControllerSupport
            private

            def dictionary_book_metadata_language
              metadata = @document&.metadata
              return nil unless metadata.is_a?(Hash)

              value = metadata[:language] || metadata['language']
              raw = value.to_s.strip
              return nil if raw.empty?

              raw
            rescue Shoko::Error
              raise
            end

            def remembered_manual_source_for_current_book
              key = current_book_memory_key
              return nil unless key

              @manual_source_lang_by_book[key]
            end

            def remember_manual_source_for_current_book(source_lang)
              key = current_book_memory_key
              return unless key

              @manual_source_lang_by_book[key] = source_lang
            end

            def current_book_memory_key
              path = @reader_state.book_path || @document&.source_path
              text = path.to_s.strip
              return nil if text.empty?

              text
            rescue Shoko::Error
              raise
            end

            def draw_dictionary_screen
              @reader_controller&.draw_screen
            rescue Shoko::Error
              raise
            end

            def ui_component_factory
              @ui_component_factory_inst
            end

            def dictionary_panel_component?(component)
              factory = ui_component_factory
              factory ? factory.dictionary_panel_component?(component) : false
            end

            def dictionary_panel_min_terminal_width
              factory = ui_component_factory
              factory ? factory.dictionary_panel_min_terminal_width : 1_000_000
            end

            def dictionary_panel_min_width
              factory = ui_component_factory
              factory ? factory.dictionary_panel_min_width : 1_000_000
            end

            def extract_lookup_word(text)
              cleaned = text.to_s.strip.gsub(/\s+/, ' ')
              words = cleaned.split
              if words.length <= 3
                cleaned
              else
                words.first
              end
            end

            def activate_dictionary_mode
              @input_controller&.enter_modal_mode(:dictionary)
            end

            def deactivate_dictionary_mode
              @input_controller&.exit_modal_mode(:dictionary)
            end

            def dictionary_book_language
              @document&.language
            end

            def extract_selected_text_from_selection(selection_range)
              return nil unless @selection_service && @rendered_content_reader

              rendered_lines = @rendered_content_reader.rendered_lines
              @selection_service.extract_text(selection_range, rendered_lines)
            end

            def set_message(text, duration = 2)
              if @notification_service
                @notification_service.set_message(text, duration)
              else
                @state_writer.update_reader(message: text)
              end
            rescue Shoko::Error
              @state_writer.update_reader(message: text)
            end

            def cleanup_popup_state
              @ui_controller&.cleanup_popup_state
            rescue Shoko::Error
              # Best effort.
            end
          end
        end
      end
    end
  end
end
