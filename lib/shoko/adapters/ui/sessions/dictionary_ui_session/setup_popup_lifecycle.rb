# frozen_string_literal: true

require_relative '../support/session_outcome_helpers'

module Shoko
  module Adapters
    module Ui
      module Sessions
        module DictionaryUiSession
          # Owns setup popup preparation and mutation for the dictionary flow.
          module SetupPopupLifecycle
            def prepare_setup_popup
              popup = ensure_setup_popup
              return setup_popup_unavailable unless popup

              success_outcome(:ready, :dictionary_setup_popup_ready)
            rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
              log_error('dictionary.session.prepare_setup_popup', e)
              failure_outcome(:error, :dictionary_setup_popup_failed, e.message)
            end

            def show_setup(**)
              with_setup_popup(
                event: 'dictionary.session.show_setup',
                unavailable_code: :dictionary_show_setup_unavailable,
                failure_code: :dictionary_show_setup_failed,
                success_code: :dictionary_show_setup_handled
              ) { |popup| popup.show_setup(**) }
            end

            def update_setup(**)
              with_setup_popup(
                event: 'dictionary.session.update_setup',
                unavailable_code: :dictionary_update_setup_unavailable,
                failure_code: :dictionary_update_setup_failed,
                success_code: :dictionary_update_setup_handled
              ) { |popup| popup.update_setup(**) }
            end

            private

            def setup_popup_unavailable
              failure_outcome(:error, :dictionary_setup_popup_unavailable, 'Dictionary setup popup unavailable')
            end

            def ensure_setup_popup
              popup = current_popup || @ui_component_factory.dictionary_popup(@reader_state_reader)
              return nil unless popup

              current_panel&.hide
              @reader_session_mutator.update_reader(
                dictionary_panel: nil,
                dictionary_popup: popup,
                dictionary_visible: true,
                mode: :dictionary,
                popup_menu: nil
              )
              popup
            rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
              log_error('dictionary.session.ensure_setup_popup', e)
              nil
            end

            def with_setup_popup(event:, unavailable_code:, failure_code:, success_code:)
              popup = ensure_setup_popup
              return failure_outcome(:error, unavailable_code, 'Dictionary setup popup unavailable') unless popup

              yield popup
              success_outcome(:handled, success_code)
            rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
              log_error(event, e)
              failure_outcome(:error, failure_code, e.message)
            end
          end
        end
      end
    end
  end
end
