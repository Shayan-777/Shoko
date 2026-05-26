# frozen_string_literal: true

require_relative '../../application/ports/outbound/clock'

module Shoko
  module Adapters
    module Runtime
      # Clock adapter backed by Process.clock_gettime(CLOCK_MONOTONIC).
      class MonotonicClockAdapter
        include Shoko::Application::Ports::Outbound::Clock

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
