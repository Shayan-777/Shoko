# frozen_string_literal: true

require_relative '../../../application/ports/outbound/notification_writer'
require_relative 'actions/update_message_action'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Application adapter implementing the NotificationWriter port.
        # Dispatches UpdateMessageAction to display/clear user messages.
        class NotificationWriterAdapter
          include Application::Ports::Outbound::NotificationWriter

          def initialize(state, text_sanitizer: nil)
            @state = state
            @text_sanitizer = text_sanitizer
          end

          # Display a message to the user
          # @param text [String] Message text to display
          def show_message(text)
            safe = if text && @text_sanitizer
                     @text_sanitizer.sanitize(text.to_s, preserve_newlines: false, max_length: nil)
                   else
                     text
                   end
            @state.dispatch(Actions::UpdateMessageAction.new(safe))
          end

          # Clear the current message
          def clear_message
            @state.dispatch(Actions::UpdateMessageAction.new(nil))
          end
        end
      end
    end
  end
end
