# frozen_string_literal: true

require_relative 'support/session_outcome_helpers'

module Shoko
  module Adapters
    module Ui
      module Sessions
        # Adapter-owned lifecycle for dictionary panel/popup UI components.
        class DictionaryUiSessionAdapter
          include Support::SessionOutcomeHelpers

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


          def dispatch_active_component(command, args: [])
            component = active_component
            unless component
              return failure_outcome(
                :ignored,
                unavailable_code_for(command),
                "#{command} unavailable for active dictionary component"
              )
            end

            unless component.respond_to?(command)
              # The active surface can be the read-only result panel (a word lookup) or the editable
              # popup (search/setup). Edit commands — insert_char, backspace, confirm, tab, … — only
              # exist on the popup. When the panel is up (e.g. the user types while reading a result)
              # ignore the command instead of raising NoMethodError; it is not an editable surface.
              return failure_outcome(
                :ignored,
                unavailable_code_for(command),
                "active dictionary component does not support #{command}"
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
