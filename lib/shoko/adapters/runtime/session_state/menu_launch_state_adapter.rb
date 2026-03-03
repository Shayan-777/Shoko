# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_launch_state'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # In-memory runtime launch state for menu->reader handoff metadata.
        class MenuLaunchStateAdapter
          include Shoko::Core::Ports::Outbound::MenuLaunchState

          def initialize
            @last_opened_path = nil
          end

          def last_opened_path
            @last_opened_path
          end

          def set_last_opened_path(path)
            @last_opened_path = path
          end

          def clear_last_opened_path
            @last_opened_path = nil
          end
        end
      end
    end
  end
end
