# frozen_string_literal: true

require_relative '../support/session_outcome_helpers'

module Shoko
  module Adapters
    module Ui
      module Sessions
        module DictionaryUiSession
          # Reads the active dictionary components and current visibility state.
          module ComponentAccess
            def visible?
              panel_visible? || popup_visible?
            end

            def panel_visible?
              component_visible?(current_panel)
            end

            def popup_visible?
              component_visible?(current_popup)
            end

            def active_result
              @reader_state_reader.dictionary_result
            end

            def active_kind
              return :panel if panel_visible?
              return :popup if popup_visible?

              nil
            end

            private

            def active_component
              return current_panel if panel_visible?
              return current_popup if popup_visible?

              nil
            end

            def current_panel
              @reader_state_reader.dictionary_panel
            rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
              log_error('dictionary.session.current_panel', e)
              nil
            end

            def current_popup
              @reader_state_reader.dictionary_popup
            rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
              log_error('dictionary.session.current_popup', e)
              nil
            end

            def component_visible?(component)
              component&.visible?
            rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
              log_error('dictionary.session.component_visible?', e)
              false
            end
          end
        end
      end
    end
  end
end
