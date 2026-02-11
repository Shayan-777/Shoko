# frozen_string_literal: true

require_relative '../../core/ports/clock'

module Shoko
  module Adapters
    module Runtime
      # Clock adapter backed by Process.clock_gettime(CLOCK_MONOTONIC).
      class MonotonicClockAdapter
        include Shoko::Core::Ports::Clock

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
