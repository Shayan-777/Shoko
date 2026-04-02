# frozen_string_literal: true

require_relative 'dynamic_strategy'
require_relative 'absolute_strategy'

module Shoko
  module Application
    module Services
      module Pagination
        # Factory for selecting per-mode pagination strategies.
        module PaginationStrategyFactory
          module_function

          def select(session)
            mode = session.config_snapshot.page_numbering_mode
            mode == :dynamic ? DynamicStrategy : AbsoluteStrategy
          end
        end
      end
    end
  end
end
