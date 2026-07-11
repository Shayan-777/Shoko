# frozen_string_literal: true

require_relative 'nav_context'
require_relative 'snapshot_queries'

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
          # Builds navigation context snapshots from the current state.
          # Uses session stores rather than state-slice ports.
          class ContextBuilder
            def initialize(app_config_store:, reader_session_store:, reader_state_reader:, page_calculator: nil)
              @app_config_store = app_config_store
              @reader_session_store = reader_session_store
              @reader_state_reader = reader_state_reader
              @page_calculator = page_calculator
            end

            def build
              snapshot = build_snapshot
              build_context_from_snapshot(snapshot)
            end

            private

            attr_reader :page_calculator

            def build_snapshot
              SnapshotQueries.build_snapshot(
                config_snapshot: @app_config_store.load,
                reader_session_snapshot: @reader_session_store.load,
                reader_pagination_snapshot: @reader_state_reader.load
              )
            end

            def build_context_from_snapshot(snapshot)
              NavContext.new(
                mode: SnapshotQueries.dynamic_mode?(snapshot) ? :dynamic : :absolute,
                view_mode: SnapshotQueries.current_view_mode(snapshot),
                current_chapter: SnapshotQueries.current_chapter(snapshot),
                total_chapters: SnapshotQueries.total_chapters(snapshot),
                current_page_index: SnapshotQueries.current_page_index(snapshot),
                dynamic_total_pages: dynamic_total_pages,
                single_page: SnapshotQueries.single_page(snapshot),
                left_page: SnapshotQueries.left_page(snapshot),
                right_page: SnapshotQueries.right_page(snapshot),
                max_page_in_chapter: 0,
                lines_per_page: 0,
                column_lines_per_page: 0,
                max_offset_in_chapter: 0
              )
            end

            def dynamic_total_pages
              return 0 unless page_calculator

              page_calculator.total_pages.to_i
            end
          end
        end
      end
    end
  end
end
