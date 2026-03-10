# frozen_string_literal: true

require_relative '../../core/ports/inbound/menu_intent_handler'
require_relative 'menu/actions/navigation'
require_relative 'menu/actions/browse'
require_relative 'menu/actions/search'
require_relative 'menu/actions/dictionary'
require_relative 'menu/actions/download'
require_relative 'menu/actions/annotations'
require_relative 'menu/actions/settings'
require_relative 'menu/actions/lifecycle'

module Shoko
  module Application
    module UseCases
      # Direct application entry point for menu intents.
      class MenuIntentHandler
        include Shoko::Core::Ports::Inbound::MenuIntentHandler

        def initialize(menu_session_store:, menu_mode_control:, menu_browse_inspection:, menu_download_selection:,
                       menu_annotation_control:, application_exit_control:, reader_launch_service:,
                       download_workflow:, dictionary_workflow:, annotation_workflow:, settings_service:,
                       annotation_service:, catalog:, logger: nil)
          @navigation = Shoko::Application::UseCases::Menu::Actions::Navigation.new(
            menu_session_store: menu_session_store,
            menu_mode_control: menu_mode_control,
            application_exit_control: application_exit_control,
            annotation_service: annotation_service,
            logger: logger
          )
          @browse = Shoko::Application::UseCases::Menu::Actions::Browse.new(
            menu_session_store: menu_session_store,
            menu_browse_inspection: menu_browse_inspection,
            reader_launch_service: reader_launch_service
          )
          @search = Shoko::Application::UseCases::Menu::Actions::Search.new(
            menu_session_store: menu_session_store
          )
          @dictionary = Shoko::Application::UseCases::Menu::Actions::Dictionary.new(
            menu_session_store: menu_session_store,
            menu_mode_control: menu_mode_control,
            dictionary_workflow: dictionary_workflow,
            settings_service: settings_service
          )
          @download = Shoko::Application::UseCases::Menu::Actions::Download.new(
            menu_session_store: menu_session_store,
            menu_mode_control: menu_mode_control,
            menu_download_selection: menu_download_selection,
            download_workflow: download_workflow
          )
          @annotations = Shoko::Application::UseCases::Menu::Actions::Annotations.new(
            menu_session_store: menu_session_store,
            menu_mode_control: menu_mode_control,
            menu_annotation_control: menu_annotation_control,
            annotation_workflow: annotation_workflow,
            annotation_service: annotation_service,
            logger: logger
          )
          @settings = Shoko::Application::UseCases::Menu::Actions::Settings.new(
            menu_session_store: menu_session_store,
            settings_service: settings_service,
            catalog: catalog,
            navigation_actions: @navigation,
            dictionary_actions: @dictionary
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
          {
            move_menu_selection_up: @navigation,
            move_menu_selection_down: @navigation,
            activate_menu_selection: @navigation,
            switch_to_menu_mode: @navigation,
            switch_to_browse_mode: @navigation,
            switch_to_search_mode: @navigation,
            move_browse_selection_up: @browse,
            move_browse_selection_down: @browse,
            open_selected_book: @browse,
            browse_insert_text: @search,
            browse_backspace: @search,
            browse_delete: @search,
            move_library_selection_up: @browse,
            move_library_selection_down: @browse,
            activate_library_selection: @browse,
            toggle_library_details: @browse,
            move_settings_selection_up: @settings,
            move_settings_selection_down: @settings,
            activate_settings_selection: @settings,
            open_dictionary_mode: @dictionary,
            close_dictionary_mode: @dictionary,
            refresh_dictionary_results: @dictionary,
            move_dictionary_selection_up: @dictionary,
            move_dictionary_selection_down: @dictionary,
            activate_dictionary_selection: @dictionary,
            dictionary_query_insert_text: @dictionary,
            dictionary_query_backspace: @dictionary,
            dictionary_query_delete: @dictionary,
            submit_dictionary_query: @dictionary,
            open_download_mode: @download,
            close_download_mode: @download,
            refresh_download_results: @download,
            move_download_selection_up: @download,
            move_download_selection_down: @download,
            activate_download_selection: @download,
            download_query_insert_text: @download,
            download_query_backspace: @download,
            download_query_delete: @download,
            submit_download_query: @download,
            download_next_page: @download,
            download_prev_page: @download,
            open_annotations_mode: @annotations,
            move_annotation_selection_up: @annotations,
            move_annotation_selection_down: @annotations,
            activate_annotation_selection: @annotations,
            open_selected_annotation: @annotations,
            edit_selected_annotation: @annotations,
            delete_selected_annotation: @annotations,
            annotation_editor_insert_text: @annotations,
            annotation_editor_backspace: @annotations,
            annotation_editor_newline: @annotations,
            annotation_editor_move_left: @annotations,
            annotation_editor_move_right: @annotations,
            annotation_editor_move_up: @annotations,
            annotation_editor_move_down: @annotations,
            annotation_editor_save: @annotations,
            annotation_editor_cancel: @annotations,
            quit_application: @lifecycle,
          }
        end
      end
    end
  end
end
