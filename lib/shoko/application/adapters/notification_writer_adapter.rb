# frozen_string_literal: true

require_relative '../../core/ports/notification_writer'
require_relative '../state/actions/update_message_action'

module Shoko
  module Application
    module Adapters
      # Application adapter implementing the NotificationWriter port.
      # Dispatches UpdateMessageAction to display/clear user messages.
      class NotificationWriterAdapter
        include Core::Ports::NotificationWriter

        def initialize(state)
          @state = state
        end

        # Display a message to the user
        # @param text [String] Message text to display
        def show_message(text)
          @state.dispatch(Actions::UpdateMessageAction.new(text))
        end

        # Clear the current message
        def clear_message
          @state.dispatch(Actions::UpdateMessageAction.new(nil))
        end
      end
    end
  end
end
