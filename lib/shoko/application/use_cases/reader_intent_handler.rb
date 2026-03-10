# frozen_string_literal: true

require_relative '../../core/ports/inbound/reader_intent_handler'
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
        include Shoko::Core::Ports::Inbound::ReaderIntentHandler

        def initialize(navigation_service:, bookmark_service:, reader_state_reader:, reader_runtime:)
          @navigation = Shoko::Application::UseCases::Reader::Actions::Navigation.new(
            navigation_service: navigation_service,
            bookmark_service: bookmark_service,
            reader_state_reader: reader_state_reader
          )
          @overlay = Shoko::Application::UseCases::Reader::Actions::Overlay.new(
            reader_runtime: reader_runtime
          )
          @dictionary = Shoko::Application::UseCases::Reader::Actions::Dictionary.new(
            reader_runtime: reader_runtime
          )
          @search = Shoko::Application::UseCases::Reader::Actions::Search.new(
            reader_runtime: reader_runtime
          )
          @annotation_editor = Shoko::Application::UseCases::Reader::Actions::AnnotationEditor.new(
            reader_runtime: reader_runtime
          )
          @lifecycle = Shoko::Application::UseCases::Reader::Actions::Lifecycle.new(
            reader_runtime: reader_runtime
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
          {
            next_page: @navigation,
            prev_page: @navigation,
            scroll_down: @navigation,
            scroll_up: @navigation,
            next_chapter: @navigation,
            prev_chapter: @navigation,
            go_to_start: @navigation,
            go_to_end: @navigation,
            add_bookmark: @navigation,
            open_toc_sidebar: @overlay,
            open_bookmarks_sidebar: @overlay,
            open_annotations_sidebar: @overlay,
            open_annotations_overlay: @overlay,
            open_help_overlay: @overlay,
            close_help_overlay: @overlay,
            toggle_view_mode: @overlay,
            toggle_page_numbering_mode: @overlay,
            increase_line_spacing: @overlay,
            decrease_line_spacing: @overlay,
            toggle_sidebar: @overlay,
            sidebar_move_up: @overlay,
            sidebar_move_down: @overlay,
            sidebar_activate: @overlay,
            popup_move_up: @overlay,
            popup_move_down: @overlay,
            popup_confirm: @overlay,
            popup_cancel: @overlay,
            open_dictionary: @dictionary,
            close_dictionary: @dictionary,
            dictionary_insert_text: @dictionary,
            dictionary_backspace: @dictionary,
            dictionary_confirm: @dictionary,
            dictionary_move_up: @dictionary,
            dictionary_move_down: @dictionary,
            dictionary_cycle_result: @dictionary,
            dictionary_cycle_pair: @dictionary,
            dictionary_swap_languages: @dictionary,
            dictionary_toggle_fuzzy: @dictionary,
            open_in_book_search: @search,
            close_in_book_search: @search,
            search_insert_text: @search,
            search_backspace: @search,
            search_confirm: @search,
            search_move_up: @search,
            search_move_down: @search,
            annotation_editor_insert_text: @annotation_editor,
            annotation_editor_backspace: @annotation_editor,
            annotation_editor_newline: @annotation_editor,
            annotation_editor_move_left: @annotation_editor,
            annotation_editor_move_right: @annotation_editor,
            annotation_editor_move_up: @annotation_editor,
            annotation_editor_move_down: @annotation_editor,
            annotation_editor_save: @annotation_editor,
            annotation_editor_cancel: @annotation_editor,
            annotation_editor_spellcheck: @annotation_editor,
            rebuild_pagination: @lifecycle,
            clear_pagination_cache: @lifecycle,
            quit_to_menu: @lifecycle,
            quit_application: @lifecycle,
          }
        end
      end
    end
  end
end
