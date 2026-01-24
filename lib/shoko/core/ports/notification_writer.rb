# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for displaying notifications/messages to the user.
      # Adapters implementing this interface handle user-facing messages without
      # coupling adapters to application-layer actions or state management.
      #
      # @example Implementing this port
      #   class NotificationWriterAdapter
      #     include Shoko::Core::Ports::NotificationWriter
      #
      #     def initialize(state)
      #       @state = state
      #     end
      #
      #     def show_message(text)
      #       @state.dispatch(UpdateMessageAction.new(text))
      #     end
      #   end
      module NotificationWriter
        # Display a message to the user
        #
        # @param text [String] Message text to display
        # @return [void]
        def show_message(text)
          raise NotImplementedError, "#{self.class} must implement #show_message"
        end

        # Clear the current message
        #
        # @return [void]
        def clear_message
          raise NotImplementedError, "#{self.class} must implement #clear_message"
        end
      end
    end
  end
end
