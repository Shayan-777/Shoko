# frozen_string_literal: true

require_relative 'support/session_outcome_helpers'

module Shoko
  module Adapters
    module Ui
      module Sessions
        # Adapter-owned lifecycle for the reader dictionary surfaces:
        #   * the left "Definition card" (`dictionary_lookup_popup`) — the result
        #     surface, a pure renderer fed from reader view-state; and
        #   * the centered first-run install wizard (`dictionary_popup`) — the only
        #     editable dictionary surface, driven through the setup-dispatch methods.
        #
        # The lookup query and selection live in the reader view-state store and are
        # written by the dictionary use case (the card re-renders from them). This
        # session owns the component instances, the dictionary mode flag, and the
        # result/fuzzy writes. Mirrors InBookSearchUiSessionAdapter.
        class DictionaryUiSessionAdapter
          include Support::SessionOutcomeHelpers

          RESCUABLE = Support::SessionOutcomeHelpers::RESCUABLE_ERRORS

          # Reset to a clean slate whenever the bar opens or closes.
          BLANK_LOOKUP_STATE = {
            dictionary_query: '',
            dictionary_results_query: '',
            dictionary_result: nil,
            dictionary_entry_index: 0,
            dictionary_selected_index: 0,
            dictionary_fuzzy_mode: false,
            dictionary_fuzzy_matches: [],
            dictionary_setup_active: false,
          }.freeze

          def initialize(reader_state_reader:, reader_session_mutator:, ui_component_factory:, logger: nil)
            @reader_state_reader = reader_state_reader
            @reader_session_mutator = reader_session_mutator
            @ui_component_factory = ui_component_factory
            @logger = logger
          end

          # ----- definition-card lifecycle -----

          def open
            popup = ensure_lookup_popup
            return failure_outcome(:error, :dictionary_lookup_unavailable, 'Dictionary popup unavailable') unless popup

            @reader_session_mutator.update_reader(
              dictionary_lookup_popup: popup,
              dictionary_popup: nil,
              dictionary_visible: true,
              mode: :dictionary,
              popup_menu: nil,
              **BLANK_LOOKUP_STATE
            )
            success_outcome(:opened, :dictionary_opened)
          rescue *RESCUABLE => e
            log_error('dictionary.session.open', e)
            failure_outcome(:error, :dictionary_open_failed, e.message)
          end

          def apply_result(result)
            current_setup_popup&.hide
            @reader_session_mutator.update_reader(
              dictionary_result: result,
              dictionary_results_query: result.query.to_s,
              dictionary_entry_index: 0,
              dictionary_selected_index: 0,
              dictionary_fuzzy_mode: false,
              dictionary_fuzzy_matches: [],
              dictionary_setup_active: false,
              dictionary_popup: nil,
              dictionary_visible: true,
              mode: :dictionary
            )
            success_outcome(:handled, :dictionary_result_applied)
          rescue *RESCUABLE => e
            log_error('dictionary.session.apply_result', e)
            failure_outcome(:error, :dictionary_apply_result_failed, e.message)
          end

          def apply_fuzzy(matches)
            @reader_session_mutator.update_reader(
              dictionary_fuzzy_mode: true,
              dictionary_fuzzy_matches: Array(matches),
              dictionary_selected_index: 0
            )
            success_outcome(:handled, :dictionary_fuzzy_applied)
          rescue *RESCUABLE => e
            log_error('dictionary.session.apply_fuzzy', e)
            failure_outcome(:error, :dictionary_fuzzy_failed, e.message)
          end

          def clear_fuzzy
            @reader_session_mutator.update_reader(
              dictionary_fuzzy_mode: false,
              dictionary_fuzzy_matches: [],
              dictionary_selected_index: 0
            )
            success_outcome(:handled, :dictionary_fuzzy_cleared)
          rescue *RESCUABLE => e
            log_error('dictionary.session.clear_fuzzy', e)
            failure_outcome(:error, :dictionary_fuzzy_clear_failed, e.message)
          end

          def close
            current_setup_popup&.hide
            @reader_session_mutator.update_reader(
              dictionary_lookup_popup: nil,
              dictionary_popup: nil,
              dictionary_visible: false,
              mode: :read,
              **BLANK_LOOKUP_STATE
            )
            success_outcome(:closed, :dictionary_closed)
          rescue *RESCUABLE => e
            log_error('dictionary.session.close', e)
            failure_outcome(:error, :dictionary_close_failed, e.message)
          end

          def visible?
            @reader_state_reader.mode == :dictionary
          rescue *RESCUABLE => e
            log_error('dictionary.session.visible?', e)
            false
          end

          def active_result
            @reader_state_reader.dictionary_result
          rescue *RESCUABLE => e
            log_error('dictionary.session.active_result', e)
            nil
          end

          def refresh_theme(color_mode:)
            [current_lookup_popup, current_setup_popup].compact.each do |popup|
              popup.update_color_mode(color_mode) if popup.respond_to?(:update_color_mode)
            end
            success_outcome(:handled, :dictionary_theme_refreshed)
          rescue *RESCUABLE => e
            log_error('dictionary.session.refresh_theme', e)
            failure_outcome(:error, :dictionary_theme_refresh_failed, e.message)
          end

          # ----- first-run install wizard -----

          def prepare_setup_popup
            unless ensure_setup_popup
              return failure_outcome(:error, :dictionary_setup_popup_unavailable,
                                     'Dictionary setup popup unavailable')
            end

            success_outcome(:ready, :dictionary_setup_popup_ready)
          rescue *RESCUABLE => e
            log_error('dictionary.session.prepare_setup_popup', e)
            failure_outcome(:error, :dictionary_setup_popup_failed, e.message)
          end

          def show_setup(**)
            with_setup_popup(:dictionary_show_setup_handled) { |popup| popup.show_setup(**) }
          end

          def update_setup(**)
            with_setup_popup(:dictionary_update_setup_handled) { |popup| popup.update_setup(**) }
          end

          def setup_mode?
            popup = current_setup_popup
            popup&.visible? == true && popup.setup_mode?
          rescue *RESCUABLE => e
            log_error('dictionary.session.setup_mode?', e)
            false
          end

          def insert_char(char) = dispatch_setup(:insert_char, char.to_s)
          def backspace = dispatch_setup(:backspace)
          def confirm = dispatch_setup(:confirm)
          def tab = dispatch_setup(:tab)
          def swap_languages = dispatch_setup(:swap_languages)
          def scroll_up = dispatch_setup(:scroll_up_action)
          def scroll_down = dispatch_setup(:scroll_down_action)

          private

          def ensure_lookup_popup
            current_lookup_popup ||
              @ui_component_factory.dictionary_lookup_popup(reader_state_reader: @reader_state_reader)
          rescue *RESCUABLE => e
            log_error('dictionary.session.ensure_lookup_popup', e)
            nil
          end

          def ensure_setup_popup
            popup = current_setup_popup || @ui_component_factory.dictionary_popup(@reader_state_reader)
            return nil unless popup

            @reader_session_mutator.update_reader(
              dictionary_popup: popup,
              dictionary_visible: true,
              dictionary_setup_active: true,
              mode: :dictionary,
              popup_menu: nil
            )
            popup
          rescue *RESCUABLE => e
            log_error('dictionary.session.ensure_setup_popup', e)
            nil
          end

          def with_setup_popup(success_code)
            popup = ensure_setup_popup
            unless popup
              return failure_outcome(:error, :dictionary_setup_popup_unavailable,
                                     'Dictionary setup popup unavailable')
            end

            yield popup
            success_outcome(:handled, success_code)
          rescue *RESCUABLE => e
            log_error('dictionary.session.setup', e)
            failure_outcome(:error, :dictionary_setup_failed, e.message)
          end

          # Run a setup-popup command and carry its returned event as the outcome
          # payload so the controller can process it (handle_setup_change, etc.).
          def dispatch_setup(command, *)
            popup = current_setup_popup
            unless popup&.visible? && popup.respond_to?(command)
              return failure_outcome(:ignored, :dictionary_setup_unavailable, "setup #{command} unavailable")
            end

            payload = popup.public_send(command, *)
            success_outcome(:handled, :dictionary_setup_command, payload: payload)
          rescue *RESCUABLE => e
            log_error("dictionary.session.#{command}", e)
            failure_outcome(:error, :dictionary_setup_command_failed, e.message)
          end

          def current_lookup_popup
            @reader_state_reader.dictionary_lookup_popup
          rescue *RESCUABLE => e
            log_error('dictionary.session.current_lookup_popup', e)
            nil
          end

          def current_setup_popup
            @reader_state_reader.dictionary_popup
          rescue *RESCUABLE => e
            log_error('dictionary.session.current_setup_popup', e)
            nil
          end
        end
      end
    end
  end
end
