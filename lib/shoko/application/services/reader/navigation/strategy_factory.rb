# frozen_string_literal: true

require_relative 'nav_context'

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
        # Chooses the appropriate navigation strategy for the current mode.
        module StrategyFactory
          module_function

          def select(context)
            context.mode == :dynamic ? DynamicStrategy : AbsoluteStrategy
          end
        end
        end
      end
    end
  end
end
