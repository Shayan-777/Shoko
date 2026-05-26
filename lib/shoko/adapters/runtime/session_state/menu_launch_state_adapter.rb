# frozen_string_literal: true

require_relative '../../../application/ports/outbound/menu_launch_state'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # In-memory runtime launch state for menu->reader handoff metadata.
        class MenuLaunchStateAdapter
          include Shoko::Application::Ports::Outbound::MenuLaunchState

          attr_accessor :last_opened_path

          def clear_last_opened_path
            @last_opened_path = nil
          end
        end
      end
    end
  end
end
