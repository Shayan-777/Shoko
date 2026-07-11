# frozen_string_literal: true

require_relative '../../application/ports/inbound/menu_intent_handler'
require_relative 'menu_intent_handler/route_groups'
require_relative 'menu/actions/navigation'
require_relative 'menu/actions/browse'
require_relative 'menu/actions/search'
require_relative 'menu/actions/dictionary'
require_relative 'menu/actions/translator_packs'
require_relative 'menu/actions/download'
require_relative 'menu/actions/translator'
require_relative 'menu/actions/rss_reader'
require_relative 'menu/actions/annotations'
require_relative 'menu/actions/settings'
require_relative 'menu/actions/lifecycle'

module Shoko
  module Application
    module UseCases
      # Direct application entry point for menu intents.
      class MenuIntentHandler
        include Shoko::Application::Ports::Inbound::MenuIntentHandler

        ROUTE_GROUPS = MENU_INTENT_ROUTE_GROUPS

        def initialize(
          menu_session_store:,
          app_config_store:,
          menu_browse_inspection:,
          menu_download_selection:,
          menu_annotation_control:,
          menu_translator_control:,
          application_exit_control:,
          reader_launch_service:,
          download_workflow:,
          dictionary_workflow:,
          translator_packs_workflow:,
          translator_workflow:,
          rss_reader_workflow:,
          annotation_workflow:,
          settings_service:,
          annotation_service:,
          catalog:,
          menu_transient_store:,
          logger: nil
        )
          @navigation = Shoko::Application::UseCases::Menu::Actions::Navigation.new(
            menu_session_store: menu_session_store,
            application_exit_control: application_exit_control,
            annotation_service: annotation_service,
            translator_workflow: translator_workflow,
            rss_reader_workflow: rss_reader_workflow,
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
            dictionary_workflow: dictionary_workflow,
            settings_service: settings_service,
            menu_transient_store: menu_transient_store
          )
          @translator_packs = Shoko::Application::UseCases::Menu::Actions::TranslatorPacks.new(
            menu_session_store: menu_session_store,
            translator_packs_workflow: translator_packs_workflow,
            settings_service: settings_service,
            menu_transient_store: menu_transient_store
          )
          @download = Shoko::Application::UseCases::Menu::Actions::Download.new(
            menu_session_store: menu_session_store,
            menu_download_selection: menu_download_selection,
            download_workflow: download_workflow,
            settings_service: settings_service,
            app_config_store: app_config_store,
            menu_transient_store: menu_transient_store
          )
          @translator = Shoko::Application::UseCases::Menu::Actions::Translator.new(
            menu_session_store: menu_session_store,
            translator_workflow: translator_workflow,
            menu_translator_control: menu_translator_control,
            menu_transient_store: menu_transient_store
          )
          @rss_reader = Shoko::Application::UseCases::Menu::Actions::RssReader.new(
            menu_session_store: menu_session_store,
            rss_reader_workflow: rss_reader_workflow,
            menu_transient_store: menu_transient_store
          )
          @annotations = Shoko::Application::UseCases::Menu::Actions::Annotations.new(
            menu_session_store: menu_session_store,
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
            translator_packs_actions: @translator_packs,
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
          route_map_for(
            navigation: @navigation,
            browse: @browse,
            search: @search,
            dictionary: @dictionary,
            translator_packs: @translator_packs,
            download: @download,
            translator: @translator,
            rss_reader: @rss_reader,
            annotations: @annotations,
            settings: @settings,
            lifecycle: @lifecycle
          )
        end

        def route_map_for(actions)
          ROUTE_GROUPS.each_with_object({}) do |(group, intents), acc|
            assign_route_group!(acc, intents, actions.fetch(group))
          end
        end

        def assign_route_group!(routes, intents, action)
          intents.each { |intent| routes[intent] = action }
        end
      end
    end
  end
end
