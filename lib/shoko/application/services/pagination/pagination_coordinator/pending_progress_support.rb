# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Pending-progress restore helpers for PaginationCoordinator.
        module PaginationCoordinatorPendingProgressSupport
          private

          def pending_progress_ready?
            @page_calculator &&
              current_config.page_numbering_mode == :dynamic &&
              @page_calculator.total_pages.to_i.positive?
          end

          def apply_pending_restore(reader_snapshot, restore)
            return unless restore

            updates = pending_restore_updates(restore)
            @reader_session_store.save(reader_snapshot.with(**updates)) unless updates.empty?
          end

          def pending_restore_updates(restore)
            updates = {}
            index = restore[:current_page_index]
            updates[:current_page_index] = index if restore.key?(:current_page_index) && !index.nil?
            updates[:pending_progress] = nil if restore[:clear_pending_progress]
            updates
          end
        end
      end
    end
  end
end
