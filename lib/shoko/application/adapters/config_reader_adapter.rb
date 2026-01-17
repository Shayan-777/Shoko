# frozen_string_literal: true

require_relative '../../core/ports/config_reader'
require_relative '../selectors/config_selectors'

module Shoko
  module Application
    module Adapters
      # Application adapter implementing the ConfigReader port.
      # Reads configuration from application state using ConfigSelectors.
      class ConfigReaderAdapter
        include Core::Ports::ConfigReader

        def initialize(state)
          @state = state
        end

        # @return [Symbol] :dynamic or :absolute
        def page_numbering_mode
          Selectors::ConfigSelectors.page_numbering_mode(@state)
        end

        # @return [Symbol] :single or :split
        def view_mode
          Selectors::ConfigSelectors.view_mode(@state)
        end

        # @return [Integer]
        def line_spacing
          Selectors::ConfigSelectors.line_spacing(@state)
        end
      end
    end
  end
end
