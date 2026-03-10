# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Adapter runtime contract for reader intent handling.
        module ReaderIntentRuntime
          def sidebar_visible?
            raise NotImplementedError, "#{self.class} must implement #sidebar_visible?"
          end

          def sidebar_toc_tab?
            raise NotImplementedError, "#{self.class} must implement #sidebar_toc_tab?"
          end

          def open_toc_sidebar
            raise NotImplementedError, "#{self.class} must implement #open_toc_sidebar"
          end

          def open_bookmarks_sidebar
            raise NotImplementedError, "#{self.class} must implement #open_bookmarks_sidebar"
          end

          def open_annotations_sidebar
            raise NotImplementedError, "#{self.class} must implement #open_annotations_sidebar"
          end

          def open_annotations_overlay
            raise NotImplementedError, "#{self.class} must implement #open_annotations_overlay"
          end

          def open_help_overlay
            raise NotImplementedError, "#{self.class} must implement #open_help_overlay"
          end

          def close_help_overlay
            raise NotImplementedError, "#{self.class} must implement #close_help_overlay"
          end

          def toggle_view_mode
            raise NotImplementedError, "#{self.class} must implement #toggle_view_mode"
          end

          def toggle_page_numbering_mode
            raise NotImplementedError, "#{self.class} must implement #toggle_page_numbering_mode"
          end

          def increase_line_spacing
            raise NotImplementedError, "#{self.class} must implement #increase_line_spacing"
          end

          def decrease_line_spacing
            raise NotImplementedError, "#{self.class} must implement #decrease_line_spacing"
          end

          def toggle_sidebar
            raise NotImplementedError, "#{self.class} must implement #toggle_sidebar"
          end

          def sidebar_move(delta)
            raise NotImplementedError, "#{self.class} must implement #sidebar_move"
          end

          def sidebar_activate
            raise NotImplementedError, "#{self.class} must implement #sidebar_activate"
          end

          def open_dictionary
            raise NotImplementedError, "#{self.class} must implement #open_dictionary"
          end

          def close_dictionary
            raise NotImplementedError, "#{self.class} must implement #close_dictionary"
          end

          def dictionary_insert_text(text)
            raise NotImplementedError, "#{self.class} must implement #dictionary_insert_text"
          end

          def dictionary_backspace
            raise NotImplementedError, "#{self.class} must implement #dictionary_backspace"
          end

          def dictionary_confirm
            raise NotImplementedError, "#{self.class} must implement #dictionary_confirm"
          end

          def dictionary_move(delta)
            raise NotImplementedError, "#{self.class} must implement #dictionary_move"
          end

          def dictionary_cycle_result
            raise NotImplementedError, "#{self.class} must implement #dictionary_cycle_result"
          end

          def dictionary_cycle_pair
            raise NotImplementedError, "#{self.class} must implement #dictionary_cycle_pair"
          end

          def dictionary_swap_languages
            raise NotImplementedError, "#{self.class} must implement #dictionary_swap_languages"
          end

          def dictionary_toggle_fuzzy
            raise NotImplementedError, "#{self.class} must implement #dictionary_toggle_fuzzy"
          end

          def open_in_book_search
            raise NotImplementedError, "#{self.class} must implement #open_in_book_search"
          end

          def close_in_book_search
            raise NotImplementedError, "#{self.class} must implement #close_in_book_search"
          end

          def search_insert_text(text)
            raise NotImplementedError, "#{self.class} must implement #search_insert_text"
          end

          def search_backspace
            raise NotImplementedError, "#{self.class} must implement #search_backspace"
          end

          def search_confirm
            raise NotImplementedError, "#{self.class} must implement #search_confirm"
          end

          def search_move(delta)
            raise NotImplementedError, "#{self.class} must implement #search_move"
          end

          def annotation_editor_insert_text(text)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_insert_text"
          end

          def annotation_editor_backspace
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_backspace"
          end

          def annotation_editor_newline
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_newline"
          end

          def annotation_editor_move(direction)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_move"
          end

          def annotation_editor_save
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_save"
          end

          def annotation_editor_cancel
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_cancel"
          end

          def annotation_editor_spellcheck
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_spellcheck"
          end

          def popup_move(delta)
            raise NotImplementedError, "#{self.class} must implement #popup_move"
          end

          def popup_confirm
            raise NotImplementedError, "#{self.class} must implement #popup_confirm"
          end

          def popup_cancel
            raise NotImplementedError, "#{self.class} must implement #popup_cancel"
          end

          def rebuild_pagination
            raise NotImplementedError, "#{self.class} must implement #rebuild_pagination"
          end

          def clear_pagination_cache
            raise NotImplementedError, "#{self.class} must implement #clear_pagination_cache"
          end

          def quit_to_menu
            raise NotImplementedError, "#{self.class} must implement #quit_to_menu"
          end

          def quit_application
            raise NotImplementedError, "#{self.class} must implement #quit_application"
          end
        end
      end
    end
  end
end
