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

        # Get the configured source language for dictionary lookups.
        #
        # @return [String, nil]
        def dictionary_source_lang
          raise NotImplementedError, "#{self.class} must implement #dictionary_source_lang"
        end

        # Get the configured target language for dictionary lookups.
        #
        # @return [String, nil]
        def dictionary_target_lang
          raise NotImplementedError, "#{self.class} must implement #dictionary_target_lang"
        end

        # Get the configured dictionary database path.
        #
        # @return [String, nil]
        def dictionary_path
          raise NotImplementedError, "#{self.class} must implement #dictionary_path"
        end

        # Get the configured dictionary backend identifier.
        #
        # @return [Symbol, nil]
        def dictionary_backend
          raise NotImplementedError, "#{self.class} must implement #dictionary_backend"
        end

        # Get whether page numbers should be displayed
        #
        # @return [Boolean] True if page numbers should be shown
        def show_page_numbers
          raise NotImplementedError, "#{self.class} must implement #show_page_numbers"
        end

        # Get whether Kitty terminal images are enabled
        #
        # @return [Boolean] True if Kitty images are enabled
        def kitty_images
          raise NotImplementedError, "#{self.class} must implement #kitty_images"
        end

        # Get the configured theme
        #
        # @return [Symbol, nil] Theme identifier
        def theme
          raise NotImplementedError, "#{self.class} must implement #theme"
        end
      end
    end
  end
end
