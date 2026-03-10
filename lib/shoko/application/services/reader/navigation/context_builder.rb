# frozen_string_literal: true

require_relative 'nav_context'
require_relative 'context_helpers'

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
          # Builds navigation context snapshots from the current state.
          # Uses session stores rather than state-slice ports.
          class ContextBuilder
            def initialize(app_config_store:, reader_session_store:, page_calculator: nil)
              @app_config_store = app_config_store
              @reader_session_store = reader_session_store
              @page_calculator = page_calculator
            end

            def build
              snapshot = build_snapshot
              build_context_from_snapshot(snapshot)
            end

            private

            attr_reader :page_calculator

            def build_snapshot
              ContextHelpers.build_snapshot(
                config_snapshot: @app_config_store.load,
                reader_snapshot: @reader_session_store.load
              )
            end

            def build_context_from_snapshot(snapshot)
              NavContext.new(
                mode: ContextHelpers.dynamic_mode?(snapshot) ? :dynamic : :absolute,
                view_mode: ContextHelpers.current_view_mode(snapshot),
                current_chapter: ContextHelpers.current_chapter(snapshot),
                total_chapters: ContextHelpers.total_chapters(snapshot),
                current_page_index: ContextHelpers.current_page_index(snapshot),
                dynamic_total_pages: dynamic_total_pages,
                single_page: ContextHelpers.single_page(snapshot),
                left_page: ContextHelpers.left_page(snapshot),
                right_page: ContextHelpers.right_page(snapshot),
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
