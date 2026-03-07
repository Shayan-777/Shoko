# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Inbound
        module MenuNavigationCommandContext
          def menu_nav_up(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #menu_nav_up"
          end

          def menu_nav_down(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #menu_nav_down"
          end

          def menu_select(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #menu_select"
          end

          def menu_back_to_root(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #menu_back_to_root"
          end

          def switch_to_annotations_mode(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #switch_to_annotations_mode"
          end

          def switch_to_browse(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #switch_to_browse"
          end

          def switch_to_search(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #switch_to_search"
          end
        end

        module MenuBrowseCommandContext
          def browse_up(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #browse_up"
          end

          def browse_down(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #browse_down"
          end

          def library_up(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #library_up"
          end

          def library_down(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #library_down"
          end

          def library_select(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #library_select"
          end

          def library_toggle_details(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #library_toggle_details"
          end

          def open_selected_book(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #open_selected_book"
          end
        end

        module MenuSearchCommandContext
          def search_backspace(key = nil)
            raise NotImplementedError, "#{self.class} must implement #search_backspace"
          end

          def search_delete(key = nil)
            raise NotImplementedError, "#{self.class} must implement #search_delete"
          end

          def search_insert_char(key = nil)
            raise NotImplementedError, "#{self.class} must implement #search_insert_char"
          end
        end

        module MenuDownloadCommandContext
          def download_confirm(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #download_confirm"
          end

          def download_down(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #download_down"
          end

          def download_exit_search(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #download_exit_search"
          end

          def download_next_page(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #download_next_page"
          end

          def download_prev_page(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #download_prev_page"
          end

          def download_refresh(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #download_refresh"
          end

          def download_search_backspace(key = nil)
            raise NotImplementedError, "#{self.class} must implement #download_search_backspace"
          end

          def download_search_delete(key = nil)
            raise NotImplementedError, "#{self.class} must implement #download_search_delete"
          end

          def download_search_insert_char(key = nil)
            raise NotImplementedError, "#{self.class} must implement #download_search_insert_char"
          end

          def download_start_search(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #download_start_search"
          end

          def download_submit_search(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #download_submit_search"
          end

          def download_up(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #download_up"
          end
        end

        module MenuDictionaryCommandContext
          def dictionary_back(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_back"
          end

          def dictionary_down(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_down"
          end

          def dictionary_exit_search(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_exit_search"
          end

          def dictionary_refresh(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_refresh"
          end

          def dictionary_search_backspace(key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_search_backspace"
          end

          def dictionary_search_delete(key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_search_delete"
          end

          def dictionary_search_insert_char(key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_search_insert_char"
          end

          def dictionary_select(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_select"
          end

          def dictionary_start_search(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_start_search"
          end

          def dictionary_submit_search(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_submit_search"
          end

          def dictionary_up(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #dictionary_up"
          end
        end

        module MenuAnnotationCommandContext
          def annotations_down(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #annotations_down"
          end

          def annotations_select(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #annotations_select"
          end

          def annotations_up(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #annotations_up"
          end

          def open_selected_annotation(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #open_selected_annotation"
          end

          def open_selected_annotation_for_edit(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #open_selected_annotation_for_edit"
          end

          def delete_selected_annotation(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #delete_selected_annotation"
          end

          def annotation_editor_backspace(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_backspace"
          end

          def annotation_editor_cancel(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_cancel"
          end

          def annotation_editor_enter(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_enter"
          end

          def annotation_editor_insert_char(key = nil)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_insert_char"
          end

          def annotation_editor_move_down(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_move_down"
          end

          def annotation_editor_move_left(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_move_left"
          end

          def annotation_editor_move_right(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_move_right"
          end

          def annotation_editor_move_up(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_move_up"
          end

          def annotation_editor_save(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_save"
          end
        end

        module MenuSettingsCommandContext
          def settings_down(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #settings_down"
          end

          def settings_select(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #settings_select"
          end

          def settings_up(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #settings_up"
          end
        end

        module MenuLifecycleCommandContext
          def menu_quit(_key = nil)
            raise NotImplementedError, "#{self.class} must implement #menu_quit"
          end
        end
      end
    end
  end
end
