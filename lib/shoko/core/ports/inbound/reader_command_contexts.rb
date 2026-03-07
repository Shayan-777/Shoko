# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Inbound
        module ReaderOverlayCommandContext
          def open_toc
            raise NotImplementedError, "#{self.class} must implement #open_toc"
          end

          def open_bookmarks
            raise NotImplementedError, "#{self.class} must implement #open_bookmarks"
          end

          def open_annotations_tab
            raise NotImplementedError, "#{self.class} must implement #open_annotations_tab"
          end

          def open_annotations
            raise NotImplementedError, "#{self.class} must implement #open_annotations"
          end

          def show_help(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #show_help"
          end

          def toggle_view_mode(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #toggle_view_mode"
          end

          def increase_line_spacing(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #increase_line_spacing"
          end

          def decrease_line_spacing(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #decrease_line_spacing"
          end

          def toggle_page_numbering_mode(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #toggle_page_numbering_mode"
          end

          def handle_popup_action_key(key = nil)
            raise NotImplementedError, "#{self.class} must implement #handle_popup_action_key"
          end

          def handle_popup_cancel(key = nil)
            raise NotImplementedError, "#{self.class} must implement #handle_popup_cancel"
          end

          def handle_popup_navigation(key = nil)
            raise NotImplementedError, "#{self.class} must implement #handle_popup_navigation"
          end

          def help_exit_to_read(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #help_exit_to_read"
          end

          def read_confirm_or_sidebar(key = nil)
            raise NotImplementedError, "#{self.class} must implement #read_confirm_or_sidebar"
          end

          def read_scroll_down_or_sidebar(key = nil)
            raise NotImplementedError, "#{self.class} must implement #read_scroll_down_or_sidebar"
          end

          def read_scroll_up_or_sidebar(key = nil)
            raise NotImplementedError, "#{self.class} must implement #read_scroll_up_or_sidebar"
          end

          def read_space_or_sidebar_toggle(key = nil)
            raise NotImplementedError, "#{self.class} must implement #read_space_or_sidebar_toggle"
          end
        end

        module ReaderDictionaryCommandContext
          def dictionary_backspace(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_backspace"
          end

          def dictionary_cancel(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_cancel"
          end

          def dictionary_confirm(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_confirm"
          end

          def dictionary_cycle_pair(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_cycle_pair"
          end

          def dictionary_cycle_result(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_cycle_result"
          end

          def dictionary_insert_char_if_printable(key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_insert_char_if_printable"
          end

          def dictionary_scroll_down(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_scroll_down"
          end

          def dictionary_scroll_up(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_scroll_up"
          end

          def dictionary_swap_languages(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_swap_languages"
          end

          def dictionary_toggle_fuzzy(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_toggle_fuzzy"
          end
        end

        module ReaderSearchCommandContext
          def open_in_book_search(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #open_in_book_search"
          end

          def in_book_search_backspace(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #in_book_search_backspace"
          end

          def in_book_search_cancel(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #in_book_search_cancel"
          end

          def in_book_search_confirm(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #in_book_search_confirm"
          end

          def in_book_search_down(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #in_book_search_down"
          end

          def in_book_search_insert_char_if_printable(key = nil)
            raise NotImplementedError, "#{self.class} must implement #in_book_search_insert_char_if_printable"
          end

          def in_book_search_up(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #in_book_search_up"
          end
        end

        module ReaderAnnotationEditorCommandContext
          def annotation_editor_backspace
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_backspace"
          end

          def annotation_editor_cancel
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_cancel"
          end

          def annotation_editor_enter
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_enter"
          end

          def annotation_editor_insert_char_if_printable(key = nil)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_insert_char_if_printable"
          end

          def annotation_editor_move_down
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_move_down"
          end

          def annotation_editor_move_left
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_move_left"
          end

          def annotation_editor_move_right
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_move_right"
          end

          def annotation_editor_move_up
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_move_up"
          end

          def annotation_editor_save
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_save"
          end

          def annotation_editor_spellcheck
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_spellcheck"
          end
        end

        module ReaderLifecycleCommandContext
          def rebuild_pagination
            raise NotImplementedError, "#{self.class} must implement #rebuild_pagination"
          end

          def invalidate_pagination_cache
            raise NotImplementedError, "#{self.class} must implement #invalidate_pagination_cache"
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
