# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Applies cached pagination to the live stores after a preload hit.
        class PaginationCacheStateHydrator
          def initialize(page_calculator:, app_config_store:, reader_session_store:, reader_state_reader:,
                         reader_pagination_store:)
            @page_calculator = page_calculator
            @app_config_store = app_config_store
            @reader_session_store = reader_session_store
            @reader_state_reader = reader_state_reader
            @reader_pagination_store = reader_pagination_store
          end

          def hydrate(doc:, cached_pages:, dimensions:, layout:)
            apply_layout_config(layout)
            payload = @page_calculator.hydrate_from_cache(
              cached_pages,
              doc: doc,
              width: dimensions.width,
              height: dimensions.height
            )
            persist_cached_payload(payload)
            apply_cached_restore(@page_calculator.apply_pending_precise_restore!(@reader_state_reader))
          end

          private

          def apply_layout_config(layout)
            @reader_pagination_store.save(current_pagination.with(last_width: layout.width, last_height: layout.height))
            updates = {}
            updates[:view_mode] = layout.view_mode if layout.view_mode
            updates[:line_spacing] = layout.line_spacing if layout.line_spacing
            return if updates.empty?

            @app_config_store.save(current_config.with(**updates))
          end

          def persist_cached_payload(payload)
            return unless payload

            @reader_pagination_store.save(current_pagination.with(**payload))
          end

          def apply_cached_restore(restore)
            return unless restore

            updates = {}
            index = restore[:current_page_index]
            updates[:current_page_index] = index if restore.key?(:current_page_index) && !index.nil?
            updates[:pending_progress] = nil if restore[:clear_pending_progress]
            return if updates.empty?

            @reader_session_store.save(current_reader.with(**updates))
          end

          def current_config
            @app_config_store.load
          end

          def current_reader
            @reader_session_store.load
          end

          def current_pagination
            @reader_pagination_store.load
          end
        end
      end
    end
  end
end
