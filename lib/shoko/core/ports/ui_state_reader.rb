# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for reading UI/display state.
      # Adapters implementing this interface provide access to terminal dimensions
      # without coupling core services to application state schema.
      #
      # @example Implementing this port
      #   class UIStateReaderAdapter
      #     include Shoko::Core::Ports::UIStateReader
      #
      #     def initialize(state)
      #       @state = state
      #     end
      #
      #     def terminal_width
      #       @state.get([:ui, :terminal_width])
      #     end
      #   end
      module UIStateReader
        # Get the terminal width in columns
        #
        # @return [Integer] Terminal width
        def terminal_width
          raise NotImplementedError, "#{self.class} must implement #terminal_width"
        end

        # Get the terminal height in rows
        #
        # @return [Integer] Terminal height
        def terminal_height
          raise NotImplementedError, "#{self.class} must implement #terminal_height"
        end
      end
    end
  end
end
