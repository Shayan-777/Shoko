# frozen_string_literal: true

require_relative 'base_command'

module Shoko
  module Application
    module UseCases
      module Commands
        # Menu commands for top-level and browse screens
        class MenuCommand < BaseCommand
          SETTINGS_ACTIONS = %i[
            back_to_menu
            toggle_view_mode
            cycle_line_spacing
            toggle_page_numbering_mode
            toggle_page_numbers
            toggle_highlight_quotes
            open_dictionary_settings
            toggle_kitty_images
            wipe_cache
            toggle_wipe_cache_cached
            toggle_wipe_cache_downloads
            toggle_wipe_cache_annotations
            toggle_wipe_cache_bookmarks
            toggle_wipe_cache_progress
            toggle_wipe_cache_config
            toggle_wipe_cache_nuke
          ].freeze
          SETTINGS_MAX_INDEX = SETTINGS_ACTIONS.length - 1

          # Actions that edit annotations
          ANNOTATION_EDIT_ACTIONS = %i[annotations_edit annotation_detail_edit].freeze

          # Actions that delete annotations
          ANNOTATION_DELETE_ACTIONS = %i[annotations_delete annotation_detail_delete].freeze

          private_constant :SETTINGS_ACTIONS, :SETTINGS_MAX_INDEX,
                           :ANNOTATION_EDIT_ACTIONS, :ANNOTATION_DELETE_ACTIONS

          def initialize(action)
            @action = action
            super(name: "menu_#{action}", description: "Menu action #{action}")
          end

          def can_execute?(context, _params = {})
            !context.nil?
          end

          protected

          def perform(context, _params = {})
            handler = ActionHandlers.new(context)
            handler.handle(@action)
          end

          # Encapsulates action handling logic to reduce method complexity
          class ActionHandlers
            def initialize(context)
              @context = context
              @menu_state_reader = context.menu_state_reader
              @menu_state_writer = context.menu_state_writer
            rescue StandardError
              @menu_state_reader = nil
              @menu_state_writer = nil
            end

            def handle(action)
              return handle_menu_navigation(action) if menu_navigation?(action)
              return handle_browse_navigation(action) if browse_navigation?(action)
            return handle_settings_navigation(action) if settings_navigation?(action)
            return handle_search_action(action) if search_action?(action)
            return handle_annotations_action(action) if annotations_action?(action)
            return handle_mode_switch(action) if mode_switch?(action)
            handle_direct_action(action)
          end

            private

            # Navigation type checks
            def menu_navigation?(action)
              %i[menu_up menu_down menu_select menu_quit].include?(action)
            end

            def browse_navigation?(action)
              %i[browse_up browse_down].include?(action)
            end

            def settings_navigation?(action)
              %i[settings_up settings_down settings_select].include?(action)
            end

            def search_action?(action)
              %i[start_search exit_search].include?(action)
            end

            def annotations_action?(action)
              %i[annotations_up annotations_down annotations_select].include?(action) ||
                ANNOTATION_EDIT_ACTIONS.include?(action) ||
                ANNOTATION_DELETE_ACTIONS.include?(action)
            end

            def mode_switch?(action)
              %i[back_to_menu annotation_detail_back].include?(action)
            end

            # Handlers
            def handle_menu_navigation(action)
              case action
              when :menu_up then update_index(:selected, -1, 0, 5)
              when :menu_down then update_index(:selected, +1, 0, 5)
              when :menu_select then @context.handle_menu_selection
              when :menu_quit then @context.cleanup_and_exit(0, '')
              end
            end

            def handle_browse_navigation(action)
              delta = action == :browse_up ? -1 : +1
              browse_nav(delta)
            end

            def handle_settings_navigation(action)
              case action
              when :settings_up then update_index(:settings_selected, -1, 0, SETTINGS_MAX_INDEX)
              when :settings_down then update_index(:settings_selected, +1, 0, SETTINGS_MAX_INDEX)
              when :settings_select then perform_settings_select
              end
            end

            def handle_search_action(action)
              action == :start_search ? start_search : exit_search
            end

            def handle_annotations_action(action)
              return @context.annotations_up if action == :annotations_up
              return @context.annotations_down if action == :annotations_down
              return @context.annotations_select if action == :annotations_select
              return @context.open_selected_annotation_for_edit if ANNOTATION_EDIT_ACTIONS.include?(action)

              delete_annotation_and_return if ANNOTATION_DELETE_ACTIONS.include?(action)
            end

            def handle_mode_switch(action)
              mode = action == :back_to_menu ? :menu : :annotations
              switch_mode(mode)
            end

            def handle_direct_action(action)
              case action
              when :browse_select then @context.open_selected_book
              when :library_up then @context.library_up
              when :library_down then @context.library_down
              when :library_select then @context.library_select
              when :dictionary_up then @context.dictionary_up
              when :dictionary_down then @context.dictionary_down
              when :dictionary_select then @context.dictionary_select
              when :dictionary_start_search then @context.dictionary_start_search
              when :dictionary_back then @context.dictionary_back
              when :dictionary_submit_search then @context.dictionary_submit_search
              when :dictionary_exit_search then @context.dictionary_exit_search
              when :dictionary_refresh then @context.dictionary_refresh
              when :download_up then @context.download_up
              when :download_down then @context.download_down
              when :download_confirm then @context.download_confirm
              when :download_start_search then @context.download_start_search
              when :download_submit_search then @context.download_submit_search
              when :download_exit_search then @context.download_exit_search
              when :download_next_page then @context.download_next_page
              when :download_prev_page then @context.download_prev_page
              when :download_refresh then @context.download_refresh
              when :toggle_view_mode then @context.toggle_view_mode
              when :cycle_line_spacing then @context.cycle_line_spacing
              when :toggle_page_numbers then @context.toggle_page_numbers
              when :toggle_page_numbering_mode then @context.toggle_page_numbering_mode
              when :toggle_highlight_quotes then @context.toggle_highlight_quotes
              when :open_dictionary_settings then @context.open_dictionary_settings
              when :toggle_kitty_images then @context.toggle_kitty_images
              when :wipe_cache then @context.wipe_cache
              when :toggle_wipe_cache_cached then @context.toggle_wipe_cache_cached
              when :toggle_wipe_cache_downloads then @context.toggle_wipe_cache_downloads
              when :toggle_wipe_cache_annotations then @context.toggle_wipe_cache_annotations
              when :toggle_wipe_cache_bookmarks then @context.toggle_wipe_cache_bookmarks
              when :toggle_wipe_cache_progress then @context.toggle_wipe_cache_progress
              when :toggle_wipe_cache_config then @context.toggle_wipe_cache_config
              when :toggle_wipe_cache_nuke then @context.toggle_wipe_cache_nuke
              when :annotation_detail_open then @context.open_selected_annotation
              else
                :pass
              end
            end

            # Helper methods
            def update_index(field, delta, min_idx, max_idx)
              current = read_menu_field(field)
              new_val = (current + delta).clamp(min_idx, max_idx)
              update_menu(field => new_val)
              new_val
            end

            def switch_mode(mode)
              @context.switch_to_mode(mode)
            end

            def browse_nav(delta)
              max_idx = calculate_browse_max_index
              current = read_menu_field(:browse_selected)
              new_val = (current + delta).clamp(0, max_idx)
              update_menu(browse_selected: new_val)
              new_val
            end

            def calculate_browse_max_index
              cnt = @context.browse_items_count
              [(cnt || 0) - 1, 0].max
            end

            def perform_settings_select
              index = read_menu_field(:settings_selected)
              action = SETTINGS_ACTIONS[index]
              return unless action

              return switch_mode(:menu) if action == :back_to_menu

              handle_direct_action(action)
            end

            def start_search
              @context.switch_to_search
              current = @menu_state_reader&.search_query.to_s
              update_menu(search_cursor: current.length)
            end

            def exit_search
              @context.switch_to_browse
            end

            def delete_annotation_and_return
              @context.delete_selected_annotation
              switch_mode(:annotations)
            end

            def update_menu(attrs)
              @menu_state_writer&.update_menu(attrs)
            end

            def read_menu_field(field)
              return 0 unless @menu_state_reader

              value = case field
                      when :selected then @menu_state_reader.selected
                      when :browse_selected then @menu_state_reader.browse_selected
                      when :settings_selected then @menu_state_reader.settings_selected
                      else 0
                      end
              value.nil? ? 0 : value
            rescue StandardError
              0
            end
          end
        end
      end
    end
  end
end
