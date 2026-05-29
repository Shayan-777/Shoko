# frozen_string_literal: true

require_relative '../../../adapters/output/terminal/text_metrics_port_adapter'
require_relative '../../../adapters/output/kitty/display_capabilities'
require_relative '../../../adapters/output/terminal_capabilities_adapter'
require_relative '../../../adapters/output/layout/layout_metrics_adapter'
require_relative '../../../adapters/input/key_classifier_adapter'
require_relative '../../../adapters/output/terminal/text_sanitizer_adapter'
require_relative '../../../adapters/runtime/inline_executor_adapter'

module Shoko
  module Composition
    module ContainerFactory
      # Registers terminal, display, and runtime ports for composition wiring.
      module PortAndRepositoryRegistrationTerminalPorts
        private

        def register_terminal_ports(container)
          register_display_ports(container)
          register_terminal_runtime_ports(container)
          register_input_classification_ports(container)
        end

        def register_display_ports(container)
          container.register_singleton(:text_metrics) do |c|
            Shoko::Adapters::Output::Terminal::TextMetricsPortAdapter.new(runtime_config: c.resolve(:runtime_config))
          end
          container.register_singleton(:display_capabilities) do |_c|
            Shoko::Adapters::Output::Kitty::DisplayCapabilities.new
          end
          container.register_singleton(:instrumentation) { |c| c.resolve(:instrumentation_service) }
        end

        def register_terminal_runtime_ports(container)
          container.register_factory(:async_executor) do |c|
            executor = c.resolve(:background_worker) if c.registered?(:background_worker)
            executor || Shoko::Adapters::Runtime::InlineExecutorAdapter.new
          rescue Shoko::Error
            Shoko::Adapters::Runtime::InlineExecutorAdapter.new
          end
          container.register_singleton(:terminal_capabilities) do |_c|
            Shoko::Adapters::Output::TerminalCapabilitiesAdapter.new
          end
          container.register_singleton(:layout_metrics) do |c|
            Shoko::Adapters::Output::Layout::LayoutMetricsAdapter.new(layout_service: c.resolve(:layout_service))
          end
        end

        def register_input_classification_ports(container)
          container.register_singleton(:key_classifier) do |_c|
            Shoko::Adapters::Input::KeyClassifierAdapter.new
          end
          container.register_singleton(:text_sanitizer) do |_c|
            Shoko::Adapters::Output::Terminal::TextSanitizerAdapter.new
          end
        end
      end
    end
  end
end
