# frozen_string_literal: true

require_relative '../../../../application/ports/dictionary_ui_session'
require_relative '../../../../application/ui/session_outcome'

module Shoko
  module Adapters
    module Output
      module Ui
        module Sessions
          # Adapter-owned lifecycle for dictionary panel/popup UI components.
          class DictionaryUiSessionAdapter
            include Shoko::Application::Ports::DictionaryUiSession

            RESCUABLE_ERRORS = [NoMethodError, ArgumentError, TypeError, RuntimeError].freeze

            def initialize(reader_state_reader:, state_writer:, ui_component_factory:, logger: nil)
              @reader_state_reader = reader_state_reader
              @state_writer = state_writer
              @ui_component_factory = ui_component_factory
              @logger = logger
            end

            def show_panel(result)
              panel = current_panel || @ui_component_factory&.dictionary_panel(@reader_state_reader)
              return failure_outcome(:show_panel, :dictionary_panel_unavailable, 'Dictionary panel component unavailable') unless panel

              current_popup&.hide
              panel.show(result)
              @state_writer.update_reader(
                dictionary_panel: panel,
                dictionary_popup: nil,
                dictionary_visible: true,
                mode: :dictionary,
                popup_menu: nil
              )
              success_outcome(:shown, :dictionary_panel_shown)
            rescue *RESCUABLE_ERRORS => e
              log_error('dictionary.session.show_panel', e)
              failure_outcome(:error, :dictionary_panel_failed, e.message)
            end

            def show_popup(result)
              popup = current_popup || @ui_component_factory&.dictionary_popup
              return failure_outcome(:show_popup, :dictionary_popup_unavailable, 'Dictionary popup component unavailable') unless popup

              current_panel&.hide
              popup.show(result)
              @state_writer.update_reader(
                dictionary_panel: nil,
                dictionary_popup: popup,
                dictionary_visible: true,
                mode: :dictionary,
                popup_menu: nil
              )
              success_outcome(:shown, :dictionary_popup_shown)
            rescue *RESCUABLE_ERRORS => e
              log_error('dictionary.session.show_popup', e)
              failure_outcome(:error, :dictionary_popup_failed, e.message)
            end

            def close
              current_panel&.hide
              current_popup&.hide
              @state_writer.update_reader(
                dictionary_panel: nil,
                dictionary_popup: nil,
                dictionary_visible: false,
                mode: :read
              )
              success_outcome(:closed, :dictionary_closed)
            rescue *RESCUABLE_ERRORS => e
              log_error('dictionary.session.close', e)
              failure_outcome(:error, :dictionary_close_failed, e.message)
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
              return current_panel.result if panel_visible? && current_panel.respond_to?(:result)
              return current_popup.result if popup_visible? && current_popup.respond_to?(:result)

              nil
            rescue *RESCUABLE_ERRORS => e
              log_error('dictionary.session.active_result', e)
              nil
            end

            def active_kind
              return :panel if panel_visible?
              return :popup if popup_visible?

              nil
            end

            def insert_char(char)
              invoke_active_component(
                command: :insert_char,
                method_name: :insert_char,
                args: [char.to_s],
                unavailable_code: :dictionary_insert_char_unavailable
              )
            end

            def backspace
              invoke_active_component(
                command: :backspace,
                method_name: :backspace,
                unavailable_code: :dictionary_backspace_unavailable
              )
            end

            def confirm
              invoke_active_component(
                command: :confirm,
                method_name: :confirm,
                unavailable_code: :dictionary_confirm_unavailable
              )
            end

            def cancel
              invoke_active_component(
                command: :cancel,
                method_name: :cancel,
                unavailable_code: :dictionary_cancel_unavailable
              )
            end

            def tab
              invoke_active_component(
                command: :tab,
                method_name: :tab,
                unavailable_code: :dictionary_tab_unavailable
              )
            end

            def swap_languages
              invoke_active_component(
                command: :swap_languages,
                method_name: :swap_languages,
                unavailable_code: :dictionary_swap_languages_unavailable
              )
            end

            def scroll_up
              invoke_scroll(command: :scroll_up, action_method: :scroll_up_action, fallback_method: :scroll_up)
            end

            def scroll_down
              invoke_scroll(command: :scroll_down, action_method: :scroll_down_action, fallback_method: :scroll_down)
            end

            def setup_mode?
              popup = current_popup
              popup_visible? && popup.respond_to?(:setup_mode?) && popup.setup_mode?
            rescue *RESCUABLE_ERRORS => e
              log_error('dictionary.session.setup_mode?', e)
              false
            end

            def fuzzy_mode?
              component = active_component
              component.respond_to?(:fuzzy_mode?) && component.fuzzy_mode?
            rescue *RESCUABLE_ERRORS => e
              log_error('dictionary.session.fuzzy_mode?', e)
              false
            end

            def toggle_fuzzy(matches = nil)
              invoke_active_component(
                command: :toggle_fuzzy,
                method_name: :toggle_fuzzy,
                args: [matches],
                unavailable_code: :dictionary_toggle_fuzzy_unavailable
              )
            end

            def next_entry
              invoke_active_component(
                command: :next_entry,
                method_name: :next_entry,
                unavailable_code: :dictionary_next_entry_unavailable
              )
            end

            def prepare_setup_popup
              popup = ensure_setup_popup
              return failure_outcome(:error, :dictionary_setup_popup_unavailable, 'Dictionary setup popup unavailable') unless popup

              success_outcome(:ready, :dictionary_setup_popup_ready)
            rescue *RESCUABLE_ERRORS => e
              log_error('dictionary.session.prepare_setup_popup', e)
              failure_outcome(:error, :dictionary_setup_popup_failed, e.message)
            end

            def show_setup(**kwargs)
              popup = ensure_setup_popup
              return failure_outcome(:error, :dictionary_show_setup_unavailable, 'Dictionary setup popup unavailable') unless popup&.respond_to?(:show_setup)

              popup.show_setup(**kwargs)
              success_outcome(:handled, :dictionary_show_setup_handled)
            rescue *RESCUABLE_ERRORS => e
              log_error('dictionary.session.show_setup', e)
              failure_outcome(:error, :dictionary_show_setup_failed, e.message)
            end

            def update_setup(**kwargs)
              popup = ensure_setup_popup
              return failure_outcome(:error, :dictionary_update_setup_unavailable, 'Dictionary setup popup unavailable') unless popup&.respond_to?(:update_setup)

              popup.update_setup(**kwargs)
              success_outcome(:handled, :dictionary_update_setup_handled)
            rescue *RESCUABLE_ERRORS => e
              log_error('dictionary.session.update_setup', e)
              failure_outcome(:error, :dictionary_update_setup_failed, e.message)
            end

            private

            def ensure_setup_popup
              popup = current_popup || @ui_component_factory&.dictionary_popup
              return nil unless popup

              current_panel&.hide
              @state_writer.update_reader(
                dictionary_panel: nil,
                dictionary_popup: popup,
                dictionary_visible: true,
                mode: :dictionary,
                popup_menu: nil
              )
              popup
            rescue *RESCUABLE_ERRORS => e
              log_error('dictionary.session.ensure_setup_popup', e)
              nil
            end

            def invoke_active_component(command:, method_name:, args: [], unavailable_code:)
              component = active_component
              unless component&.respond_to?(method_name)
                return failure_outcome(:ignored, unavailable_code, "#{method_name} unavailable for active dictionary component")
              end

              payload = component.public_send(method_name, *args)
              success_outcome(:handled, "dictionary_#{command}_handled".to_sym, payload: payload)
            rescue *RESCUABLE_ERRORS => e
              log_error("dictionary.session.#{command}", e)
              failure_outcome(:error, "dictionary_#{command}_failed".to_sym, e.message)
            end

            def invoke_scroll(command:, action_method:, fallback_method:)
              component = active_component
              return failure_outcome(:ignored, "dictionary_#{command}_unavailable".to_sym, 'No active dictionary component') unless component

              handled = if component.respond_to?(action_method)
                          !!component.public_send(action_method)
                        elsif component.respond_to?(fallback_method)
                          !!component.public_send(fallback_method) || true
                        else
                          false
                        end

              if handled
                success_outcome(:handled, "dictionary_#{command}_handled".to_sym, payload: true)
              else
                failure_outcome(:ignored, "dictionary_#{command}_ignored".to_sym, 'Dictionary scroll event was not handled', payload: false)
              end
            rescue *RESCUABLE_ERRORS => e
              log_error("dictionary.session.#{command}", e)
              failure_outcome(:error, "dictionary_#{command}_failed".to_sym, e.message)
            end

            def active_component
              return current_panel if panel_visible?
              return current_popup if popup_visible?

              nil
            end

            def current_panel
              @reader_state_reader&.dictionary_panel
            rescue *RESCUABLE_ERRORS => e
              log_error('dictionary.session.current_panel', e)
              nil
            end

            def current_popup
              @reader_state_reader&.dictionary_popup
            rescue *RESCUABLE_ERRORS => e
              log_error('dictionary.session.current_popup', e)
              nil
            end

            def component_visible?(component)
              component.respond_to?(:visible?) && component.visible?
            rescue *RESCUABLE_ERRORS => e
              log_error('dictionary.session.component_visible?', e)
              false
            end

            def success_outcome(status, code, payload: nil)
              Shoko::Application::Ui::SessionOutcome.success(status: status, code: code, payload: payload)
            end

            def failure_outcome(status, code, message, payload: nil)
              Shoko::Application::Ui::SessionOutcome.failure(
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
end
