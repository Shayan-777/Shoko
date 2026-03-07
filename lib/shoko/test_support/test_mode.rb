# frozen_string_literal: true

require_relative 'terminal_double'
require_relative '../adapters/output/terminal/terminal_service'

module Shoko
  module TestSupport
    # Central hook that enables deterministic test behaviour by swapping in
    # lightweight adapters and updating the dependency container.
    module TestMode
      module_function

      def active?
        primary = ENV.fetch('SHOKO_TEST_MODE', '').to_s.strip
        primary == '1'
      end

      def activate!
        return unless active?

        install_terminal_double!
      end

      def configure_container(container)
        return unless active?

        container.register_singleton(:terminal_service) do |c|
          TestTerminalService.new(
            runtime_config: c.resolve(:runtime_config),
            logger: c.resolve(:logger)
          )
        end
      end

      # Test-specialised terminal service that exposes helpers for enqueuing
      # deterministic input sequences while delegating behaviour to the base
      # implementation (now backed by the TerminalDouble).
      class TestTerminalService < Shoko::Adapters::Output::Terminal::TerminalService
        def queue_input(*keys)
          Shoko::TestSupport::TerminalDouble.push_input(*keys)
        end

        def drain_input
          Shoko::TestSupport::TerminalDouble.drain_input
        end

        def configure_size(height:, width:)
          Shoko::TestSupport::TerminalDouble.size = [height, width]
        end
      end

      def install_terminal_double!
        return if @terminal_installed

        real_terminal = (Shoko.const_get(:Terminal) if Shoko.const_defined?(:Terminal, false))
        Shoko.const_set(:RealTerminal, real_terminal) unless Shoko.const_defined?(:RealTerminal)
        Shoko.class_eval { remove_const(:Terminal) } if Shoko.const_defined?(:Terminal, false)
        Shoko.const_set(:Terminal, Shoko::TestSupport::TerminalDouble)
        Shoko::TestSupport::TerminalDouble.reset!
        @terminal_installed = true
      end
    end
  end
end
