# frozen_string_literal: true

require_relative 'strategy'

module Shoko
  module Application
    module Services
      module Pagination
        # Dynamic pagination behavior.
        class DynamicStrategy < PaginationStrategy
          def build_full_map(progress: nil)
            session.build_dynamic_map(progress: progress)
            nil
          end

          def build_initial_map(progress:)
            build_full_map(progress: progress)
          end

          def refresh_after_resize(progress: nil)
            session.build_dynamic_map(progress: progress)
            session.clamp_dynamic_index!
          end

          def rebuild_after_config_change
            payload = session.pending_progress_payload
            session.update_reader(pending_progress: payload)
            session.build_dynamic_map
            session.clamp_dynamic_index!
          end

          def rebuild_dynamic(progress:)
            payload = session.pending_progress_payload
            session.with_loading('Rebuilding pagination…') do
              session.update_reader(pending_progress: payload)
              session.build_dynamic_map(progress: progress)
            end
            :handled
          end
        end
      end
    end
  end
end
