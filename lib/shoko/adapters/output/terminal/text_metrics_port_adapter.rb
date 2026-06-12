# frozen_string_literal: true

require 'shoko/application/ports/outbound/text_metrics'
require 'shoko/application/ports/outbound/runtime_config'
require_relative 'text_metrics'

module Shoko
  module Adapters
    module Output
      module Terminal
        # Core port adapter that binds runtime-config toggles without global mutation.
        class TextMetricsPortAdapter
          include Shoko::Application::Ports::Outbound::TextMetrics

          def initialize(runtime_config:)
            unless runtime_config.is_a?(Shoko::Application::Ports::Outbound::RuntimeConfig)
              raise ArgumentError, 'runtime_config must implement Application::Ports::Outbound::RuntimeConfig'
            end

            @runtime_config = runtime_config
            TextMetrics.configure_runtime_config!(runtime_config: @runtime_config)
          end

          def wrap_plain_text(line, width)
            with_runtime_config do
              TextMetrics.wrap_plain_text(line, width)
            end
          end

          private

          def with_runtime_config(&)
            return yield unless @runtime_config

            TextMetrics.with_runtime_config(config: @runtime_config, &)
          end
        end
      end
    end
  end
end
