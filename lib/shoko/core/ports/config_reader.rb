# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for reading application configuration.
      # Adapters implementing this interface provide access to user settings
      # and display configuration without coupling core services to application state.
      #
      # @example Implementing this port
      #   class ConfigReaderAdapter
      #     include Shoko::Core::Ports::ConfigReader
      #
      #     def initialize(state)
      #       @state = state
      #     end
      #
      #     def page_numbering_mode
      #       # Read from state
      #     end
      #   end
      module ConfigReader
        # Get the current page numbering mode
        #
        # @return [Symbol] :dynamic or :absolute
        def page_numbering_mode
          raise NotImplementedError, "#{self.class} must implement #page_numbering_mode"
        end

        # Get the current view mode
        #
        # @return [Symbol] :single or :split
        def view_mode
          raise NotImplementedError, "#{self.class} must implement #view_mode"
        end

        # Get the current line spacing setting
        #
        # @return [Integer] Line spacing value
        def line_spacing
          raise NotImplementedError, "#{self.class} must implement #line_spacing"
        end
      end
    end
  end
end
