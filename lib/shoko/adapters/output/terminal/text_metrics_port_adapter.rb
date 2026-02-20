# frozen_string_literal: true

require_relative '../../../core/ports/text_metrics'
require_relative 'text_metrics'

module Shoko
  module Adapters
    module Output
      module Terminal
        # Core port adapter that binds runtime-config toggles without global mutation.
        class TextMetricsPortAdapter
          include Shoko::Core::Ports::TextMetrics

          def initialize(runtime_config: nil)
            @runtime_config = runtime_config
          end

          def wrap_plain_text(line, width)
            with_runtime_config do
              TextMetrics.wrap_plain_text(line, width)
            end
          end

          private

          def with_runtime_config
            return yield unless @runtime_config

            TextMetrics.with_runtime_config(config: @runtime_config) { yield }
          end
        end
      end
    end
  end
end
