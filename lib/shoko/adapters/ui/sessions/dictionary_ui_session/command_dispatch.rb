# frozen_string_literal: true

require_relative '../support/session_outcome_helpers'

module Shoko
  module Adapters
    module Ui
      module Sessions
        module DictionaryUiSession
          # Routes dictionary popup/panel input commands through a small command map.
          module CommandDispatch
            COMPONENT_COMMANDS = {
              insert_char: ->(component, value) { component.insert_char(value) },
              backspace: ->(component, *) { component.backspace },
              confirm: ->(component, *) { component.confirm },
              cancel: ->(component, *) { component.cancel },
              tab: ->(component, *) { component.tab },
              swap_languages: ->(component, *) { component.swap_languages },
              toggle_fuzzy: ->(component, value = nil) { component.toggle_fuzzy(value) },
              next_entry: ->(component, *) { component.next_entry },
            }.freeze

            SCROLL_COMMANDS = { scroll_up: :scroll_up_action.to_proc, scroll_down: :scroll_down_action.to_proc }.freeze

            def insert_char(char)
              dispatch_active_component(:insert_char, args: [char.to_s])
            end

            def backspace
              dispatch_active_component(:backspace)
            end

            def confirm
              dispatch_active_component(:confirm)
            end

            def cancel
              dispatch_active_component(:cancel)
            end

            def tab
              dispatch_active_component(:tab)
            end

            def swap_languages
              dispatch_active_component(:swap_languages)
            end

            def scroll_up
              dispatch_scroll(:scroll_up)
            end

            def scroll_down
              dispatch_scroll(:scroll_down)
            end

            def setup_mode?
              popup = current_popup
              popup&.visible? && popup.setup_mode?
            rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
              log_error('dictionary.session.setup_mode?', e)
              false
            end

            def fuzzy_mode?
              component = active_component
              component&.fuzzy_mode?
            rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
              log_error('dictionary.session.fuzzy_mode?', e)
              false
            end

            def toggle_fuzzy(matches = nil)
              dispatch_active_component(:toggle_fuzzy, args: [matches])
            end

            def next_entry
              dispatch_active_component(:next_entry)
            end

            private

            def dispatch_active_component(command, args: [])
              component = active_component
              unless component
                return failure_outcome(
                  :ignored,
                  unavailable_code_for(command),
                  "#{command} unavailable for active dictionary component"
                )
              end

              payload = COMPONENT_COMMANDS.fetch(command).call(component, *args)
              success_outcome(:handled, handled_code_for(command), payload: payload)
            rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
              log_error("dictionary.session.#{command}", e)
              failure_outcome(:error, failed_code_for(command), e.message)
            end

            def dispatch_scroll(command)
              component = active_component
              unless component
                return failure_outcome(:ignored, unavailable_code_for(command), 'No active dictionary component')
              end

              handled = SCROLL_COMMANDS.fetch(command).call(component) ? true : false
              return success_outcome(:handled, handled_code_for(command), payload: true) if handled

              failure_outcome(
                :ignored,
                ignored_code_for(command),
                'Dictionary scroll event was not handled',
                payload: false
              )
            rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
              log_error("dictionary.session.#{command}", e)
              failure_outcome(:error, failed_code_for(command), e.message)
            end

            def unavailable_code_for(command)
              :"dictionary_#{command}_unavailable"
            end

            def handled_code_for(command)
              :"dictionary_#{command}_handled"
            end

            def failed_code_for(command)
              :"dictionary_#{command}_failed"
            end

            def ignored_code_for(command)
              :"dictionary_#{command}_ignored"
            end
          end
        end
      end
    end
  end
end
