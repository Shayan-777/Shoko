# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Base strategy type for pagination session operations.
        class PaginationStrategy
          def initialize(session)
            @session = session
          end

          private

          attr_reader :session
        end
      end
    end
  end
end
