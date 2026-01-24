# frozen_string_literal: true

require_relative '../ports/instrumentation'

module Shoko
  module Core
    module Services
      # No-op instrumentation for environments without monitoring/tracing.
      class NullInstrumentation
        include Core::Ports::Instrumentation

        def measure(_metric, &)
          return unless block_given?

          yield
        end

        def annotate(_payload)
          nil
        end
      end
    end
  end
end
