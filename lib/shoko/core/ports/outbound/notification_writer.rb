# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Application-facing contract for writing user-facing notifications.
      module NotificationWriter
        def show_message(text)
          raise NotImplementedError, "#{self.class} must implement #show_message"
        end

        def clear_message
          raise NotImplementedError, "#{self.class} must implement #clear_message"
        end
      end
    end
  end
end
