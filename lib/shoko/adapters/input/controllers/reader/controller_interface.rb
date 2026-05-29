# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Centralizes ReaderController delegation and alias wiring so the
          # controller stays focused on runtime coordination.
          module ControllerInterface
            CONTEXT_DELEGATORS = {
              context: %i[path doc metrics_start_time],
              services: %i[page_calculator terminal_service clipboard_service instrumentation],
              controllers: %i[ui_controller state_controller input_controller],
              coordinators: %i[lifecycle pagination_coordinator render_coordinator],
            }.freeze

            UI_CONTROLLER_METHODS = %i[
              switch_mode
              open_toc
              open_bookmarks
              open_annotations_tab
              open_annotations
              show_help
              toggle_view_mode
              increase_line_spacing
              decrease_line_spacing
              toggle_page_numbering_mode
              sidebar_down
              sidebar_up
              sidebar_select
              sidebar_toggle_toc
              handle_popup_action
              close_dictionary
              dictionary_insert_char
              dictionary_backspace
              dictionary_confirm
              dictionary_cancel
              dictionary_tab
              dictionary_swap_languages
              dictionary_scroll_up
              dictionary_scroll_down
              dictionary_toggle_fuzzy
              dictionary_cycle_result
              dictionary_cycle_pair
              open_in_book_search
              close_in_book_search
              submit_in_book_search
              open_search_result
              annotation_editor_move_left
              annotation_editor_move_right
              annotation_editor_move_up
              annotation_editor_move_down
              annotation_editor_spellcheck
              close_annotation_editor_overlay
            ].freeze

            STATE_CONTROLLER_METHODS = %i[
              save_progress
              load_progress
              load_bookmarks
              add_bookmark
              jump_to_bookmark
              delete_selected_bookmark
              quit_to_menu
              quit_application
            ].freeze

            INPUT_CONTROLLER_METHODS = %i[
              handle_popup_navigation
              handle_popup_action_key
              handle_popup_cancel
              handle_popup_menu_input
            ].freeze

            RENDER_COORDINATOR_METHODS = %i[
              draw_screen
              refresh_highlighting
              force_redraw
              render_loading_overlay
              build_component_layout
              rebuild_root_layout
              apply_theme_palette
            ].freeze

            PAGINATION_COORDINATOR_METHODS = %i[
              pending_initial_calculation?
              perform_initial_calculations_if_needed
              defer_page_map?
              schedule_background_page_map_build
              clear_defer_page_map!
              rebuild_pagination
              invalidate_pagination_cache
            ].freeze

            ALIASED_READERS = {
              navigation_service: :navigation_service_ref,
              bookmark_service: :bookmark_service_ref,
              popup_position_service: :popup_position_service_ref,
              logger: :logger_ref,
              process_control: :process_control_ref,
              clock: :clock_ref,
              selection_service: :selection_service_ref,
              coordinate_service: :coordinate_service_ref,
              annotation_service: :annotation_service_ref,
            }.freeze

            def self.apply_to(klass)
              CONTEXT_DELEGATORS.each do |target, methods|
                klass.def_delegators target, *methods
              end

              klass.def_delegators :ui_controller, *UI_CONTROLLER_METHODS
              klass.def_delegators :state_controller, *STATE_CONTROLLER_METHODS
              klass.def_delegators :input_controller, *INPUT_CONTROLLER_METHODS
              klass.def_delegators :render_coordinator, *RENDER_COORDINATOR_METHODS
              klass.def_delegators :pagination_coordinator, *PAGINATION_COORDINATOR_METHODS
              klass.def_delegators :lifecycle, :run, :background_worker
              klass.include AliasReaders
            end

            # Named readers keep call sites expressive without exposing the
            # internal `_ref` storage names outside the controller.
            module AliasReaders
              ALIASED_READERS.each do |public_name, attr_name|
                define_method(public_name) { public_send(attr_name) }
              end
            end
          end
        end
      end
    end
  end
end
