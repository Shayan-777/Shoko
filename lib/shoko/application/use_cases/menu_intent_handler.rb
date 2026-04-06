# frozen_string_literal: true

require_relative '../../core/ports/inbound/menu_intent_handler'
require_relative 'menu/actions/navigation'
require_relative 'menu/actions/browse'
require_relative 'menu/actions/search'
require_relative 'menu/actions/dictionary'
require_relative 'menu/actions/download'
require_relative 'menu/actions/translator'
require_relative 'menu/actions/annotations'
require_relative 'menu/actions/settings'
require_relative 'menu/actions/lifecycle'

module Shoko
  module Application
    module UseCases
      # Direct application entry point for menu intents.
      class MenuIntentHandler
        include Shoko::Core::Ports::Inbound::MenuIntentHandler

        ROUTE_GROUPS = {
          navigation: %i[
            move_menu_selection_up
            move_menu_selection_down
            activate_menu_selection
            switch_to_menu_mode
            switch_to_browse_mode
            switch_to_search_mode
          ],
          browse: %i[
            move_browse_selection_up
            move_browse_selection_down
            open_selected_book
            move_library_selection_up
            move_library_selection_down
            activate_library_selection
            toggle_library_details
          ],
          search: %i[
            browse_insert_text
            browse_backspace
            browse_delete
          ],
          dictionary: %i[
            open_dictionary_mode
            close_dictionary_mode
            refresh_dictionary_results
            move_dictionary_selection_up
            move_dictionary_selection_down
            activate_dictionary_selection
            dictionary_query_insert_text
            dictionary_query_backspace
            dictionary_query_delete
            submit_dictionary_query
          ],
          download: %i[
            open_download_mode
            close_download_mode
            open_download_source_mode
            close_download_source_mode
            refresh_download_results
            move_download_selection_up
            move_download_selection_down
            move_download_source_selection_up
            move_download_source_selection_down
            activate_download_selection
            activate_download_source_selection
            download_query_insert_text
            download_query_backspace
            download_query_delete
            submit_download_query
            download_next_page
            download_prev_page
          ],
          translator: %i[
            close_translator_mode
            close_translator_dropdown
            translator_cycle_focus
            translator_activate_focus
            translator_swap_languages
            translator_input_insert_text
            translator_input_backspace
            translator_input_delete
            move_translator_language_selection_up
            move_translator_language_selection_down
            activate_translator_language_selection
          ],
          annotations: %i[
            open_annotations_mode
            move_annotation_selection_up
            move_annotation_selection_down
            activate_annotation_selection
            open_selected_annotation
            edit_selected_annotation
            delete_selected_annotation
            annotation_editor_insert_text
            annotation_editor_backspace
            annotation_editor_newline
            annotation_editor_move_left
            annotation_editor_move_right
            annotation_editor_move_up
            annotation_editor_move_down
            annotation_editor_save
            annotation_editor_cancel
          ],
          settings: %i[
            move_settings_selection_up
            move_settings_selection_down
            activate_settings_selection
          ],
          lifecycle: %i[quit_application],
        }.freeze

        def initialize(
          menu_session_store:,
          app_config_store:,
          menu_mode_control:,
          menu_browse_inspection:,
          menu_download_selection:,
          menu_annotation_control:,
          application_exit_control:,
          reader_launch_service:,
          download_workflow:,
          dictionary_workflow:,
          translator_workflow:,
          annotation_workflow:,
          settings_service:,
          annotation_service:,
          catalog:,
          menu_transient_store:,
          logger: nil
        )
          @navigation = Shoko::Application::UseCases::Menu::Actions::Navigation.new(
            menu_session_store: menu_session_store,
            menu_mode_control: menu_mode_control,
            application_exit_control: application_exit_control,
            annotation_service: annotation_service,
            translator_workflow: translator_workflow,
            menu_transient_store: menu_transient_store,
            logger: logger
          )
          @browse = Shoko::Application::UseCases::Menu::Actions::Browse.new(
            menu_session_store: menu_session_store,
            menu_browse_inspection: menu_browse_inspection,
            reader_launch_service: reader_launch_service,
            menu_transient_store: menu_transient_store
          )
          @search = Shoko::Application::UseCases::Menu::Actions::Search.new(
            menu_session_store: menu_session_store,
            menu_transient_store: menu_transient_store
          )
          @dictionary = Shoko::Application::UseCases::Menu::Actions::Dictionary.new(
            menu_session_store: menu_session_store,
            menu_mode_control: menu_mode_control,
            dictionary_workflow: dictionary_workflow,
            settings_service: settings_service,
            menu_transient_store: menu_transient_store
          )
          @download = Shoko::Application::UseCases::Menu::Actions::Download.new(
            menu_session_store: menu_session_store,
            menu_mode_control: menu_mode_control,
            menu_download_selection: menu_download_selection,
            download_workflow: download_workflow,
            settings_service: settings_service,
            app_config_store: app_config_store,
            menu_transient_store: menu_transient_store
          )
          @translator = Shoko::Application::UseCases::Menu::Actions::Translator.new(
            menu_session_store: menu_session_store,
            menu_mode_control: menu_mode_control,
            translator_workflow: translator_workflow,
            menu_transient_store: menu_transient_store
          )
          @annotations = Shoko::Application::UseCases::Menu::Actions::Annotations.new(
            menu_session_store: menu_session_store,
            menu_mode_control: menu_mode_control,
            menu_annotation_control: menu_annotation_control,
            annotation_workflow: annotation_workflow,
            annotation_service: annotation_service,
            menu_transient_store: menu_transient_store,
            logger: logger
          )
          @settings = Shoko::Application::UseCases::Menu::Actions::Settings.new(
            menu_session_store: menu_session_store,
            settings_service: settings_service,
            catalog: catalog,
            navigation_actions: @navigation,
            dictionary_actions: @dictionary,
            menu_transient_store: menu_transient_store
          )
          @lifecycle = Shoko::Application::UseCases::Menu::Actions::Lifecycle.new(
            application_exit_control: application_exit_control
          )
          @routes = build_routes
        end

        def handle_menu_intent(intent_symbol, payload = nil)
          intent = intent_symbol.to_sym
          raise ArgumentError, "unsupported menu intent: #{intent}" unless INTENT_SYMBOLS.include?(intent)

          action = @routes[intent]
          raise ArgumentError, "missing action group for menu intent: #{intent}" if action.nil?

          action.call(intent, payload)
        end

        private

        def build_routes
          actions = {
            navigation: @navigation,
            browse: @browse,
            search: @search,
            dictionary: @dictionary,
            download: @download,
            translator: @translator,
            annotations: @annotations,
            settings: @settings,
            lifecycle: @lifecycle,
          }

          ROUTE_GROUPS.each_with_object({}) do |(group, intents), acc|
            action = actions.fetch(group)
            intents.each { |intent| acc[intent] = action }
          end
        end
      end
    end
  end
end
