# frozen_string_literal: true

require_relative 'support/message_notifier'
require_relative 'support/session_outcome_helpers'
require_relative 'in_book_search/result_navigator'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Handles in-book full text search popup lifecycle, search execution, and
        # result navigation. Query/selection state lives in the reader view-state
        # store and is written application-side; the popup component re-renders
        # from it. This controller owns only operations that need adapter
        # coordination: surface lifecycle + modal mode, running the document-bound
        # search service, and navigating to a selected result.
        class InBookSearchController
          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier
          include Shoko::Adapters::Input::Controllers::Support::SessionOutcomeHelpers

          def initialize(reader_state:, reader_session_mutator:, search_service:,
                         input_controller: nil, reader_controller: nil, state_controller: nil,
                         notification_service: nil, logger: nil, in_book_search_ui_session: nil,
                         clock: nil)
            @reader_state = reader_state
            @search_service = search_service
            @input_controller = input_controller
            @notification_service = notification_service
            @logger = logger
            @in_book_search_ui_session = in_book_search_ui_session
            @result_navigator = ResultNavigator.new(
              reader_state: reader_state,
              reader_session_mutator: reader_session_mutator,
              reader_controller: reader_controller,
              state_controller: state_controller,
              page_calculator: reader_controller&.page_calculator,
              clock: clock
            )
            raise ArgumentError, 'notification_service is required' if @notification_service.nil?
          end

          def open_in_book_search(_key = nil)
            @result_navigator.clear_landing_highlight
            result = @in_book_search_ui_session.open
            return :pass unless session_ok?(result)

            activate_search_mode
            set_message('In-book search: type query, press Enter to search', 2)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('in_book_search.open_failed', error: e.message)
            :pass
          end

          def close_in_book_search(_key = nil)
            mode = @reader_state.mode
            return :pass unless @in_book_search_ui_session.visible? || mode == :in_book_search

            result = @in_book_search_ui_session.close
            return :pass unless session_ok?(result)

            deactivate_search_mode
            :handled
          rescue Shoko::Error => e
            @logger&.debug('in_book_search.close_failed', error: e.message)
            :pass
          end

          def submit_in_book_search(_key = nil)
            query = @reader_state.search_query.to_s
            result = @search_service.search(query)
            outcome = @in_book_search_ui_session.apply_results(
              query: result.query,
              results: result.matches,
              total_matches: result.total_matches
            )
            return :pass unless session_ok?(outcome)

            announce_result_message(result)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('in_book_search.submit_failed', error: e.message)
            :pass
          end

          def open_search_result(result_entry)
            outcome = @result_navigator.open(result_entry)
            return :pass unless outcome

            close_in_book_search
            set_message("Opened result in #{outcome.label}", 2)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('in_book_search.open_result_failed', error: e.message)
            :pass
          end

          def refresh_theme(theme_context:)
            color_mode = theme_context&.color_mode
            @in_book_search_ui_session&.refresh_theme(color_mode: color_mode)
          end

          def in_book_search_visible?
            @in_book_search_ui_session.visible? == true
          end

          private

          def announce_result_message(result)
            query = result.query.to_s
            return if query.empty?

            total = result.total_matches.to_i
            if total.zero?
              set_message("No matches for '#{query}'", 2)
            elsif result.matches.length < total
              set_message("#{total} matches for '#{query}' (showing first #{result.matches.length})", 2)
            else
              set_message("#{total} match#{'es' unless total == 1} for '#{query}'", 2)
            end
          end

          def activate_search_mode
            @input_controller&.enter_modal_mode(:in_book_search)
          end

          def deactivate_search_mode
            @input_controller&.exit_modal_mode(:in_book_search)
          end
        end
      end
    end
  end
end
