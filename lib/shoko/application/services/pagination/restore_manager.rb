# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Owns pending-progress capture, restore application, and dynamic index clamping.
        class PaginationRestoreManager
          def initialize(page_calculator:, state_sync:, layout_spec:)
            @page_calculator = page_calculator
            @state_sync = state_sync
            @layout_spec = layout_spec
          end

          def pending_progress_payload
            snapshot = @state_sync.reader_session_snapshot
            page = @page_calculator.get_page(
              snapshot.current_page_index.to_i,
              width: @layout_spec.width,
              height: @layout_spec.height,
              sidebar_visible: @layout_spec.layout_variant == :sidebar
            )
            {
              chapter_index: snapshot.current_chapter,
              line_offset: page ? page[:start_line] : 0,
            }
          end

          def apply_restore_payload(payload)
            return unless payload.is_a?(Hash)

            index = payload[:current_page_index]
            @state_sync.persist_session(current_page_index: index) if payload.key?(:current_page_index) && !index.nil?
            @state_sync.persist_session(pending_progress: nil) if payload[:clear_pending_progress]
          end

          def clamp_dynamic_index!
            total = @page_calculator.total_pages.to_i
            return if total <= 0

            current = @state_sync.reader_session_snapshot.current_page_index.to_i
            @state_sync.persist_session(current_page_index: current.clamp(0, total - 1))
          end
        end
      end
    end
  end
end
