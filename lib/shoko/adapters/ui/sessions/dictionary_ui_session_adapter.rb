# frozen_string_literal: true

require_relative 'support/session_outcome_helpers'
require_relative 'dictionary_ui_session/component_access'
require_relative 'dictionary_ui_session/command_dispatch'
require_relative 'dictionary_ui_session/setup_popup_lifecycle'

module Shoko
  module Adapters
    module Ui
      module Sessions
        # Adapter-owned lifecycle for dictionary panel/popup UI components.
        class DictionaryUiSessionAdapter
          include Support::SessionOutcomeHelpers
          include DictionaryUiSession::ComponentAccess
          include DictionaryUiSession::CommandDispatch
          include DictionaryUiSession::SetupPopupLifecycle

          def initialize(reader_state_reader:, reader_session_mutator:, ui_component_factory:, logger: nil)
            @reader_state_reader = reader_state_reader
            @reader_session_mutator = reader_session_mutator
            @ui_component_factory = ui_component_factory
            @logger = logger
          end

          def show_panel(result)
            panel = current_panel || @ui_component_factory.dictionary_panel(@reader_state_reader)
            show_surface(
              surface: panel,
              hide_surface: current_popup,
              event: 'dictionary.session.show_panel',
              unavailable_code: :dictionary_panel_unavailable,
              failure_code: :dictionary_panel_failed,
              success_code: :dictionary_panel_shown,
              state_updates: result_state_updates(dictionary_panel: panel, dictionary_popup: nil, result: result)
            ) { |component| component.show(result) }
          end

          def show_popup(result)
            popup = current_popup || @ui_component_factory.dictionary_popup(@reader_state_reader)
            show_surface(
              surface: popup,
              hide_surface: current_panel,
              event: 'dictionary.session.show_popup',
              unavailable_code: :dictionary_popup_unavailable,
              failure_code: :dictionary_popup_failed,
              success_code: :dictionary_popup_shown,
              state_updates: result_state_updates(dictionary_panel: nil, dictionary_popup: popup, result: result)
            ) { |component| component.show(result) }
          end

          def close
            panel = current_panel
            popup = current_popup
            panel&.hide
            popup&.hide
            @reader_session_mutator.update_reader(
              dictionary_panel: nil,
              dictionary_popup: nil,
              dictionary_visible: false,
              dictionary_result: nil,
              dictionary_entry_index: 0,
              dictionary_fuzzy_mode: false,
              dictionary_fuzzy_matches: [],
              mode: :read
            )
            success_outcome(:closed, :dictionary_closed)
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error('dictionary.session.close', e)
            failure_outcome(:error, :dictionary_close_failed, e.message)
          end

          def refresh_theme(color_mode:)
            panel = current_panel
            popup = current_popup
            panel&.update_color_mode(color_mode) if panel.respond_to?(:update_color_mode)
            popup&.update_color_mode(color_mode) if popup.respond_to?(:update_color_mode)
            success_outcome(:handled, :dictionary_theme_refreshed)
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error('dictionary.session.refresh_theme', e)
            failure_outcome(:error, :dictionary_theme_refresh_failed, e.message)
          end

          private

          # Lookup display state migrates to the reader view store: the panel/popup
          # components render the result/entry/fuzzy from state. A fresh result
          # resets entry/fuzzy and clears the setup-active flag (lookup, not setup).
          def result_state_updates(dictionary_panel:, dictionary_popup:, result:)
            {
              dictionary_panel: dictionary_panel,
              dictionary_popup: dictionary_popup,
              dictionary_result: result,
              dictionary_entry_index: 0,
              dictionary_fuzzy_mode: false,
              dictionary_fuzzy_matches: [],
            }
          end

          def show_surface(
            surface:,
            hide_surface:,
            event:,
            unavailable_code:,
            failure_code:,
            success_code:,
            state_updates:
          )
            return failure_outcome(:error, unavailable_code, 'Dictionary component unavailable') unless surface

            hide_surface&.hide
            yield surface
            @reader_session_mutator.update_reader(
              **state_updates,
              dictionary_visible: true,
              mode: :dictionary,
              popup_menu: nil
            )
            success_outcome(:shown, success_code)
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error(event, e)
            failure_outcome(:error, failure_code, e.message)
          end
        end
      end
    end
  end
end
