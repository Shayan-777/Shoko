# frozen_string_literal: true

require_relative '../../application/ports/inbound/reader_intent_handler'
require_relative 'reader/actions/navigation'
require_relative 'reader/actions/overlay'
require_relative 'reader/actions/dictionary'
require_relative 'reader/actions/search'
require_relative 'reader/actions/annotation_editor'
require_relative 'reader/actions/lifecycle'

module Shoko
  module Application
    module UseCases
      # Direct application entry point for reader intents.
      class ReaderIntentHandler
        include Shoko::Application::Ports::Inbound::ReaderIntentHandler

        ROUTE_GROUPS = {
          navigation: %i[
            next_page
            prev_page
            scroll_down
            scroll_up
            next_chapter
            prev_chapter
            go_to_start
            go_to_end
            add_bookmark
          ],
          overlay: %i[
            open_toc_sidebar
            open_bookmarks_sidebar
            open_annotations_sidebar
            open_annotations_overlay
            open_help_overlay
            close_help_overlay
            toggle_view_mode
            toggle_page_numbering_mode
            increase_line_spacing
            decrease_line_spacing
            toggle_sidebar
            sidebar_move_up
            sidebar_move_down
            sidebar_activate
            popup_move_up
            popup_move_down
            popup_confirm
            popup_cancel
          ],
          dictionary: %i[
            open_dictionary
            close_dictionary
            edit_reader_dictionary_query
            dictionary_confirm
            dictionary_move_up
            dictionary_move_down
            dictionary_cycle_result
            dictionary_cycle_pair
            dictionary_swap_languages
            dictionary_toggle_fuzzy
          ],
          search: %i[
            open_in_book_search
            close_in_book_search
            edit_in_book_search
            search_confirm
            search_move_up
            search_move_down
          ],
          annotation_editor: %i[
            edit_annotation_text
            move_annotation_cursor
            annotation_editor_save
            annotation_editor_cancel
            annotation_editor_spellcheck
          ],
          lifecycle: %i[
            rebuild_pagination
            clear_pagination_cache
            quit_to_menu
            quit_application
          ],
        }.freeze

        def initialize(navigation_service:, bookmark_service:, reader_session_store:,
                       reader_view_state_store:, reader_view_mutator:, app_config_store:,
                       notification_writer:, reader_overlay_control:, reader_popup_control:,
                       reader_dictionary_control:, reader_search_control:,
                       reader_annotation_editor_control:, reader_lifecycle_control:,
                       application_exit_control:, annotation_service:)
          @navigation = Shoko::Application::UseCases::Reader::Actions::Navigation.new(
            navigation_service: navigation_service,
            bookmark_service: bookmark_service,
            reader_session_store: reader_session_store
          )
          @overlay = Shoko::Application::UseCases::Reader::Actions::Overlay.new(
            reader_overlay_control: reader_overlay_control,
            reader_popup_control: reader_popup_control,
            reader_view_mutator: reader_view_mutator,
            app_config_store: app_config_store,
            notification_writer: notification_writer
          )
          @dictionary = Shoko::Application::UseCases::Reader::Actions::Dictionary.new(
            reader_dictionary_control: reader_dictionary_control
          )
          @search = Shoko::Application::UseCases::Reader::Actions::Search.new(
            reader_search_control: reader_search_control
          )
          @annotation_editor = Shoko::Application::UseCases::Reader::Actions::AnnotationEditor.new(
            reader_session_store: reader_session_store,
            reader_view_state_store: reader_view_state_store,
            reader_view_mutator: reader_view_mutator,
            reader_annotation_editor_control: reader_annotation_editor_control,
            annotation_service: annotation_service,
            notification_writer: notification_writer
          )
          @lifecycle = Shoko::Application::UseCases::Reader::Actions::Lifecycle.new(
            reader_lifecycle_control: reader_lifecycle_control,
            application_exit_control: application_exit_control
          )
          @routes = build_routes
        end

        def handle_reader_intent(intent_symbol, payload = nil)
          intent = intent_symbol.to_sym
          raise ArgumentError, "unsupported reader intent: #{intent}" unless INTENT_SYMBOLS.include?(intent)

          action = @routes[intent]
          raise ArgumentError, "missing action group for reader intent: #{intent}" if action.nil?

          action.call(intent, payload)
        end

        private

        def build_routes
          actions = {
            navigation: @navigation,
            overlay: @overlay,
            dictionary: @dictionary,
            search: @search,
            annotation_editor: @annotation_editor,
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
