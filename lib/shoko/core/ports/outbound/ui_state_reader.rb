# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Application-facing contract for reading UI state.
      module UiStateReader
        def terminal_width
          raise NotImplementedError, "#{self.class} must implement #terminal_width"
        end

        def terminal_height
          raise NotImplementedError, "#{self.class} must implement #terminal_height"
        end

        def loading_message
          raise NotImplementedError, "#{self.class} must implement #loading_message"
        end

        def loading_progress
          raise NotImplementedError, "#{self.class} must implement #loading_progress"
        end

        def terminal_size_changed?(width, height)
          raise NotImplementedError, "#{self.class} must implement #terminal_size_changed?"
        end
      end
    end
  end
end
