# frozen_string_literal: true

require 'shoko/shared/contracts/session_outcome'

module Shoko
  module Adapters
    module Ui
      module Sessions
        # Adapter-owned lifecycle for the in-book search popup component. The
        # popup renders from the reader view-state store; this session owns the
        # component instance (create/teardown via the registry), the search-mode
        # flag, and the writes that publish search results to state.
        class InBookSearchUiSessionAdapter
          RESCUABLE_ERRORS = [ArgumentError, TypeError, RuntimeError].freeze

          BLANK_SEARCH_STATE = {
            search_query: '',
            search_results: [],
            search_results_query: '',
            search_selected_index: 0,
            search_total_matches: 0,
          }.freeze

          def initialize(
            reader_state_reader:,
            reader_session_mutator:,
            ui_component_factory:,
            rendered_content_reader: nil,
            logger: nil
          )
            @reader_state_reader = reader_state_reader
            @reader_session_mutator = reader_session_mutator
            @ui_component_factory = ui_component_factory
            @rendered_content_reader = rendered_content_reader
            @logger = logger
          end

          def open
            popup = ensure_popup
            unless popup
              return failure_outcome(:error, :in_book_search_popup_unavailable, 'In-book search popup unavailable')
            end

            popup.update_rendered_lines(current_rendered_lines) if popup.respond_to?(:update_rendered_lines)
            @reader_session_mutator.update_reader(
              in_book_search_popup: popup, mode: :in_book_search, popup_menu: nil, **BLANK_SEARCH_STATE
            )
            success_outcome(:opened, :in_book_search_opened)
          rescue *RESCUABLE_ERRORS => e
            log_error('in_book_search.session.open', e)
            failure_outcome(:error, :in_book_search_open_failed, e.message)
          end

          def close
            @reader_session_mutator.update_reader(in_book_search_popup: nil, mode: :read, **BLANK_SEARCH_STATE)
            success_outcome(:closed, :in_book_search_closed)
          rescue *RESCUABLE_ERRORS => e
            log_error('in_book_search.session.close', e)
            failure_outcome(:error, :in_book_search_close_failed, e.message)
          end

          def apply_results(query:, results:, total_matches:)
            @reader_session_mutator.update_reader(
              search_query: query.to_s,
              search_results: Array(results),
              search_results_query: query.to_s,
              search_total_matches: total_matches.to_i
            )
            success_outcome(:handled, :in_book_search_results_applied)
          rescue *RESCUABLE_ERRORS => e
            log_error('in_book_search.session.apply_results', e)
            failure_outcome(:error, :in_book_search_apply_results_failed, e.message)
          end

          def visible?
            @reader_state_reader.mode == :in_book_search
          rescue *RESCUABLE_ERRORS => e
            log_error('in_book_search.session.visible?', e)
            false
          end

          def refresh_theme(color_mode:)
            popup = current_popup
            popup&.update_color_mode(color_mode) if popup.respond_to?(:update_color_mode)
            success_outcome(:handled, :in_book_search_theme_refreshed)
          rescue *RESCUABLE_ERRORS => e
            log_error('in_book_search.session.refresh_theme', e)
            failure_outcome(:error, :in_book_search_theme_refresh_failed, e.message)
          end

          private

          def ensure_popup
            current_popup || @ui_component_factory.in_book_search_popup(
              reader_state_reader: @reader_state_reader,
              rendered_lines: current_rendered_lines
            )
          rescue *RESCUABLE_ERRORS => e
            log_error('in_book_search.session.ensure_popup', e)
            nil
          end

          def current_rendered_lines
            lines = @rendered_content_reader&.rendered_lines
            lines.is_a?(Hash) ? lines : {}
          rescue *RESCUABLE_ERRORS => e
            log_error('in_book_search.session.current_rendered_lines', e)
            {}
          end

          def current_popup
            @reader_state_reader.in_book_search_popup
          rescue *RESCUABLE_ERRORS => e
            log_error('in_book_search.session.current_popup', e)
            nil
          end

          def success_outcome(status, code, payload: nil)
            Shoko::Shared::Contracts::SessionOutcome.success(status: status, code: code, payload: payload)
          end

          def failure_outcome(status, code, message, payload: nil)
            Shoko::Shared::Contracts::SessionOutcome.failure(
              status: status,
              code: code,
              message: message,
              payload: payload
            )
          end

          def log_error(event, error)
            @logger&.error(event, error: error.class.name, message: error.message)
          end
        end
      end
    end
  end
end
