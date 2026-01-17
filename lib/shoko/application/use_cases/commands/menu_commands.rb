# frozen_string_literal: true

require_relative 'base_command'

module Shoko
  module Application
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
        ].freeze
        SETTINGS_MAX_INDEX = SETTINGS_ACTIONS.length - 1

        # Actions that delegate directly to context methods
        CONTEXT_DELEGATED_ACTIONS = %i[
          menu_select handle_menu_selection
          browse_select open_selected_book
          library_up library_up
          library_down library_down
          library_select library_select
          toggle_view_mode toggle_view_mode
          cycle_line_spacing cycle_line_spacing
          toggle_page_numbers toggle_page_numbers
          toggle_page_numbering_mode toggle_page_numbering_mode
          toggle_highlight_quotes toggle_highlight_quotes
          open_dictionary_settings open_dictionary_settings
          toggle_kitty_images toggle_kitty_images
          wipe_cache wipe_cache
          annotation_detail_open open_selected_annotation
        ].each_slice(2).to_h.freeze

        # Actions that edit annotations
        ANNOTATION_EDIT_ACTIONS = %i[annotations_edit annotation_detail_edit].freeze

        # Actions that delete annotations
        ANNOTATION_DELETE_ACTIONS = %i[annotations_delete annotation_detail_delete].freeze

        private_constant :SETTINGS_ACTIONS, :SETTINGS_MAX_INDEX,
                         :CONTEXT_DELEGATED_ACTIONS, :ANNOTATION_EDIT_ACTIONS, :ANNOTATION_DELETE_ACTIONS

        def initialize(action)
          @action = action
          super(name: "menu_#{action}", description: "Menu action #{action}")
        end

        def can_execute?(context, _params = {})
          context.respond_to?(:state)
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
            @state = context.state
            @can_switch = context.respond_to?(:switch_to_mode)
            @mmc = context.respond_to?(:main_menu_component) ? context.main_menu_component : nil
          end

          def handle(action)
            return handle_menu_navigation(action) if menu_navigation?(action)
            return handle_browse_navigation(action) if browse_navigation?(action)
            return handle_settings_navigation(action) if settings_navigation?(action)
            return handle_search_action(action) if search_action?(action)
            return handle_annotations_action(action) if annotations_action?(action)
            return handle_mode_switch(action) if mode_switch?(action)
            return delegate_to_context(action) if delegatable?(action)

            :pass
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

          def delegatable?(action)
            CONTEXT_DELEGATED_ACTIONS.key?(action)
          end

          # Handlers
          def handle_menu_navigation(action)
            case action
            when :menu_up then update_index(:selected, -1, 0, 5)
            when :menu_down then update_index(:selected, +1, 0, 5)
            when :menu_select then try_context(:handle_menu_selection)
            when :menu_quit then @context.cleanup_and_exit(0, '') if @context.respond_to?(:cleanup_and_exit)
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
            return @mmc&.annotations_screen&.navigate(:up) if action == :annotations_up
            return @mmc&.annotations_screen&.navigate(:down) if action == :annotations_down
            return handle_annotations_select if action == :annotations_select
            return try_context(:open_selected_annotation_for_edit) if ANNOTATION_EDIT_ACTIONS.include?(action)

            delete_annotation_and_return if ANNOTATION_DELETE_ACTIONS.include?(action)
          end

          def handle_mode_switch(action)
            mode = action == :back_to_menu ? :menu : :annotations
            switch_mode(mode)
          end

          def delegate_to_context(action)
            method_name = CONTEXT_DELEGATED_ACTIONS[action]
            try_context(method_name)
          end

          # Helper methods
          def update_index(field, delta, min_idx, max_idx)
            current = @state.get([:menu, field]) || 0
            new_val = (current + delta).clamp(min_idx, max_idx)
            @state.dispatch(Shoko::Application::Actions::UpdateMenuAction.new(field => new_val))
            new_val
          end

          def switch_mode(mode)
            @context.switch_to_mode(mode) if @can_switch
          end

          def try_context(method)
            @context.public_send(method) if @context.respond_to?(method)
          end

          def browse_nav(delta)
            max_idx = calculate_browse_max_index
            current = @state.get(%i[menu browse_selected]) || 0
            new_val = (current + delta).clamp(0, max_idx)
            @state.dispatch(Shoko::Application::Actions::UpdateMenuAction.new(browse_selected: new_val))
            new_val
          end

          def calculate_browse_max_index
            if @mmc.respond_to?(:browse_screen)
              cnt = @mmc.browse_screen.filtered_count
              [(cnt || 0) - 1, 0].max
            else
              epubs = (@context.respond_to?(:filtered_epubs) && @context.filtered_epubs) || []
              [epubs.length - 1, 0].max
            end
          end

          def perform_settings_select
            index = @state.get(%i[menu settings_selected]) || 0
            action = SETTINGS_ACTIONS[index]
            return unless action

            return switch_mode(:menu) if action == :back_to_menu

            try_context(action)
          end

          def start_search
            if @context.respond_to?(:switch_to_search)
              @context.switch_to_search
            else
              @state.dispatch(Shoko::Application::Actions::UpdateMenuAction.new(mode: :search, search_active: true))
            end
            current = (@state.get(%i[menu search_query]) || '').to_s
            @state.dispatch(Shoko::Application::Actions::UpdateMenuAction.new(search_cursor: current.length))
          end

          def exit_search
            if @context.respond_to?(:switch_to_browse)
              @context.switch_to_browse
            else
              @state.dispatch(Shoko::Application::Actions::UpdateMenuAction.new(mode: :browse, search_active: false))
            end
          end

          def handle_annotations_select
            return unless @mmc

            screen = @mmc.annotations_screen
            ann = screen.current_annotation
            path = screen.current_book_path
            return unless ann && path

            @state.dispatch(Shoko::Application::Actions::UpdateMenuAction.new(
                              selected_annotation: ann, selected_annotation_book: path
                            ))
            switch_mode(:annotation_detail)
          end

          def delete_annotation_and_return
            return unless @context.respond_to?(:delete_selected_annotation)

            @context.delete_selected_annotation
            switch_mode(:annotations)
          end
        end
      end
    end
  end
end
