# frozen_string_literal: true

require 'shoko/shared/contracts/session_outcome'

module Shoko
  module Adapters
    module Ui
      module Sessions
        # Adapter-owned lifecycle for the Table-of-Contents panel component. The
        # panel renders from the reader view-state store; this session owns the
        # component instance (create/teardown via the factory), the TOC-mode flag,
        # and the writes that publish the visible entry rows + selection to state.
        #
        # Mirrors InBookSearchUiSessionAdapter: a pure renderer fed from state, with
        # the document/tree logic living in the controller that drives this session.
        class TocUiSessionAdapter
          RESCUABLE_ERRORS = [ArgumentError, TypeError, RuntimeError].freeze

          BLANK_TOC_STATE = {
            toc_query: '',
            toc_selected_index: 0,
            toc_visible_entries: [],
          }.freeze

          def initialize(reader_state_reader:, reader_session_mutator:, ui_component_factory:, logger: nil)
            @reader_state_reader = reader_state_reader
            @reader_session_mutator = reader_session_mutator
            @ui_component_factory = ui_component_factory
            @logger = logger
          end

          def open
            popup = ensure_popup
            return failure_outcome(:error, :toc_popup_unavailable, 'TOC popup unavailable') unless popup

            @reader_session_mutator.update_reader(
              toc_lookup_popup: popup, mode: :toc, popup_menu: nil, **BLANK_TOC_STATE
            )
            success_outcome(:opened, :toc_opened)
          rescue *RESCUABLE_ERRORS => e
            log_error('toc.session.open', e)
            failure_outcome(:error, :toc_open_failed, e.message)
          end

          def close
            @reader_session_mutator.update_reader(toc_lookup_popup: nil, mode: :read, **BLANK_TOC_STATE)
            success_outcome(:closed, :toc_closed)
          rescue *RESCUABLE_ERRORS => e
            log_error('toc.session.close', e)
            failure_outcome(:error, :toc_close_failed, e.message)
          end

          # Publish the rows the panel should render along with the live filter
          # query and selected position.
          def apply_view(query:, entries:, selected_index:)
            @reader_session_mutator.update_reader(
              toc_query: query.to_s,
              toc_visible_entries: Array(entries),
              toc_selected_index: selected_index.to_i
            )
            success_outcome(:handled, :toc_view_applied)
          rescue *RESCUABLE_ERRORS => e
            log_error('toc.session.apply_view', e)
            failure_outcome(:error, :toc_apply_view_failed, e.message)
          end

          def apply_selection(selected_index)
            @reader_session_mutator.update_reader(toc_selected_index: selected_index.to_i)
            success_outcome(:handled, :toc_selection_applied)
          rescue *RESCUABLE_ERRORS => e
            log_error('toc.session.apply_selection', e)
            failure_outcome(:error, :toc_apply_selection_failed, e.message)
          end

          def visible?
            @reader_state_reader.mode == :toc
          rescue *RESCUABLE_ERRORS => e
            log_error('toc.session.visible?', e)
            false
          end

          def refresh_theme(color_mode:)
            popup = current_popup
            popup&.update_color_mode(color_mode) if popup.respond_to?(:update_color_mode)
            success_outcome(:handled, :toc_theme_refreshed)
          rescue *RESCUABLE_ERRORS => e
            log_error('toc.session.refresh_theme', e)
            failure_outcome(:error, :toc_theme_refresh_failed, e.message)
          end

          private

          def ensure_popup
            current_popup || @ui_component_factory.toc_lookup_popup(reader_state_reader: @reader_state_reader)
          rescue *RESCUABLE_ERRORS => e
            log_error('toc.session.ensure_popup', e)
            nil
          end

          def current_popup
            @reader_state_reader.toc_lookup_popup
          rescue *RESCUABLE_ERRORS => e
            log_error('toc.session.current_popup', e)
            nil
          end

          def success_outcome(status, code, payload: nil)
            Shoko::Shared::Contracts::SessionOutcome.success(status: status, code: code, payload: payload)
          end

          def failure_outcome(status, code, message, payload: nil)
            Shoko::Shared::Contracts::SessionOutcome.failure(status: status, code: code, message: message,
                                                             payload: payload)
          end

          def log_error(event, error)
            @logger&.error(event, error: error.class.name, message: error.message)
          end
        end
      end
    end
  end
end
