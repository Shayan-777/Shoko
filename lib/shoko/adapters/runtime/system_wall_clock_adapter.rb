# frozen_string_literal: true

require_relative '../../core/ports/outbound/wall_clock'

module Shoko
  module Adapters
    module Runtime
      # Port adapter for system wall-clock time.
      class SystemWallClockAdapter
        include Shoko::Core::Ports::Outbound::WallClock

        def utc_now
          Time.now.utc
        end
      end
    end
  end
end
