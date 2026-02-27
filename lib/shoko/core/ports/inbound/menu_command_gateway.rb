# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Inbound
        # Explicit menu-facing inbound command contract.
        module MenuCommandGateway
          COMMAND_METHODS = %i[
            annotation_editor_backspace
            annotation_editor_cancel
            annotation_editor_enter
            annotation_editor_insert_char
            annotation_editor_move_down
            annotation_editor_move_left
            annotation_editor_move_right
            annotation_editor_move_up
            annotation_editor_save
            annotations_down
            annotations_select
            annotations_up
            browse_down
            browse_up
            delete_selected_annotation
            dictionary_back
            dictionary_down
            dictionary_exit_search
            dictionary_refresh
            dictionary_search_backspace
            dictionary_search_delete
            dictionary_search_insert_char
            dictionary_select
            dictionary_start_search
            dictionary_submit_search
            dictionary_up
            download_confirm
            download_down
            download_exit_search
            download_next_page
            download_prev_page
            download_refresh
            download_search_backspace
            download_search_delete
            download_search_insert_char
            download_start_search
            download_submit_search
            download_up
            library_down
            library_select
            library_up
            menu_back_to_root
            menu_nav_down
            menu_nav_up
            menu_quit
            menu_select
            open_selected_annotation
            open_selected_annotation_for_edit
            open_selected_book
            search_backspace
            search_delete
            search_insert_char
            settings_down
            settings_select
            settings_up
            switch_to_annotations_mode
            switch_to_browse
            switch_to_search
          ].freeze

          COMMAND_METHODS.each do |method_name|
            define_method(method_name) do |_key = nil|
              raise NotImplementedError, "#{self.class} must implement ##{method_name}"
            end
          end

          def command_logger
            raise NotImplementedError, "#{self.class} must implement #command_logger"
          end
        end
      end
    end
  end
end
