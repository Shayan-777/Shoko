# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../ui/box_drawer'
require_relative 'annotation_rendering_helpers'

module Shoko
  module Adapters::Output::Ui::Components
    module Screens
      # Detailed view for a single annotation selected from the list
      class AnnotationDetailScreenComponent < BaseComponent
        include Adapters::Output::Ui::Constants::UI
        include UI::BoxDrawer
        include AnnotationScreenRendering

        def initialize(state, dependencies: nil)
          super()
          @state = state
          @dependencies = dependencies
          @menu_state_reader = nil
          @render_context = nil
        end

        def do_render(surface, bounds)
          @render_context = build_context(surface, bounds)
          render_header
          return render_empty(context.surface, context.bounds) unless context.annotation

          render_body
        ensure
          @render_context = nil
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def build_context(surface, bounds)
          annotation = selected_annotation
          build_annotation_context(
            surface, bounds,
            annotation ? AnnotationView.new(annotation) : nil,
            resolve_book_label(@state)
          )
        end

        def render_header
          title_plain = "📝 Annotation • #{context.book_label}"
          title_width = render_screen_title(context, title_plain)
          render_right_aligned_text(context, '[o] Open • [e] Edit • [d] Delete • [ESC] Back', title_width)
          render_screen_divider(context)
        end

        def render_metadata
          annotation = context.annotation
          page_meta = annotation.page_meta
          meta_line = [
            "Ch: #{annotation.chapter_index || '-'}",
            page_meta && "Page: #{page_meta}",
            "Saved: #{annotation.formatted_date}",
          ].compact.join('   ')
          context.surface.write(context.bounds, 3, 2, COLOR_TEXT_DIM + meta_line + context.reset)
        end

        def render_body
          render_metadata
          text_box = build_selected_text_box(context, context.annotation.text)
          render_annotation_text_box(text_box, context, color_prefix: COLOR_TEXT_PRIMARY)
          render_annotation_text_box(note_box(text_box), context, color_prefix: COLOR_TEXT_PRIMARY)
        end

        def note_box(text_box)
          text_box.next_box(
            total_height: context.height,
            label: 'Note',
            text: context.annotation.note,
            style: :markup
          )
        end

        def context
          @render_context
        end

        def selected_annotation
          ann = menu_state_reader&.selected_annotation
          ann if ann.is_a?(Hash)
        end

        def menu_state_reader
          return @menu_state_reader if @menu_state_reader

          @menu_state_reader = @dependencies&.menu_state_reader
        end
      end
    end
  end
end
