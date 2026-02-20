# frozen_string_literal: true

require_relative '../../../../shared/text_sanitizer'

module Shoko
  module Adapters::Input::Controllers
    module Menu
      # Centralises dispatcher setup and key handling for the main menu.
      class InputController
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

        attr_reader :dispatcher

        def initialize(menu, key_classifier:, input_system_factory:)
          @menu = menu
          @key_classifier = key_classifier
          @dispatcher = input_system_factory.create_menu_dispatcher(menu)
          register_bindings
          activate_current_mode
        end

        def handle_keys(keys)
          keys.each { |key| dispatcher.handle_key(key) }
        end

        def activate(mode)
          dispatcher.activate(mode)
        end

        private

        attr_reader :menu

        def register_bindings
          register_menu_bindings
          register_browse_bindings
          register_search_bindings
          register_library_bindings
          register_settings_bindings
          register_dictionary_bindings
          register_dictionary_search_bindings
          register_download_bindings
          register_download_search_bindings
          register_annotations_bindings
          register_annotation_detail_bindings
          register_annotation_editor_bindings
        end

        def activate_current_mode
          current_mode = menu.menu_state_reader&.mode
          dispatcher.activate(current_mode)
        end

        def add_back_bindings(bindings)
          keys = Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
          keys.each { |k| bindings[k] = menu_action(:switch_to_mode, :menu) }
          bindings
        end

        def add_confirm_bindings(bindings, action)
          @key_classifier.action_keys(:confirm).each { |k| bindings[k] = menu_action(action) }
          bindings
        end

        def add_nav_up_down(bindings, up_action, down_action)
          @key_classifier.navigation_keys(:up).each { |k| bindings[k] = menu_action(up_action) }
          @key_classifier.navigation_keys(:down).each { |k| bindings[k] = menu_action(down_action) }
          bindings
        end

        def register_menu_bindings
          bindings = {}
          nav_up = @key_classifier.navigation_keys(:up)
          nav_down = @key_classifier.navigation_keys(:down)
          confirm_keys = @key_classifier.action_keys(:confirm)
          quit_keys = @key_classifier.action_keys(:quit)
          nav_up.each { |k| bindings[k] = menu_action(:handle_navigation, :up) }
          nav_down.each { |k| bindings[k] = menu_action(:handle_navigation, :down) }
          confirm_keys.each { |k| bindings[k] = menu_action(:handle_menu_selection) }
          quit_keys.each { |k| bindings[k] = menu_action(:cleanup_and_exit, 0, '') }
          dispatcher.register_mode(:menu, bindings)
        end

        def register_browse_bindings
          bindings = {}
          @key_classifier.navigation_keys(:up).each { |k| bindings[k] = browse_shift_action(-1) }
          @key_classifier.navigation_keys(:down).each { |k| bindings[k] = browse_shift_action(+1) }
          add_confirm_bindings(bindings, :open_selected_book)
          add_back_bindings(bindings)
          bindings['/'] = menu_action(:switch_to_search)
          dispatcher.register_mode(:browse, bindings)
        end

        def register_search_bindings
          bindings = @key_classifier.text_input_commands.text_input_commands(:search_query, nil,
                                                                             cursor_field: :search_cursor)
          @key_classifier.navigation_keys(:up).each { |k| bindings[k] = browse_shift_action(-1) }
          @key_classifier.navigation_keys(:down).each { |k| bindings[k] = browse_shift_action(+1) }

          confirm_keys = @key_classifier.action_keys(:confirm)
          confirm_keys.each { |k| bindings[k] = menu_action(:open_selected_book) }
          bindings['/'] = menu_action(:switch_to_browse)
          @key_classifier.action_keys(:cancel).each { |k| bindings[k] = menu_action(:switch_to_browse) }
          dispatcher.register_mode(:search, bindings)
        end

        def register_library_bindings
          bindings = {}
          add_nav_up_down(bindings, :library_up, :library_down)
          add_confirm_bindings(bindings, :library_select)
          add_back_bindings(bindings)
          dispatcher.register_mode(:library, bindings)
        end

        def register_settings_bindings
          bindings = {}
          @key_classifier.navigation_keys(:up).each { |k| bindings[k] = settings_shift_action(-1) }
          @key_classifier.navigation_keys(:down).each { |k| bindings[k] = settings_shift_action(+1) }
          @key_classifier.action_keys(:confirm).each { |k| bindings[k] = settings_select_action }
          Array(@key_classifier.action_keys(:space)).each { |k| bindings[k] = settings_select_action }
          add_back_bindings(bindings)
          dispatcher.register_mode(:settings, bindings)
        end

        def register_dictionary_bindings
          bindings = {}
          add_nav_up_down(bindings, :dictionary_up, :dictionary_down)
          add_confirm_bindings(bindings, :dictionary_select)
          Array(@key_classifier.action_keys(:space)).each { |k| bindings[k] = menu_action(:dictionary_select) }
          keys = Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
          keys.each { |k| bindings[k] = menu_action(:dictionary_back) }
          bindings['/'] = menu_action(:dictionary_start_search)
          bindings['r'] = menu_action(:dictionary_refresh)
          dispatcher.register_mode(:dictionary, bindings)
        end

        def register_dictionary_search_bindings
          bindings = @key_classifier.text_input_commands.text_input_commands(:dictionary_query, nil,
                                                                             cursor_field: :dictionary_cursor)
          add_confirm_bindings(bindings, :dictionary_submit_search)
          bindings['/'] = menu_action(:dictionary_exit_search)
          @key_classifier.action_keys(:cancel).each { |k| bindings[k] = menu_action(:dictionary_exit_search) }
          dispatcher.register_mode(:dictionary_search, bindings)
        end

        def register_download_bindings
          bindings = {}
          add_nav_up_down(bindings, :download_up, :download_down)
          add_confirm_bindings(bindings, :download_confirm)
          add_back_bindings(bindings)
          bindings['/'] = menu_action(:download_start_search)
          %w[n N].each { |k| bindings[k] = menu_action(:download_next_page) }
          %w[p P].each { |k| bindings[k] = menu_action(:download_prev_page) }
          bindings['r'] = menu_action(:download_refresh)
          dispatcher.register_mode(:download, bindings)
        end

        def register_download_search_bindings
          bindings = @key_classifier.text_input_commands.text_input_commands(:download_query, nil,
                                                                             cursor_field: :download_cursor)
          add_confirm_bindings(bindings, :download_submit_search)
          bindings['/'] = menu_action(:download_exit_search)
          @key_classifier.action_keys(:cancel).each { |k| bindings[k] = menu_action(:download_exit_search) }
          dispatcher.register_mode(:download_search, bindings)
        end

        def register_annotations_bindings
          bindings = {}
          add_nav_up_down(bindings, :annotations_up, :annotations_down)
          add_confirm_bindings(bindings, :annotations_select)
          %w[e E].each { |k| bindings[k] = menu_action(:open_selected_annotation_for_edit) }
          bindings['d'] = menu_action(:delete_selected_annotation)
          add_back_bindings(bindings)
          dispatcher.register_mode(:annotations, bindings)
        end

        def register_annotation_detail_bindings
          bindings = {}
          %w[o O].each { |k| bindings[k] = menu_action(:open_selected_annotation) }
          %w[e E].each { |k| bindings[k] = menu_action(:open_selected_annotation_for_edit) }
          bindings['d'] = menu_action(:delete_selected_annotation)
          @key_classifier.action_keys(:cancel).each { |k| bindings[k] = menu_action(:switch_to_mode, :annotations) }
          dispatcher.register_mode(:annotation_detail, bindings)
        end

        def register_annotation_editor_bindings
          bindings = {}
          @key_classifier.action_keys(:cancel).each { |k| bindings[k] = annotation_editor_action(:cancel_annotation) }
          @key_classifier.action_keys(:quit).each { |k| bindings[k] = annotation_editor_action(:cancel_annotation) }

          @key_classifier.action_keys(:save).each { |k| bindings[k] = annotation_editor_action(:save_annotation) }

          @key_classifier.action_keys(:backspace).each do |k|
            bindings[k] = annotation_editor_action(:handle_backspace)
          end

          enter_keys = []
          enter_action = @key_classifier.action_keys(:enter)
          enter_keys += Array(enter_action) if enter_action
          enter_keys += Array(@key_classifier.action_keys(:confirm))
          enter_keys.each { |k| bindings[k] = annotation_editor_action(:handle_enter) }

          @key_classifier.navigation_keys(:left).each { |k| bindings[k] = annotation_editor_action(:handle_move_left) }
          @key_classifier.navigation_keys(:right).each { |k| bindings[k] = annotation_editor_action(:handle_move_right) }
          @key_classifier.navigation_keys(:up).each { |k| bindings[k] = annotation_editor_action(:handle_move_up) }
          @key_classifier.navigation_keys(:down).each { |k| bindings[k] = annotation_editor_action(:handle_move_down) }

          bindings[:__default__] = annotation_editor_action(:handle_character, character_arg: true)
          dispatcher.register_mode(:annotation_editor, bindings)
        end

        def menu_action(action, *args)
          lambda do |ctx, _|
            if args.empty?
              ctx.public_send(action)
            else
              ctx.public_send(action, *args)
            end
            :handled
          rescue StandardError
            :pass
          end
        end

        def browse_shift_action(delta)
          lambda do |ctx, _|
            max_index = [ctx.browse_items_count.to_i - 1, 0].max
            current = (ctx.menu_state_reader&.browse_selected || 0).to_i
            ctx.menu_state_writer&.update_menu(browse_selected: (current + delta).clamp(0, max_index))
            :handled
          rescue StandardError
            :pass
          end
        end

        def settings_shift_action(delta)
          lambda do |ctx, _|
            current = (ctx.menu_state_reader&.settings_selected || 0).to_i
            ctx.menu_state_writer&.update_menu(settings_selected: (current + delta).clamp(0, SETTINGS_MAX_INDEX))
            :handled
          rescue StandardError
            :pass
          end
        end

        def settings_select_action
          lambda do |ctx, _|
            index = (ctx.menu_state_reader&.settings_selected || 0).to_i
            action = SETTINGS_ACTIONS[index]
            next :pass unless action

            if action == :back_to_menu
              ctx.switch_to_mode(:menu)
            else
              ctx.public_send(action)
            end
            :handled
          rescue StandardError
            :pass
          end
        end

        def annotation_editor_action(action, character_arg: false)
          lambda do |ctx, key|
            editor = annotation_editor_component(ctx)
            next :pass unless editor&.respond_to?(action)

            if character_arg
              char = key.to_s
              next :pass unless Shoko::Shared::TextSanitizer.printable_char?(char)

              editor.public_send(action, char)
            else
              editor.public_send(action)
            end

            if action == :save_annotation || action == :cancel_annotation
              ctx.switch_to_mode(:annotations) if ctx.respond_to?(:switch_to_mode)
            end

            :handled
          rescue StandardError
            :pass
          end
        end

        def annotation_editor_component(ctx)
          return nil unless ctx.respond_to?(:current_editor_component)

          ctx.current_editor_component
        rescue StandardError
          nil
        end
      end
    end
  end
end
