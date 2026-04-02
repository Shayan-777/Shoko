# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Synchronizes reader/view/pagination snapshot persistence for pagination sessions.
        class PaginationSessionStateSync
          attr_reader :reader_session_snapshot,
                      :reader_session_store,
                      :reader_view_state_store,
                      :reader_pagination_store

          def initialize(
            reader_session_snapshot:,
            reader_session_store:,
            reader_view_state_store:,
            reader_pagination_store:
          )
            @reader_session_snapshot = reader_session_snapshot
            @reader_session_store = reader_session_store
            @reader_view_state_store = reader_view_state_store
            @reader_pagination_store = reader_pagination_store
          end

          def persist_session(**attrs)
            snapshot = @reader_session_snapshot.with(**attrs)
            @reader_session_snapshot = @reader_session_store.save(snapshot)
          end

          def persist_view(**attrs)
            snapshot = @reader_view_state_store.load.with(**attrs)
            @reader_view_state_store.save(snapshot)
          end

          def persist_pagination(**attrs)
            snapshot = @reader_pagination_store.load.with(**attrs)
            @reader_pagination_store.save(snapshot)
          end
        end
      end
    end
  end
end
