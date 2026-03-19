# frozen_string_literal: true

require_relative '../../../shared/type_coercion'

require_relative 'base_component'
require_relative 'tooltip_overlay_component/geometry_highlight_support'
require_relative 'tooltip_overlay_component/search_highlight_support'
require_relative '../../../shared/terminal/text_metrics'
require_relative '../../../core/models/selection_anchor'
module Shoko
  module Adapters
    module Ui
      module Components
        # Unified overlay component that handles all tooltip/popup rendering
        # including text selection highlighting, popup menus, and annotations.
        #
        # This component consolidates the scattered rendering logic and provides
        # consistent coordinate handling for the fragile tooltip system.
        class TooltipOverlayComponent < BaseComponent
          include Adapters::Ui::Constants::Ui
          include GeometryHighlightSupport
          include SearchHighlightSupport

          SEARCH_CONTEXT_WINDOW = 48

          def initialize(coordinate_service:, reader_state_reader:, rendered_content_reader:)
            super()
            @coordinate_service = coordinate_service
            @reader_state_reader = reader_state_reader
            @rendered_content_reader = rendered_content_reader
            @last_selection_segments = []
            @last_search_highlight_segments = []
            @geometry_cache_key = nil
            @geometry_cache = nil
          end

          # Render all overlay elements: highlights, popups, tooltips
          def do_render(surface, bounds)
            # Render in specific order to ensure proper layering
            clear_previous_selection_artifacts(surface, bounds)
            clear_previous_search_highlight_artifacts(surface, bounds)
            render_saved_annotations(surface, bounds)
            render_search_landing_highlight(surface, bounds)
            render_active_selection(surface, bounds)
            render_popup_menu(surface, bounds)
            render_annotations_overlay(surface, bounds)
            render_annotation_editor_overlay(surface, bounds)
            render_dictionary_popup(surface, bounds)
            render_in_book_search_popup(surface, bounds)
            render_toast_notification(surface, bounds)
          end

          private

          attr_reader :reader_state_reader, :rendered_content_reader

          def render_saved_annotations(surface, bounds)
            anns = reader_state_reader&.annotations
            return unless anns

            current_ch = reader_state_reader&.current_chapter || 0
            chapter_annotations = anns.select { |annotation| annotation['chapter_index'] == current_ch }
            chapter_annotations.each do |annotation|
              render_text_highlight(surface, bounds, annotation['range'], HIGHLIGHT_BG_SAVED)
            end
          end

          def render_active_selection(surface, bounds)
            # Render current selection highlight
            selection_range = reader_state_reader&.selection

            unless selection_range
              # No active selection; keep any previously rendered segments for one clear pass
              @pending_clear = true if @last_selection_segments.any?
              return
            end

            # Reset tracking for this frame
            @last_selection_segments.clear
            @pending_clear = false
            render_text_highlight(surface, bounds, selection_range, HIGHLIGHT_BG_ACTIVE)
          end

          def render_popup_menu(surface, bounds)
            popup_menu = reader_state_reader&.popup_menu
            return unless popup_menu&.visible

            # Unified component rendering path
            popup_menu.render(surface, bounds)
          end

          def render_annotations_overlay(surface, bounds)
            overlay = reader_state_reader&.annotations_overlay
            return unless overlay&.visible? == true

            overlay.render(surface, bounds)
          end

          def render_annotation_editor_overlay(surface, bounds)
            overlay = reader_state_reader&.annotation_editor_overlay
            return unless overlay&.visible? == true

            overlay.render(surface, bounds)
          end

          def render_dictionary_popup(surface, bounds)
            popup = reader_state_reader&.dictionary_popup
            return unless popup&.visible? == true

            popup.render(surface, bounds)
          end

          def render_in_book_search_popup(surface, bounds)
            popup = reader_state_reader&.in_book_search_popup
            return unless popup&.visible? == true

            popup.render(surface, bounds)
          end

          def render_toast_notification(surface, bounds)
            message = reader_state_reader&.message.to_s
            return if message.empty?

            ui = Adapters::Ui::Constants::Ui
            width = bounds.width
            max_width = [width - 2, 1].max
            label_max = [max_width - 1, 1].max
            label = " #{message} "
            label = Shoko::Shared::Terminal::TextMetrics.truncate_to(label, label_max)
            content = "|#{label}"
            col = [width - Shoko::Shared::Terminal::TextMetrics.visible_length(content) + 1, 1].max

            toast = "#{Shoko::Shared::Terminal::Ansi::RESET}#{ui::TOAST_ACCENT}|#{ui::TOAST_FG}#{label}#{Shoko::Shared::Terminal::Ansi::RESET}"
            surface.write(bounds, 1, col, toast)
          end

          def monotonic_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end

          # Column bounds and overlap checks are now handled by CoordinateService
        end
      end
    end
  end
end
