# frozen_string_literal: true

require_relative '../../adapters/output/render_registry.rb'

module Shoko
  module Application
    module Selectors
      # Selectors for reader state - provides read-only access to state
      # Replaces direct state access and convenience methods
      module ReaderSelectors
        # Chapter and page selectors
        def self.current_chapter(state)
          state.get(%i[reader current_chapter])
        end

        def self.current_page_index(state)
          state.get(%i[reader current_page_index])
        end

        def self.current_page(state)
          current_page_index(state) + 1
        end

        def self.left_page(state)
          state.get(%i[reader left_page])
        end

        def self.right_page(state)
          state.get(%i[reader right_page])
        end

        def self.single_page(state)
          state.get(%i[reader single_page])
        end

        # Mode and UI state selectors
        def self.mode(state)
          state.get(%i[reader mode])
        end

        def self.selection(state)
          state.get(%i[reader selection])
        end

        def self.message(state)
          state.get(%i[reader message])
        end

        def self.running(state)
          state.get(%i[reader running])
        end

        def self.running?(state)
          running(state)
        end

        # List selectors
        def self.bookmarks(state)
          state.get(%i[reader bookmarks]) || []
        end

        def self.annotations(state)
          state.get(%i[reader annotations]) || []
        end

        # Pagination selectors
        def self.page_map(state)
          state.get(%i[reader page_map]) || []
        end

        def self.total_pages(state)
          state.get(%i[reader total_pages])
        end

        def self.pages_per_chapter(state)
          state.get(%i[reader pages_per_chapter]) || []
        end

        # Dynamic pagination selectors
        def self.dynamic_page_map(state)
          state.get(%i[reader dynamic_page_map])
        end

        def self.dynamic_total_pages(state)
          state.get(%i[reader dynamic_total_pages])
        end

        def self.dynamic_chapter_starts(state)
          state.get(%i[reader dynamic_chapter_starts]) || []
        end

        # Terminal sizing selectors
        def self.last_width(state)
          state.get(%i[reader last_width])
        end

        def self.last_height(state)
          state.get(%i[reader last_height])
        end

        def self.last_dynamic_width(state)
          state.get(%i[reader last_dynamic_width])
        end

        def self.last_dynamic_height(state)
          state.get(%i[reader last_dynamic_height])
        end

        def self.terminal_size_changed?(state, width, height)
          width != last_width(state) || height != last_height(state)
        end

        # UI state selectors
        def self.rendered_lines(state)
          registry = begin
            state.resolve(:render_registry)
          rescue StandardError
            nil
          end
          registry ||= begin
            Shoko::Adapters::Output::RenderRegistry.current
          rescue StandardError
            nil
          end

          lines = registry&.lines
          return lines if lines.is_a?(Hash)

          fallback = state.get(%i[reader rendered_lines])
          return {} if fallback == :render_registry

          fallback.is_a?(Hash) ? fallback : {}
        end

        def self.popup_menu(state)
          state.get(%i[reader popup_menu])
        end

        def self.annotations_overlay(state)
          state.get(%i[reader annotations_overlay])
        end

        def self.annotation_editor_overlay(state)
          state.get(%i[reader annotation_editor_overlay])
        end

        # Sidebar selectors
        def self.sidebar_visible(state)
          state.get(%i[reader sidebar_visible])
        end

        def self.sidebar_visible?(state)
          sidebar_visible(state)
        end

        def self.sidebar_active_tab(state)
          state.get(%i[reader sidebar_active_tab])
        end

        def self.sidebar_toc_selected(state)
          state.get(%i[reader sidebar_toc_selected])
        end

        def self.sidebar_toc_collapsed(state)
          state.get(%i[reader sidebar_toc_collapsed])
        end

        def self.sidebar_annotations_selected(state)
          state.get(%i[reader sidebar_annotations_selected])
        end

        def self.sidebar_bookmarks_selected(state)
          state.get(%i[reader sidebar_bookmarks_selected])
        end

        def self.sidebar_toc_filter(state)
          state.get(%i[reader sidebar_toc_filter])
        end

        def self.sidebar_toc_filter_active(state)
          state.get(%i[reader sidebar_toc_filter_active])
        end

        def self.sidebar_toc_filter_active?(state)
          sidebar_toc_filter_active(state)
        end
      end
    end
  end
end
