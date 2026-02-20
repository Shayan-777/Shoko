# frozen_string_literal: true

require_relative '../../../application/ports/in_book_search_ui_session'
require_relative '../../../application/ui/session_outcome'

module Shoko
  module Presentation
    module Ui
        module Sessions
          # Adapter-owned lifecycle for in-book search popup component.
          class InBookSearchUiSessionAdapter
            include Shoko::Application::Ports::InBookSearchUiSession

            RESCUABLE_ERRORS = [NoMethodError, ArgumentError, TypeError, RuntimeError].freeze

            def initialize(reader_state_reader:, state_writer:, ui_component_factory:, logger: nil)
              @reader_state_reader = reader_state_reader
              @state_writer = state_writer
              @ui_component_factory = ui_component_factory
              @logger = logger
            end

            def open(query: '', results: [], total_matches: 0)
              popup = ensure_popup
              return failure_outcome(:error, :in_book_search_popup_unavailable, 'In-book search popup unavailable') unless popup

              popup.show(query: query, results: results, total_matches: total_matches)
              @state_writer.update_reader(
                in_book_search_popup: popup,
                mode: :in_book_search,
                popup_menu: nil
              )
              success_outcome(:opened, :in_book_search_opened)
            rescue *RESCUABLE_ERRORS => e
              log_error('in_book_search.session.open', e)
              failure_outcome(:error, :in_book_search_open_failed, e.message)
            end

            def close
              current_popup&.hide
              @state_writer.update_reader(
                in_book_search_popup: nil,
                mode: :read
              )
              success_outcome(:closed, :in_book_search_closed)
            rescue *RESCUABLE_ERRORS => e
              log_error('in_book_search.session.close', e)
              failure_outcome(:error, :in_book_search_close_failed, e.message)
            end

            def visible?
              popup = current_popup
              popup.respond_to?(:visible?) && popup.visible?
            rescue *RESCUABLE_ERRORS => e
              log_error('in_book_search.session.visible?', e)
              false
            end

            def insert_char(char)
              invoke_popup_action(
                command: :insert_char,
                method_name: :insert_char,
                args: [char.to_s],
                unavailable_code: :in_book_search_insert_char_unavailable
              )
            end

            def backspace
              invoke_popup_action(
                command: :backspace,
                method_name: :backspace,
                unavailable_code: :in_book_search_backspace_unavailable
              )
            end

            def confirm
              invoke_popup_action(
                command: :confirm,
                method_name: :confirm,
                unavailable_code: :in_book_search_confirm_unavailable
              )
            end

            def cancel
              invoke_popup_action(
                command: :cancel,
                method_name: :cancel,
                unavailable_code: :in_book_search_cancel_unavailable
              )
            end

            def scroll_up
              invoke_scroll_action(:scroll_up, :scroll_up_action)
            end

            def scroll_down
              invoke_scroll_action(:scroll_down, :scroll_down_action)
            end

            def update(query:, results:, total_matches:, results_query:)
              popup = current_popup
              return failure_outcome(:ignored, :in_book_search_update_unavailable, 'In-book search popup unavailable') unless popup&.respond_to?(:update)

              popup.update(
                query: query,
                results: results,
                total_matches: total_matches,
                results_query: results_query
              )
              success_outcome(:handled, :in_book_search_update_handled, payload: true)
            rescue *RESCUABLE_ERRORS => e
              log_error('in_book_search.session.update', e)
              failure_outcome(:error, :in_book_search_update_failed, e.message)
            end

            private

            def invoke_popup_action(command:, method_name:, args: [], unavailable_code:)
              popup = current_popup
              return failure_outcome(:ignored, unavailable_code, "#{method_name} unavailable for in-book search popup") unless popup&.respond_to?(method_name)

              payload = popup.public_send(method_name, *args)
              success_outcome(:handled, "in_book_search_#{command}_handled".to_sym, payload: payload)
            rescue *RESCUABLE_ERRORS => e
              log_error("in_book_search.session.#{command}", e)
              failure_outcome(:error, "in_book_search_#{command}_failed".to_sym, e.message)
            end

            def invoke_scroll_action(command, method_name)
              popup = current_popup
              return failure_outcome(:ignored, "in_book_search_#{command}_unavailable".to_sym, 'In-book search popup unavailable', payload: false) unless popup

              payload = popup.respond_to?(method_name) ? popup.public_send(method_name) : nil
              if payload
                success_outcome(:handled, "in_book_search_#{command}_handled".to_sym, payload: payload)
              else
                failure_outcome(:ignored, "in_book_search_#{command}_ignored".to_sym, 'In-book search scroll event was not handled', payload: false)
              end
            rescue *RESCUABLE_ERRORS => e
              log_error("in_book_search.session.#{command}", e)
              failure_outcome(:error, "in_book_search_#{command}_failed".to_sym, e.message)
            end

            def ensure_popup
              current_popup || @ui_component_factory&.in_book_search_popup
            rescue *RESCUABLE_ERRORS => e
              log_error('in_book_search.session.ensure_popup', e)
              nil
            end

            def current_popup
              @reader_state_reader&.in_book_search_popup
            rescue *RESCUABLE_ERRORS => e
              log_error('in_book_search.session.current_popup', e)
              nil
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
