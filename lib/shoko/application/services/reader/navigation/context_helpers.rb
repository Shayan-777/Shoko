# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
          # Helpers for extracting navigation-relevant values from a state snapshot.
          # These are pure functions that work on hash snapshots, keeping them
          # decoupled from specific state store implementations.
          module ContextHelpers
            module_function

            def dynamic_mode?(snapshot)
              mode = snapshot[:page_numbering_mode]
              mode == :dynamic
            end

            def current_view_mode(snapshot)
              snapshot[:view_mode] || :single
            end

            def current_chapter(snapshot)
              snapshot[:current_chapter] || 0
            end

            def total_chapters(snapshot)
              snapshot[:total_chapters] || 0
            end

            def current_page_index(snapshot)
              snapshot[:current_page_index] || 0
            end

            def current_page(snapshot)
              snapshot[:current_page] || 0
            end

            def single_page(snapshot)
              snapshot[:single_page] || current_page(snapshot)
            end

            def left_page(snapshot)
              snapshot[:left_page] || current_page(snapshot)
            end

            def right_page(snapshot)
              snapshot[:right_page] || 0
            end

            def page_map(snapshot)
              snapshot[:page_map] || []
            end

            def build_snapshot(
              config_snapshot:,
              reader_session_snapshot:,
              reader_pagination_snapshot:,
              terminal_size: nil
            )
              {
                page_numbering_mode: config_snapshot.page_numbering_mode,
                view_mode: config_snapshot.view_mode,
                line_spacing: config_snapshot.line_spacing,
                current_chapter: reader_session_snapshot.current_chapter,
                total_chapters: reader_session_snapshot.total_chapters,
                current_page_index: reader_session_snapshot.current_page_index,
                current_page: reader_session_snapshot.current_page,
                single_page: reader_session_snapshot.single_page,
                left_page: reader_session_snapshot.left_page,
                right_page: reader_session_snapshot.right_page,
                page_map: reader_pagination_snapshot.page_map,
                terminal_width: terminal_size&.width,
                terminal_height: terminal_size&.height,
              }
            end
          end
        end
      end
    end
  end
end
