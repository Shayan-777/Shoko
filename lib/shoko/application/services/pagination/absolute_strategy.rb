# frozen_string_literal: true

require_relative 'strategy'

module Shoko
  module Application
    module Services
      module Pagination
        # Absolute pagination behavior.
        class AbsoluteStrategy < PaginationStrategy
          def build_full_map(progress: nil)
            session.build_absolute_map(progress: progress)
          end

          def build_initial_map(progress:)
            build_full_map(progress: progress)
          end

          def refresh_after_resize
            session.build_absolute_map
          end

          def rebuild_after_config_change
            session.build_absolute_map
          end

          def rebuild_dynamic(progress: nil) # rubocop:disable Lint/UnusedMethodArgument
            :pass
          end
        end
      end
    end
  end
end
